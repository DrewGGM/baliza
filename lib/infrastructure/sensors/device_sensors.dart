import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../domain/ports/device_services.dart';
import '../../domain/services/disaster_detector.dart';

/// Lee los sensores inerciales y barométrico y publica sólo las anomalías.
///
/// ## Por qué el umbralizado ocurre aquí y no en el dominio
///
/// A 50 Hz y con tres sensores llegan 150 muestras por segundo. Pasarlas todas
/// al dominio obligaría a despertar la lógica de decisión constantemente y a
/// tener despierta la CPU, que es justo lo que no puede hacer una app pensada
/// para durar días con la batería que quede. Aquí se compara contra el umbral
/// y se descarta el 99,9 % del caudal; sólo sube lo que ya es candidato.
///
/// ## Cómo se mide cada sensor
///
/// - **Acelerómetro**: se usa `userAccelerometerEventStream`, que ya viene con
///   la gravedad descontada. Con el acelerómetro crudo habría que restar 9,81
///   m/s² y la orientación del teléfono metería error.
/// - **Giroscopio**: módulo del vector de velocidad angular.
/// - **Barómetro**: no interesa la presión sino su **variación** respecto a
///   una media móvil. La presión absoluta cambia con el clima y la altitud;
///   un colapso estructural produce un salto brusco sobre la línea base.
class DeviceSensorSource implements SensorSource {
  DeviceSensorSource({
    this.samplingPeriod = const Duration(milliseconds: 20),
    this.minimumGap = const Duration(milliseconds: 120),
  });

  /// Periodo de muestreo. 20 ms equivale a 50 Hz, de sobra para un sismo, cuya
  /// energía se concentra por debajo de 20 Hz.
  final Duration samplingPeriod;

  /// Tiempo mínimo entre dos anomalías del mismo sensor. Evita que una sola
  /// sacudida genere una ráfaga de cincuenta eventos idénticos.
  final Duration minimumGap;

  final StreamController<SensorAnomaly> _anomalies =
      StreamController<SensorAnomaly>.broadcast();

  StreamSubscription<UserAccelerometerEvent>? _accelSub;
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  StreamSubscription<BarometerEvent>? _baroSub;

  DetectionThresholds _thresholds = const DetectionThresholds();
  final Map<SensorKind, DateTime> _lastEmitted = {};

  bool _hasBarometer = false;
  bool _listening = false;

  /// Media móvil de presión, base contra la que se mide la variación.
  double? _pressureBaseline;

  /// Peso de la muestra nueva en la media móvil. 0,05 da una constante de
  /// tiempo de unos pocos segundos: sigue los cambios meteorológicos y de
  /// altitud, pero no un pulso de colapso.
  static const double _baselineAlpha = 0.05;

  @override
  Stream<SensorAnomaly> get anomalies => _anomalies.stream;

  @override
  bool get hasBarometer => _hasBarometer;

  @override
  bool get isListening => _listening;

  @override
  Future<void> start(DetectionThresholds thresholds) async {
    if (_listening) {
      await updateThresholds(thresholds);
      return;
    }
    _thresholds = thresholds;
    _listening = true;

    _accelSub = userAccelerometerEventStream(samplingPeriod: samplingPeriod)
        .listen(_onAccelerometer, onError: _onSensorError);

    _gyroSub = gyroscopeEventStream(samplingPeriod: samplingPeriod)
        .listen(_onGyroscope, onError: _onSensorError);

    // El barómetro puede no existir. Se intenta suscribir y, si el flujo falla
    // o nunca emite, sencillamente el detector trabaja con dos sensores.
    try {
      _baroSub = barometerEventStream(samplingPeriod: samplingPeriod).listen(
        _onBarometer,
        onError: (Object e) {
          _hasBarometer = false;
          debugPrint('[DeviceSensorSource] sin barómetro: $e');
        },
      );
    } catch (e) {
      _hasBarometer = false;
      debugPrint('[DeviceSensorSource] barómetro no disponible: $e');
    }
  }

