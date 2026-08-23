import 'dart:math' as math;

/// Medio físico que separa al rescatista de la baliza. Determina el exponente
/// de pérdida de trayecto del modelo log-distancia.
///
/// Los valores son los rangos aceptados en la literatura de propagación en
/// interiores a 2.4 GHz. El caso [rubble] es una extrapolación conservadora:
/// hormigón fragmentado, varilla y mobiliario atenúan más que un muro limpio.
enum PropagationEnvironment {
  /// Campo abierto, línea de vista. Plaza, parque, vía despejada.
  openField('Campo abierto', 2.0),

  /// Interior convencional: oficinas, vivienda en pie, muros y puertas.
  indoor('Interior', 2.8),

  /// Estructura colapsada. Es el escenario por defecto tras un sismo.
  rubble('Escombros', 3.5);

  const PropagationEnvironment(this.label, this.pathLossExponent);
  final String label;
  final double pathLossExponent;
}

/// Banda de cercanía que se le muestra al rescatista.
///
/// Deliberadamente **no** se le muestra un número con decimales. El RSSI es
/// demasiado ruidoso para justificar "3,2 m", y una cifra precisa induce a
/// confiar en ella. Bandas anchas comunican la incertidumbre real y sirven
/// igual para la única maniobra que importa: caminar y ver si mejora.
enum ProximityBand {
  /// A menos de 2 m. Debería poder oírse o tocarse.
  immediate('Inmediato', 'A menos de 2 metros'),

  /// Entre 2 y 5 m. Mismo cuarto o al otro lado de una losa.
  near('Cerca', 'Entre 2 y 5 metros'),

  /// Entre 5 y 15 m. Mismo piso o piso contiguo.
  medium('Media', 'Entre 5 y 15 metros'),

  /// Más de 15 m. Hay señal, pero falta acercarse.
  far('Lejos', 'Más de 15 metros'),

  /// Sin lecturas suficientes para afirmar nada.
  unknown('Sin dato', 'Señal insuficiente');

  const ProximityBand(this.label, this.description);
  final String label;
  final String description;
}

/// Resultado de una estimación, con su incertidumbre explícita.
class DistanceEstimate {
  const DistanceEstimate({
    required this.meters,
    required this.band,
    required this.confidence,
    required this.sampleCount,
  });

  /// Estimación puntual en metros. Úsese sólo para ordenar, nunca para
  /// mostrarla cruda al usuario.
  final double meters;

  final ProximityBand band;

  /// 0.0 a 1.0. Crece con el número de muestras y decae con su dispersión.
  final double confidence;

  final int sampleCount;

  /// Estimación vacía, cuando aún no hay lecturas.
  static const DistanceEstimate none = DistanceEstimate(
    meters: double.infinity,
    band: ProximityBand.unknown,
    confidence: 0,
    sampleCount: 0,
  );

  bool get isUsable => band != ProximityBand.unknown;

  @override
  String toString() =>
      'DistanceEstimate(${meters.toStringAsFixed(1)} m, ${band.label}, '
      'conf ${(confidence * 100).round()}%, n=$sampleCount)';
}

/// Convierte potencia de señal recibida (RSSI, en dBm) en una estimación de
/// distancia mediante el modelo log-distancia de pérdida de trayecto:
///
///     d = 10 ^ ((P1m − RSSI) / (10 · n))
///
/// donde `P1m` es el RSSI de referencia medido a un metro y `n` el exponente
/// de pérdida del medio.
///
/// ## Advertencia de diseño
///
/// Este modelo es malo. Todos los modelos RSSI lo son: la orientación del
/// cuerpo, el modelo de teléfono, la humedad y una pared cambian la lectura
/// varios decibelios. Se usa igual porque la alternativa —no dar ninguna
/// pista de distancia— es peor, y porque el rescatista no necesita la
/// distancia: necesita saber **si se está acercando**. Por eso la clase expone
/// tendencia y bandas, y guarda la cifra exacta para uso interno.
class DistanceEstimator {
  const DistanceEstimator({
    this.referenceRssiAtOneMeter = -59,
    this.environment = PropagationEnvironment.rubble,
    this.windowSize = 8,
  }) : assert(windowSize > 0, 'la ventana debe tener al menos una muestra');

  /// RSSI típico a un metro para radios BLE de teléfono. −59 dBm es el valor
  /// que usan como referencia las implementaciones iBeacon de Apple.
  final int referenceRssiAtOneMeter;

  final PropagationEnvironment environment;

  /// Cuántas lecturas recientes se promedian. Ocho, a ~1 anuncio/segundo, da
  /// una respuesta de unos ocho segundos: suficiente para filtrar el ruido sin
  /// que el indicador se quede pegado mientras el rescatista camina.
  final int windowSize;

