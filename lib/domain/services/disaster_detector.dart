import '../ports/clock.dart';

/// Sensor inercial o barométrico que puede reportar una anomalía.
enum SensorKind {
  accelerometer('Acelerómetro'),
  gyroscope('Giroscopio'),
  barometer('Barómetro');

  const SensorKind(this.label);
  final String label;
}

/// Una lectura que superó el umbral de su sensor.
class SensorAnomaly {
  const SensorAnomaly({
    required this.kind,
    required this.magnitude,
    required this.at,
  });

  final SensorKind kind;

  /// Magnitud del evento en las unidades del sensor: m/s² para el
  /// acelerómetro, rad/s para el giroscopio, hPa de variación para el
  /// barómetro.
  final double magnitude;

  final DateTime at;

  @override
  String toString() =>
      'SensorAnomaly(${kind.label}, ${magnitude.toStringAsFixed(2)}, $at)';
}

/// Sensibilidad configurable por la persona usuaria.
///
/// Un sismo de magnitud alta se siente igual en todos los teléfonos, pero la
/// tolerancia a falsos positivos no es la misma para todo el mundo: quien
/// duerme con el teléfono en la cama quiere menos sensibilidad que quien lo
/// deja quieto sobre una mesa.
enum DetectionSensitivity {
  low('Baja', 1.6),
  medium('Media', 1.0),
  high('Alta', 0.65);

  const DetectionSensitivity(this.label, this.multiplier);
  final String label;

  /// Factor que escala todos los umbrales. Mayor multiplicador implica que
  /// hace falta un movimiento más violento para disparar.
  final double multiplier;
}

/// Umbrales de disparo por sensor.
class DetectionThresholds {
  const DetectionThresholds({
    this.accelerationMps2 = 22.0,
    this.rotationRadS = 5.5,
    this.pressureHpa = 0.6,
  });

  /// Aceleración lineal, descontada la gravedad, en m/s².
  ///
  /// 22 m/s² equivale a algo más de 2 g. Un teléfono en una mesa durante un
  /// sismo severo supera ese valor; caminar o dejarlo caer sobre un sofá no.
  final double accelerationMps2;

  /// Velocidad angular en rad/s.
  final double rotationRadS;

  /// Variación de presión en hPa. Un colapso estructural genera un pulso de
  /// presión medible en el barómetro del teléfono.
  final double pressureHpa;

  DetectionThresholds scaled(DetectionSensitivity sensitivity) {
    final m = sensitivity.multiplier;
    return DetectionThresholds(
      accelerationMps2: accelerationMps2 * m,
      rotationRadS: rotationRadS * m,
      pressureHpa: pressureHpa * m,
    );
  }

  double forKind(SensorKind kind) => switch (kind) {
        SensorKind.accelerometer => accelerationMps2,
        SensorKind.gyroscope => rotationRadS,
        SensorKind.barometer => pressureHpa,
      };
}

/// Veredicto del detector tras procesar una anomalía.
enum DetectionVerdict {
  /// No hay evidencia suficiente todavía.
  idle,

  /// Hay anomalías acumuladas pero aún no se alcanza el corroborado mínimo.
  accumulating,

  /// Evento confirmado: se dispara el aviso "¿estás bien?".
  disasterDetected,

  /// Se ignora por estar dentro del periodo de enfriamiento posterior a una
  /// detección previa (típicamente una réplica).
  suppressedByCooldown,
}

