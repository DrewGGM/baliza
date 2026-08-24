import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/entities/sos_signal.dart';
import '../domain/ports/beacon_transport.dart';
import '../domain/ports/clock.dart';
import '../domain/ports/device_services.dart';
import '../domain/services/beacon_identity.dart';
import '../domain/services/power_policy.dart';
import '../domain/value_objects/enums.dart';
import '../infrastructure/platform/foreground_service.dart';
import 'app_settings.dart';

/// En qué estado está la emisión de auxilio.
enum SosState {
  /// No se está emitiendo nada.
  idle,

  /// Emisión de auxilio activa.
  transmitting,

  /// Emitiendo "estoy bien", para que quien busque pueda descartarte.
  broadcastingSafe,

  /// El radio no está listo (apagado, sin permisos o sin soporte).
  blocked,
}

/// Orquesta la emisión de auxilio: radio, sirena, vibración y linterna.
///
/// ## Prioridad de diseño: nunca dejar de emitir
///
/// Si la sirena falla porque el altavoz está roto, o la linterna porque el
/// equipo no tiene, **la emisión de radio continúa**. Cada dispositivo
/// auxiliar se activa en su propio bloque protegido: un fallo periférico no
/// puede tumbar lo único que de verdad salva, que es la baliza.
class SosController extends ChangeNotifier {
  SosController({
    required BeaconTransmitter transmitter,
    required SirenPlayer siren,
    required SignalingDevices signaling,
    required BatterySource battery,
    required NotificationService notifications,
    required BeaconIdentity identity,
    required AppSettings settings,
    required Clock clock,
    required KeepAliveService keepAlive,
    required SettingsStore store,
    this.powerPolicy = const PowerPolicy(),
    this.refreshInterval = const Duration(seconds: 30),
  })  : _store = store,
        _keepAlive = keepAlive,
        _transmitter = transmitter,
        _siren = siren,
        _signaling = signaling,
        _battery = battery,
        _notifications = notifications,
        _identity = identity,
        _settings = settings,
        _clock = clock {
    _radioSub = _transmitter.radioState.listen(_onRadioState);
  }

  final BeaconTransmitter _transmitter;
  final SirenPlayer _siren;
  final SignalingDevices _signaling;
  final BatterySource _battery;
  final NotificationService _notifications;
  final BeaconIdentity _identity;
  final AppSettings _settings;
  final Clock _clock;
  final KeepAliveService _keepAlive;
  final SettingsStore _store;

  /// Decide qué señales auxiliares se mantienen según la batería.
  final PowerPolicy powerPolicy;

  /// Cada cuánto se refresca el contenido de la baliza (minutos y batería).
  final Duration refreshInterval;

  static const _kActive = 'sos_active';
  static const _kStartedAt = 'sos_started_at';
  static const _kAutoDetected = 'sos_auto_detected';
  static const _kTrapped = 'sos_trapped';
  static const _kBeaconId = 'sos_beacon_id';

  StreamSubscription<RadioState>? _radioSub;
  Timer? _refreshTimer;

  SosState _state = SosState.idle;
  DateTime? _startedAt;
  SosSignal? _signal;
  RadioState _radio = RadioState.unknown;
  String? _lastError;

  /// Fallos no fatales de los periféricos, para poder avisarlos sin alarmar.
  final List<String> _degradations = [];

  /// `true` si el servicio en primer plano no pudo arrancar.
  ///
  /// Se distingue del resto de degradaciones porque **no es cosmética**: sin
  /// servicio, Android detiene la emisión a los pocos minutos de apagar la
  /// pantalla. Decirle a la persona que "todo sigue con normalidad" en ese
  /// caso sería mentirle sobre lo único que importa.
  bool _keepAliveFailed = false;

  bool get keepAliveFailed => _keepAliveFailed;

  Timer? _safeTimer;
  DateTime? _safeUntil;
  PowerTier _powerTier = PowerTier.full;
  int? _batteryLevel;
  Timer? _sirenDutyTimer;

  /// Nivel de ahorro vigente.
  PowerTier get powerTier => _powerTier;

  /// Explicación de qué se apagó por batería, o `null` si no se apagó nada.
  String? get powerNotice => powerPolicy.explain(_powerTier, _batteryLevel);

  /// Estimación gruesa del tiempo de emisión restante.
  Duration? get estimatedLife =>
      powerPolicy.estimatedBeaconLife(_batteryLevel, _powerTier);

  /// `true` si se está emitiendo "estoy bien".
  bool get isBroadcastingSafe => _state == SosState.broadcastingSafe;