  /// Estimación instantánea a partir de una sola lectura.
  double metersFromRssi(int rssi) {
    if (rssi >= 0) return 0;
    final exponent =
        (referenceRssiAtOneMeter - rssi) / (10 * environment.pathLossExponent);
    return math.pow(10, exponent).toDouble();
  }

  /// Clasifica una distancia en metros dentro de su banda de cercanía.
  ProximityBand bandForMeters(double meters) {
    if (meters.isNaN || meters.isInfinite || meters < 0) {
      return ProximityBand.unknown;
    }
    if (meters < 2) return ProximityBand.immediate;
    if (meters < 5) return ProximityBand.near;
    if (meters < 15) return ProximityBand.medium;
    return ProximityBand.far;
  }

  /// Estima la distancia a partir de una serie de lecturas, de la más antigua
  /// a la más reciente.
  ///
  /// Se descarta el 25% de valores extremos (media recortada) antes de
  /// promediar, porque el RSSI produce con frecuencia lecturas aisladas
  /// absurdas cuando alguien pasa entre los dos dispositivos.
  DistanceEstimate estimate(List<int> rssiSamples) {
    if (rssiSamples.isEmpty) return DistanceEstimate.none;

    final window = rssiSamples.length <= windowSize
        ? List<int>.from(rssiSamples)
        : rssiSamples.sublist(rssiSamples.length - windowSize);

    final trimmed = _trimmedMean(window);
    final meters = metersFromRssi(trimmed.round());

    return DistanceEstimate(
      meters: meters,
      band: bandForMeters(meters),
      confidence: _confidence(window),
      sampleCount: window.length,
    );
  }

  /// Media recortada: ordena, descarta un cuarto de las muestras repartido
  /// entre ambos extremos y promedia el resto.
  double _trimmedMean(List<int> samples) {
    if (samples.length < 4) {
      return samples.reduce((a, b) => a + b) / samples.length;
    }
    final sorted = List<int>.from(samples)..sort();
    final cut = (sorted.length * 0.125).floor();
    final core = sorted.sublist(cut, sorted.length - cut);
    return core.reduce((a, b) => a + b) / core.length;
  }

  /// Confianza en el rango 0..1.
  ///
  /// Combina cuántas muestras hay (más es mejor, saturando en [windowSize])
  /// con qué tan dispersas están (una desviación estándar de 10 dBm o más
  /// anula la confianza por dispersión).
  double _confidence(List<int> samples) {
    final countFactor = (samples.length / windowSize).clamp(0.0, 1.0);
    if (samples.length < 2) return countFactor * 0.4;

    final mean = samples.reduce((a, b) => a + b) / samples.length;
    final variance =
        samples.map((s) => math.pow(s - mean, 2)).reduce((a, b) => a + b) /
            samples.length;
    final stdDev = math.sqrt(variance);
    final spreadFactor = (1 - (stdDev / 10)).clamp(0.0, 1.0);

    return (countFactor * 0.5 + spreadFactor * 0.5).clamp(0.0, 1.0);
  }
}

/// Hacia dónde se mueve el rescatista respecto de la baliza.
///
/// Es la información más útil de toda la pantalla de rescate: convierte una
/// búsqueda a ciegas en un juego de "caliente o frío".
enum ProximityTrend {
  closer('Te estás acercando'),
  farther('Te estás alejando'),
  steady('Sin cambio'),
  unknown('Calculando');

  const ProximityTrend(this.label);
  final String label;
}

/// Deduce la tendencia comparando la mitad reciente de la serie contra la
/// mitad anterior.
///
/// [thresholdDb] es la variación mínima en dBm para declarar un cambio; por
/// debajo de ese umbral se considera ruido y se reporta [ProximityTrend.steady].
ProximityTrend trendFromSamples(List<int> rssiSamples, {double thresholdDb = 3}) {
  if (rssiSamples.length < 4) return ProximityTrend.unknown;

  final half = rssiSamples.length ~/ 2;
  final older = rssiSamples.sublist(0, half);
  final recent = rssiSamples.sublist(rssiSamples.length - half);

  final olderMean = older.reduce((a, b) => a + b) / older.length;
  final recentMean = recent.reduce((a, b) => a + b) / recent.length;
  final delta = recentMean - olderMean;

  // RSSI menos negativo significa señal más fuerte, es decir, más cerca.
  if (delta > thresholdDb) return ProximityTrend.closer;
  if (delta < -thresholdDb) return ProximityTrend.farther;
  return ProximityTrend.steady;
}
