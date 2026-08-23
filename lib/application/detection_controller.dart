import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/ports/clock.dart';
import '../domain/ports/device_services.dart';
import '../domain/services/disaster_detector.dart';
import 'app_settings.dart';
import 'sos_controller.dart';

/// Fase del ciclo de detección automática.
enum DetectionPhase {
  /// Vigilancia apagada.
  off,

  /// Vigilando sensores, sin novedad.
  monitoring,

  /// Se detectó un evento y se está esperando la respuesta de la persona.
  awaitingResponse,

  /// La persona confirmó estar bien; se ignora el evento.
  dismissed,
}

/// Vigila los sensores y, ante un evento sísmico, pregunta si la persona está
/// bien antes de emitir auxilio por su cuenta.
///
/// ## La cuenta atrás es el corazón del diseño
///
/// Detectar un sismo es fácil; decidir qué hacer después es lo difícil. Emitir
/// auxilio de inmediato llenaría la ciudad de falsas alarmas tras cada temblor
/// sentido, y eso destruiría la utilidad de la herramienta justo cuando más se
/// necesita: un rescatista que ve cincuenta balizas falsas deja de mirarlas.
///
/// Por eso el evento sólo abre una pregunta con cuenta atrás:
///
/// - Si respondes **"Estoy bien"**, no pasa nada.
/// - Si respondes **"Necesito ayuda"**, se emite de inmediato.
/// - Si **no respondes** en [responseWindow], se emite igual.
///
/// El silencio se interpreta como emergencia porque quien queda inconsciente o
/// atrapado no puede contestar, y ése es exactamente el caso que justifica la
/// existencia de la app.
class DetectionController extends ChangeNotifier {
  DetectionController({
    required SensorSource sensors,
    required NotificationService notifications,
    required SosController sos,
    required AppSettings settings,
    required Clock clock,
    this.responseWindow = const Duration(minutes: 2),
  })  : _sensors = sensors,
        _notifications = notifications,
        _sos = sos,
        _settings = settings,
        _clock = clock {
    _detector = DisasterDetector(
      clock: clock,
      barometerAvailable: sensors.hasBarometer,
    );
  }

  final SensorSource _sensors;
  final NotificationService _notifications;
  final SosController _sos;
  final AppSettings _settings;
  final Clock _clock;

  /// Cuánto se espera la respuesta antes de emitir por cuenta propia.
  final Duration responseWindow;

  late final DisasterDetector _detector;

  StreamSubscription<SensorAnomaly>? _anomalySub;
  Timer? _countdownTimer;

  DetectionPhase _phase = DetectionPhase.off;
  DateTime? _detectedAt;
  String? _lastError;
  int _eventCount = 0;

  DetectionPhase get phase => _phase;
  bool get isMonitoring =>
      _phase == DetectionPhase.monitoring ||
      _phase == DetectionPhase.awaitingResponse;
  bool get isAwaitingResponse => _phase == DetectionPhase.awaitingResponse;
  String? get lastError => _lastError;

  /// Cuántos eventos se han confirmado en esta sesión.
  int get eventCount => _eventCount;

  bool get hasBarometer => _sensors.hasBarometer;

  /// Sensores que ahora mismo tienen una anomalía vigente. Se muestra en
  /// ajustes para que se vea que la vigilancia está viva.
  Set<SensorKind> get corroborating => _detector.corroboratingSensors;

  int get requiredSensorCount => _detector.requiredSensorCount;

  /// Tiempo restante de la cuenta atrás, o `null` si no hay ninguna en curso.
  Duration? get remaining {
    final at = _detectedAt;
    if (at == null || _phase != DetectionPhase.awaitingResponse) return null;
    final left = responseWindow - _clock.now().difference(at);
    return left.isNegative ? Duration.zero : left;
  }

  /// Progreso de la cuenta atrás, de 0 a 1.
  double get countdownProgress {
    final left = remaining;
    if (left == null) return 0;
    return 1 - (left.inMilliseconds / responseWindow.inMilliseconds);
  }