  SosState get state => _state;
  bool get isTransmitting => _state == SosState.transmitting;
  RadioState get radioState => _radio;
  SosSignal? get signal => _signal;
  DateTime? get startedAt => _startedAt;
  String? get lastError => _lastError;
  List<String> get degradations => List.unmodifiable(_degradations);

  /// Cuánto lleva emitiendo.
  Duration get elapsed {
    final start = _startedAt;
    if (start == null) return Duration.zero;
    return _clock.now().difference(start);
  }

  /// Identificador corto que la persona puede leerle a un rescatista.
  String get shortCode {
    final id = _signal?.beaconId ?? _identity.current;
    final hex = (id & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '${hex.substring(0, 2)}-${hex.substring(2)}';
  }

  void _onRadioState(RadioState s) {
    _radio = s;
    if (!s.isReady && _state == SosState.transmitting) {
      _state = SosState.blocked;
    } else if (s.isReady && _state == SosState.blocked) {
      _state = SosState.transmitting;
    }
    notifyListeners();
  }

  /// Inicia la emisión de auxilio.
  ///
  /// [autoDetected] distingue el disparo automático tras un sismo del que hace
  /// la persona a mano; esa diferencia viaja en la baliza y le dice al
  /// rescatista si alguien confirmó la emergencia o si el teléfono la dedujo.
  Future<void> startSos({
    bool autoDetected = false,
    bool trapped = false,
  }) async {
    if (_state == SosState.transmitting) return;

    _lastError = null;
    _degradations.clear();
    _keepAliveFailed = false;

    // Congelar el identificador es lo primero: a partir de aquí la
    // continuidad de la señal importa más que el anonimato.
    _identity.freeze();

    final flags = <SignalFlag>{
      if (autoDetected) SignalFlag.autoDetected else SignalFlag.manual,
      if (trapped) SignalFlag.trapped,
    };

    _batteryLevel = await _readBattery();
    _powerTier = powerPolicy.tierFor(_batteryLevel);

    final signal = SosSignal(
      beaconId: _identity.current,
      messageType: MessageType.sos,
      flags: flags,
      batteryPercent: _batteryLevel,
      elapsedMinutes: 0,
      peopleCount: _settings.peopleCount,
      medicalProfile: _settings.profile,
    );

    // El servicio se levanta ANTES de emitir. Si el proceso muriera entre las
    // dos llamadas, es preferible un servicio sin baliza (inofensivo) que una
    // baliza sin servicio, que el sistema mataría a los pocos minutos.
    _keepAliveFailed = false;
    try {
      await _keepAlive.start(
        title: 'Emitiendo señal de auxilio',
        body: 'Mantén el teléfono encendido y destapado.',
        buttons: const <KeepAliveButton>[
          KeepAliveButton(id: KeepAliveCommand.stopSos, text: 'Detener'),
        ],
      );
    } catch (e) {
      // Causa habitual: los permisos de Bluetooth no están concedidos. Desde
      // Android 14 un servicio de tipo `connectedDevice` sólo puede arrancar
      // si el permiso ya fue otorgado en tiempo de ejecución.
      _keepAliveFailed = true;
      debugPrint('[SosController] servicio en primer plano no disponible: $e');
    }

    try {
      await _transmitter.start(signal);
    } catch (e) {
      _lastError = 'No se pudo iniciar la emisión: $e';
      _identity.unfreeze();
      await _safely(() => _keepAlive.stop(), 'servicio en primer plano');
      _state = SosState.blocked;
      notifyListeners();
      return;
    }

    _signal = signal;
    _startedAt = _clock.now();
    _state = SosState.transmitting;

    await _startPeripherals();

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(refreshInterval, (_) => _refresh());

    await _persistActive(autoDetected: autoDetected, trapped: trapped);

    notifyListeners();
  }

  /// Guarda que hay una emisión en curso.
  ///
  /// Si el sistema mata el proceso —cosa que ocurre pese al servicio en primer
  /// plano en capas de fabricante agresivas— al volver a arrancar hay que
  /// reanudar la emisión sola. Una baliza que se apaga en silencio porque
  /// Android recicló memoria es exactamente el fallo que esta app no se puede
  /// permitir.
  Future<void> _persistActive({
    required bool autoDetected,
    required bool trapped,
  }) async {
    try {
      await _store.writeBool(_kActive, true);
      await _store.writeInt(
        _kStartedAt,
        (_startedAt ?? _clock.now()).millisecondsSinceEpoch,
      );
      await _store.writeBool(_kAutoDetected, autoDetected);
      await _store.writeBool(_kTrapped, trapped);
      // El identificador se guarda para que un reinicio no rompa el
      // seguimiento de quien ya venía siguiendo esta baliza.
      final id = _signal?.beaconId;
      if (id != null) await _store.writeInt(_kBeaconId, id);
    } catch (e) {
      debugPrint('[SosController] no se pudo persistir el estado: $e');
    }
  }

  Future<void> _clearPersisted() async {
    try {
      await _store.remove(_kActive);
      await _store.remove(_kStartedAt);
      await _store.remove(_kAutoDetected);
      await _store.remove(_kTrapped);
      await _store.remove(_kBeaconId);
    } catch (e) {
      debugPrint('[SosController] no se pudo limpiar el estado: $e');
    }
  }

  /// Reanuda una emisión que quedó interrumpida por la muerte del proceso.
  ///
  /// Devuelve `true` si había algo que reanudar. Conserva el instante de
  /// inicio original para que el cronómetro y los minutos que viajan en la
  /// baliza reflejen el tiempo real de espera, no el del reinicio.
  Future<bool> resumeIfInterrupted() async {
    try {
      if (await _store.readBool(_kActive) != true) return false;

      final startedMillis = await _store.readInt(_kStartedAt);
      final autoDetected = await _store.readBool(_kAutoDetected) ?? false;
      final trapped = await _store.readBool(_kTrapped) ?? false;
      final previousId = await _store.readInt(_kBeaconId);

      // Se restaura ANTES de emitir, para que la baliza salga ya con el
      // identificador de siempre y no llegue a anunciarse con uno nuevo.
      if (previousId != null) _identity.restore(previousId);

      await startSos(autoDetected: autoDetected, trapped: trapped);

      if (startedMillis != null && _state == SosState.transmitting) {
        _startedAt = DateTime.fromMillisecondsSinceEpoch(startedMillis);
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('[SosController] no se pudo reanudar: $e');
      return false;
    }
  }

  /// Activa sirena, vibración y linterna según preferencias. Cada una en su
  /// propio bloque: que falle una no debe impedir las otras ni cortar la
  /// emisión de radio.
  Future<void> _startPeripherals() async {
    final tier = _powerTier;

    // Cada señal exige DOS condiciones: que la persona la haya dejado activada
    // y que quede batería para permitírsela. La preferencia manda sobre lo que
    // se enciende; la batería, sobre lo que se puede sostener.
    if (_settings.siren && tier.siren) {
      await _safely(() => _siren.start(), 'sirena');
      _applySirenDutyCycle(tier);
    }
    if (_settings.vibration && tier.vibration) {
      await _safely(() => _signaling.startVibrationPattern(), 'vibración');
    }
    if (_settings.torch && tier.torch && _signaling.hasTorch) {
      await _safely(() => _signaling.startTorchPattern(), 'linterna');
    }
  }

  /// Alterna la sirena para que suene sólo una fracción del tiempo.
  ///
  /// Los silencios no son sólo ahorro: dejan oír la voz de quien busca, que
  /// con la sirena continua queda tapada.
  void _applySirenDutyCycle(PowerTier tier) {
    _sirenDutyTimer?.cancel();
    if (tier.sirenDutyCycle >= 1.0) return;

    const cycle = Duration(seconds: 20);
    final onFor = Duration(
      milliseconds: (cycle.inMilliseconds * tier.sirenDutyCycle).round(),
    );

    var sounding = true;
    _sirenDutyTimer = Timer.periodic(onFor, (timer) async {
      if (_state != SosState.transmitting) {
        timer.cancel();
        return;
      }
      sounding = !sounding;
      await _safely(
        () => sounding ? _siren.start() : _siren.stop(),
        'sirena',
      );
    });
  }

  /// Recalcula el nivel de ahorro y aplica los cambios si el nivel cambió.
  Future<void> _applyPowerTier() async {
    final next = powerPolicy.tierFor(_batteryLevel, current: _powerTier);
    if (next == _powerTier) return;

    _powerTier = next;

    if (_state != SosState.transmitting) return;

    // Se apaga lo que el nuevo nivel ya no permite y se enciende lo que
    // recupera, sin tocar la emisión de radio, que nunca se interrumpe.
    if (!next.torch) {
      await _safely(() => _signaling.stopTorch(), 'linterna');
    } else if (_settings.torch && _signaling.hasTorch) {
      await _safely(() => _signaling.startTorchPattern(), 'linterna');
    }

    if (!next.vibration) {
      await _safely(() => _signaling.stopVibration(), 'vibración');
    } else if (_settings.vibration) {
      await _safely(() => _signaling.startVibrationPattern(), 'vibración');
    }

    if (!next.siren) {
      _sirenDutyTimer?.cancel();
      await _safely(() => _siren.stop(), 'sirena');
    } else if (_settings.siren) {
      await _safely(() => _siren.start(), 'sirena');
      _applySirenDutyCycle(next);
    }

    notifyListeners();
  }

  /// Detiene toda la emisión.
  Future<void> stopSos() async {
    if (_state == SosState.idle) return;

    _refreshTimer?.cancel();
    _refreshTimer = null;
    _sirenDutyTimer?.cancel();
    _sirenDutyTimer = null;

    await _clearPersisted();

    await _safely(() => _transmitter.stop(), 'radio');
    await _safely(() => _siren.stop(), 'sirena');
    await _safely(() => _signaling.stopVibration(), 'vibración');
    await _safely(() => _signaling.stopTorch(), 'linterna');
    await _safely(() => _notifications.clearAll(), 'avisos');
    await _safely(() => _keepAlive.stop(), 'servicio en primer plano');

    // Se reanuda la rotación y se fuerza un identificador nuevo, para que la
    // baliza usada durante la emergencia no siga siendo rastreable después.
    _identity.unfreeze();

    _state = SosState.idle;
    _startedAt = null;
    _signal = null;
    notifyListeners();
  }

  /// Emite un "estoy bien" puntual, para que quien busque pueda descartarte.
  Future<void> broadcastSafe({
    Duration duration = const Duration(minutes: 2),
  }) async {
    if (_state == SosState.transmitting) return;

    _safeUntil = _clock.now().add(duration);

    final signal = SosSignal(
      beaconId: _identity.current,
      messageType: MessageType.safe,
      batteryPercent: await _readBattery(),
      peopleCount: _settings.peopleCount,
    );

    await _safely(() => _transmitter.start(signal), 'radio');
    _signal = signal;
    _state = SosState.broadcastingSafe;
    notifyListeners();

    _safeTimer?.cancel();
    _safeTimer = Timer(duration, () async {
      if (_state != SosState.broadcastingSafe) return;
      await _safely(() => _transmitter.stop(), 'radio');
      _signal = null;
      _safeUntil = null;
      _state = SosState.idle;
      notifyListeners();
    });
  }

  /// Detiene la emisión de "estoy bien" antes de que expire sola.
  Future<void> stopSafeBroadcast() async {
    if (_state != SosState.broadcastingSafe) return;
    _safeTimer?.cancel();
    _safeTimer = null;
    await _safely(() => _transmitter.stop(), 'radio');
    _signal = null;
    _safeUntil = null;
    _state = SosState.idle;
    notifyListeners();
  }

  /// Cuánto queda de la emisión "estoy bien".
  Duration? get safeRemaining {
    final until = _safeUntil;
    if (until == null || _state != SosState.broadcastingSafe) return null;
    final left = until.difference(_clock.now());
    return left.isNegative ? Duration.zero : left;
  }

  /// Refresca el contenido de la baliza sin cortar la emisión.
  Future<void> _refresh() async {
    final current = _signal;
    if (current == null || _state != SosState.transmitting) return;

    _batteryLevel = await _readBattery();
    await _applyPowerTier();

    final updated = current.copyWith(
      elapsedMinutes: elapsed.inMinutes,
      batteryPercent: _batteryLevel,
      peopleCount: _settings.peopleCount,
      medicalProfile: _settings.profile,
    );

    await _safely(() => _transmitter.update(updated), 'radio');
    await _safely(
      () => _keepAlive.update(
        title: 'Emitiendo señal de auxilio',
        body: 'Llevas ${elapsed.inMinutes} min pidiendo ayuda.',
        buttons: const <KeepAliveButton>[
          KeepAliveButton(id: KeepAliveCommand.stopSos, text: 'Detener'),
        ],
      ),
      'servicio en primer plano',
    );
    _signal = updated;
    notifyListeners();
  }

  Future<int?> _readBattery() async {
    try {
      return await _battery.level();
    } catch (_) {
      return null;
    }
  }

  /// Ejecuta una operación de periférico registrando el fallo sin propagarlo.
  Future<void> _safely(Future<void> Function() action, String label) async {
    try {
      await action();
    } catch (e) {
      final message = 'Falló $label';
      if (!_degradations.contains(message)) _degradations.add(message);
      debugPrint('[SosController] $message: $e');
    }
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _sirenDutyTimer?.cancel();
    _safeTimer?.cancel();
    _radioSub?.cancel();
    super.dispose();
  }
}
