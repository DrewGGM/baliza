import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/entities/sos_signal.dart';
import '../domain/ports/beacon_transport.dart';
import '../domain/ports/clock.dart';
import '../domain/ports/device_services.dart';
import '../domain/services/beacon_identity.dart';
import '../domain/value_objects/enums.dart';
import '../infrastructure/platform/foreground_service.dart';
import 'app_settings.dart';

/// En qué estado está la emisión de auxilio.
enum SosState {
  /// No se está emitiendo nada.
  idle,

  /// Emisión activa.
  transmitting,

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
    this.refreshInterval = const Duration(seconds: 30),
  })  : _keepAlive = keepAlive,
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

  /// Cada cuánto se refresca el contenido de la baliza (minutos y batería).
  final Duration refreshInterval;

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

    final signal = SosSignal(
      beaconId: _identity.current,
      messageType: MessageType.sos,
      flags: flags,
      batteryPercent: await _readBattery(),
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

    notifyListeners();
  }

  /// Activa sirena, vibración y linterna según preferencias. Cada una en su
  /// propio bloque: que falle una no debe impedir las otras ni cortar la
  /// emisión de radio.
  Future<void> _startPeripherals() async {
    if (_settings.siren) {
      await _safely(() => _siren.start(), 'sirena');
    }
    if (_settings.vibration) {
      await _safely(() => _signaling.startVibrationPattern(), 'vibración');
    }
    if (_settings.torch && _signaling.hasTorch) {
      await _safely(() => _signaling.startTorchPattern(), 'linterna');
    }
  }

  /// Detiene toda la emisión.
  Future<void> stopSos() async {
    if (_state == SosState.idle) return;

    _refreshTimer?.cancel();
    _refreshTimer = null;

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
  Future<void> broadcastSafe({Duration duration = const Duration(minutes: 2)}) async {
    if (_state == SosState.transmitting) return;

    final signal = SosSignal(
      beaconId: _identity.current,
      messageType: MessageType.safe,
      batteryPercent: await _readBattery(),
      peopleCount: _settings.peopleCount,
    );

    await _safely(() => _transmitter.start(signal), 'radio');
    _signal = signal;
    notifyListeners();

    Timer(duration, () async {
      if (_state != SosState.transmitting) {
        await _safely(() => _transmitter.stop(), 'radio');
        _signal = null;
        notifyListeners();
      }
    });
  }

  /// Refresca el contenido de la baliza sin cortar la emisión.
  Future<void> _refresh() async {
    final current = _signal;
    if (current == null || _state != SosState.transmitting) return;

    final updated = current.copyWith(
      elapsedMinutes: elapsed.inMinutes,
      batteryPercent: await _readBattery(),
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
    _radioSub?.cancel();
    super.dispose();
  }
}