  @override
  Future<void> updateThresholds(DetectionThresholds thresholds) async {
    _thresholds = thresholds;
  }

  void _onSensorError(Object error) {
    debugPrint('[DeviceSensorSource] error de sensor: $error');
  }

  void _onAccelerometer(UserAccelerometerEvent e) {
    final magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _maybeEmit(SensorKind.accelerometer, magnitude);
  }

  void _onGyroscope(GyroscopeEvent e) {
    final magnitude = math.sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _maybeEmit(SensorKind.gyroscope, magnitude);
  }

  void _onBarometer(BarometerEvent e) {
    _hasBarometer = true;

    final baseline = _pressureBaseline;
    if (baseline == null) {
      _pressureBaseline = e.pressure;
      return;
    }

    final deviation = (e.pressure - baseline).abs();
    _pressureBaseline =
        baseline * (1 - _baselineAlpha) + e.pressure * _baselineAlpha;

    _maybeEmit(SensorKind.barometer, deviation);
  }

  /// Publica la anomalía si supera el umbral y respeta el intervalo mínimo.
  void _maybeEmit(SensorKind kind, double magnitude) {
    if (magnitude < _thresholds.forKind(kind)) return;

    final now = DateTime.now();
    final last = _lastEmitted[kind];
    if (last != null && now.difference(last) < minimumGap) return;

    _lastEmitted[kind] = now;
    if (!_anomalies.isClosed) {
      _anomalies.add(
        SensorAnomaly(kind: kind, magnitude: magnitude, at: now),
      );
    }
  }

  @override
  Future<void> stop() async {
    _listening = false;
    await _accelSub?.cancel();
    await _gyroSub?.cancel();
    await _baroSub?.cancel();
    _accelSub = null;
    _gyroSub = null;
    _baroSub = null;
    _lastEmitted.clear();
    _pressureBaseline = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _anomalies.close();
  }
}

/// Fuente de sensores controlable a mano, para el modo simulación.
///
/// Permite recorrer el ciclo completo de detección —evento, pregunta "¿estás
/// bien?", cuenta atrás y emisión automática— sin esperar a que tiemble.
class SimulatedSensorSource implements SensorSource {
  SimulatedSensorSource({bool hasBarometer = true})
      : _hasBarometer = hasBarometer;

  final bool _hasBarometer;

  final StreamController<SensorAnomaly> _anomalies =
      StreamController<SensorAnomaly>.broadcast();

  bool _listening = false;

  @override
  Stream<SensorAnomaly> get anomalies => _anomalies.stream;

  @override
  bool get hasBarometer => _hasBarometer;

  @override
  bool get isListening => _listening;

  @override
  Future<void> start(DetectionThresholds thresholds) async {
    _listening = true;
  }

  @override
  Future<void> updateThresholds(DetectionThresholds thresholds) async {}

  /// Inyecta una sacudida que corrobora todos los sensores disponibles.
  void injectQuake() {
    final now = DateTime.now();
    _anomalies.add(
      SensorAnomaly(kind: SensorKind.accelerometer, magnitude: 31, at: now),
    );
    _anomalies.add(
      SensorAnomaly(kind: SensorKind.gyroscope, magnitude: 7.9, at: now),
    );
    if (_hasBarometer) {
      _anomalies.add(
        SensorAnomaly(kind: SensorKind.barometer, magnitude: 1.4, at: now),
      );
    }
  }

  /// Inyecta una sola anomalía, para comprobar que un golpe aislado no basta.
  void injectSingle(SensorKind kind) {
    _anomalies.add(
      SensorAnomaly(kind: kind, magnitude: 30, at: DateTime.now()),
    );
  }

  @override
  Future<void> stop() async {
    _listening = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _anomalies.close();
  }
}