/// Correlaciona anomalías de varios sensores para decidir si ocurrió un evento
/// sísmico, evitando que un golpe accidental active una alerta.
///
/// ## Regla de decisión
///
/// Se declara evento cuando **sensores distintos** reportan anomalías dentro
/// de una misma ventana temporal:
///
/// - Con barómetro disponible: hacen falta **3** sensores dentro de
///   [corroborationWindow].
/// - Sin barómetro: hacen falta **2**, pero dentro de una ventana **más
///   estrecha** ([corroborationWindow] dividida por [narrowWindowDivisor]).
///   Al perder el tercer testigo se compensa exigiendo mayor simultaneidad.
///
/// ## Dos decisiones deliberadas
///
/// **Las anomalías caducan.** Cada anomalía se descarta en cuanto supera la
/// ventana aplicable. Sin caducidad, un golpe del acelerómetro a las 9:00 y
/// otro del giroscopio a las 18:00 podrían sumarse como si fueran simultáneos,
/// o al revés: una lectura vieja que nunca se limpia bloquea indefinidamente
/// la condición de simultaneidad. Se purga en cada evaluación.
///
/// **La ventana estrecha se aplica de verdad.** Es tentador escribir el
/// endurecimiento sin barómetro como un segundo filtro anidado dentro del
/// primero; si se hace así con umbrales mal ordenados, la condición interna
/// resulta lógicamente incompatible con la externa y nunca se ejecuta: código
/// muerto que aparenta proteger sin proteger. Aquí la ventana se selecciona
/// **antes** de evaluar, en [_windowFor], de modo que sólo hay una condición y
/// no puede volverse inalcanzable.
class DisasterDetector {
  DisasterDetector({
    required this.clock,
    this.corroborationWindow = const Duration(milliseconds: 1200),
    this.cooldown = const Duration(seconds: 30),
    this.narrowWindowDivisor = 3.0,
    bool barometerAvailable = true,
  }) : assert(narrowWindowDivisor >= 1, 'el divisor no puede encoger a cero') {
    _barometerAvailable = barometerAvailable;
  }

  final Clock clock;

  /// Ventana dentro de la cual las anomalías cuentan como simultáneas cuando
  /// hay barómetro.
  final Duration corroborationWindow;

  /// Tiempo tras una detección durante el cual no se dispara otra. Evita que
  /// una secuencia de réplicas genere una ráfaga de alertas.
  final Duration cooldown;

  /// Cuánto se estrecha la ventana cuando no hay barómetro.
  final double narrowWindowDivisor;

  late bool _barometerAvailable;

  final Map<SensorKind, SensorAnomaly> _recent = {};
  DateTime? _lastDetection;

  /// Indica si el dispositivo tiene barómetro. Muchos equipos de gama de
  /// entrada —los más frecuentes en población vulnerable— no lo tienen.
  bool get barometerAvailable => _barometerAvailable;

  set barometerAvailable(bool value) {
    if (_barometerAvailable == value) return;
    _barometerAvailable = value;
    _recent.clear();
  }

  /// Cuántos sensores distintos deben coincidir para declarar el evento.
  int get requiredSensorCount => _barometerAvailable ? 3 : 2;

  /// Ventana efectiva según la disponibilidad de barómetro.
  Duration get effectiveWindow => _windowFor(_barometerAvailable);

  Duration _windowFor(bool withBarometer) {
    if (withBarometer) return corroborationWindow;
    final micros =
        (corroborationWindow.inMicroseconds / narrowWindowDivisor).round();
    return Duration(microseconds: micros);
  }

  /// Sensores que actualmente tienen una anomalía vigente.
  Set<SensorKind> get corroboratingSensors {
    _purgeExpired(clock.now());
    return _recent.keys.toSet();
  }

  /// Registra una anomalía y devuelve el veredicto resultante.
  DetectionVerdict record(SensorAnomaly anomaly) {
    final now = clock.now();

    // Una anomalía de un barómetro implica que el barómetro existe, aunque la
    // capa de infraestructura no lo hubiera reportado.
    if (anomaly.kind == SensorKind.barometer && !_barometerAvailable) {
      _barometerAvailable = true;
    }

    final last = _lastDetection;
    if (last != null && now.difference(last) < cooldown) {
      return DetectionVerdict.suppressedByCooldown;
    }

    _recent[anomaly.kind] = anomaly;
    _purgeExpired(now);

    if (_recent.length < requiredSensorCount) {
      return _recent.isEmpty
          ? DetectionVerdict.idle
          : DetectionVerdict.accumulating;
    }

    _lastDetection = now;
    _recent.clear();
    return DetectionVerdict.disasterDetected;
  }

  /// Elimina las anomalías que quedaron fuera de la ventana vigente.
  void _purgeExpired(DateTime now) {
    final window = effectiveWindow;
    _recent.removeWhere((_, a) => now.difference(a.at) > window);
  }

  /// Descarta el estado acumulado sin tocar el enfriamiento.
  void reset() => _recent.clear();

  /// Descarta todo, incluido el enfriamiento.
  void resetAll() {
    _recent.clear();
    _lastDetection = null;
  }

  /// Instante de la última detección confirmada, o `null` si no ha habido.
  DateTime? get lastDetection => _lastDetection;

  /// `true` si el detector está dentro del periodo de enfriamiento.
  bool get isInCooldown {
    final last = _lastDetection;
    if (last == null) return false;
    return clock.now().difference(last) < cooldown;
  }
}