  Future<void> start() async {
    if (isMonitoring) return;
    _lastError = null;
    try {
      await _sensors.start(_settings.thresholds);
    } catch (e) {
      _lastError = 'No se pudo activar la vigilancia: $e';
      _phase = DetectionPhase.off;
      notifyListeners();
      return;
    }

    _detector.barometerAvailable = _sensors.hasBarometer;
    _anomalySub = _sensors.anomalies.listen(_onAnomaly);
    _phase = DetectionPhase.monitoring;
    notifyListeners();
  }

  Future<void> stop() async {
    _cancelCountdown();
    await _anomalySub?.cancel();
    _anomalySub = null;
    try {
      await _sensors.stop();
    } catch (_) {
      // Detener no debe fallar de cara al usuario.
    }
    _detector.resetAll();
    _phase = DetectionPhase.off;
    notifyListeners();
  }

  /// Aplica una nueva sensibilidad sin interrumpir la vigilancia.
  Future<void> applySensitivity() async {
    if (!isMonitoring) return;
    try {
      await _sensors.updateThresholds(_settings.thresholds);
    } catch (e) {
      _lastError = 'No se pudo aplicar la sensibilidad: $e';
      notifyListeners();
    }
  }

  void _onAnomaly(SensorAnomaly anomaly) {
    // Si ya se está emitiendo auxilio, detectar más eventos no aporta nada.
    if (_sos.isTransmitting) return;
    if (_phase == DetectionPhase.awaitingResponse) return;

    final verdict = _detector.record(anomaly);
    if (verdict == DetectionVerdict.disasterDetected) {
      _onDisasterDetected();
    } else {
      // Refresca la vista de sensores corroborando, si alguien la mira.
      notifyListeners();
    }
  }

  void _onDisasterDetected() {
    _eventCount++;
    _detectedAt = _clock.now();
    _phase = DetectionPhase.awaitingResponse;

    unawaited(_showQuestion());

    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final left = remaining;
      if (left == null) return;
      if (left <= Duration.zero) {
        _onNoResponse();
      } else {
        notifyListeners();
      }
    });

    notifyListeners();
  }

  Future<void> _showQuestion() async {
    try {
      await _notifications.showAreYouOkay(countdown: responseWindow);
    } catch (e) {
      debugPrint('[DetectionController] no se pudo notificar: $e');
    }
  }

  /// La persona respondió que está bien.
  Future<void> reportOkay() async {
    if (_phase != DetectionPhase.awaitingResponse) return;
    _cancelCountdown();
    _phase = DetectionPhase.dismissed;
    notifyListeners();

    await _dismissQuestion();

    // Vuelve a vigilar: tras un sismo vienen réplicas, y alguna puede ser peor
    // que la principal.
    await Future<void>.delayed(const Duration(seconds: 2));
    if (_phase == DetectionPhase.dismissed) {
      _phase = DetectionPhase.monitoring;
      notifyListeners();
    }
  }

  /// La persona pidió ayuda explícitamente.
  Future<void> reportNeedHelp() async {
    _cancelCountdown();
    await _dismissQuestion();
    _phase = DetectionPhase.monitoring;
    notifyListeners();
    await _sos.startSos(autoDetected: false, trapped: true);
  }

  /// Se agotó la cuenta atrás sin respuesta.
  Future<void> _onNoResponse() async {
    _cancelCountdown();
    await _dismissQuestion();
    _phase = DetectionPhase.monitoring;
    notifyListeners();
    await _sos.startSos(autoDetected: true);
  }

  Future<void> _dismissQuestion() async {
    try {
      await _notifications.dismissAreYouOkay();
    } catch (_) {
      // Sin consecuencias.
    }
  }

  void _cancelCountdown() {
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _detectedAt = null;
  }

  /// Dispara el ciclo completo a mano, para poder recorrerlo sin un sismo.
  @visibleForTesting
  void simulateDetection() => _onDisasterDetected();

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _anomalySub?.cancel();
    super.dispose();
  }
}
