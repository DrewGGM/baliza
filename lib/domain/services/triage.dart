import '../entities/survivor.dart';
import '../value_objects/enums.dart';
import 'distance_estimator.dart';

/// Criterio con el que se ordena la lista de personas por rescatar.
enum TriageStrategy {
  /// Prioriza a quien se puede alcanzar antes. Es el criterio por defecto:
  /// en las primeras horas tras un colapso, el factor que más vidas salva es
  /// la velocidad, y la persona más cercana es la que se alcanza primero.
  proximity('Cercanía', 'Primero quien está más cerca'),

  /// Prioriza por gravedad clínica declarada en la ficha médica.
  medical('Gravedad', 'Primero quien tiene mayor riesgo médico'),

  /// Prioriza a quien lleva más tiempo pidiendo auxilio.
  elapsed('Tiempo', 'Primero quien lleva más tiempo esperando'),

  /// Prioriza los puntos con más personas: máximo rescate por intervención.
  groupSize('Personas', 'Primero donde hay más personas');

  const TriageStrategy(this.label, this.description);
  final String label;
  final String description;
}

/// Puntúa y ordena balizas para guiar la decisión de a quién atender primero.
///
/// ## Advertencia
///
/// Esto **no es un protocolo de triaje clínico**. START, SALT o cualquier
/// protocolo real exigen valorar a la persona en sitio: respiración, pulso,
/// estado de conciencia. Nada de eso cabe en una baliza de 16 bytes.
///
/// Lo que hace este ordenamiento es resolver una pregunta anterior y mucho más
/// modesta: cuando hay ocho señales en pantalla y un solo equipo, ¿por cuál
/// empezar? La decisión final siempre es del rescatista, y la interfaz nunca
/// oculta las demás señales ni impide saltarse el orden propuesto.
class TriageRanker {
  const TriageRanker({
    this.estimator = const DistanceEstimator(),
    this.strategy = TriageStrategy.proximity,
  });

  final DistanceEstimator estimator;
  final TriageStrategy strategy;

  TriageRanker withStrategy(TriageStrategy s) =>
      TriageRanker(estimator: estimator, strategy: s);

  /// Puntúa una baliza en el rango 0..1000. Mayor puntaje, mayor prioridad.
  ///
  /// El puntaje mezcla siempre los cuatro factores; la estrategia sólo cambia
  /// el peso del factor dominante. Así, aun ordenando por cercanía, entre dos
  /// personas igual de cerca sube primero la que está más grave.
  int score(Survivor survivor, DateTime now) {
    final proximityScore = _proximityScore(survivor);
    final medicalScore = _medicalScore(survivor);
    final elapsedScore = _elapsedScore(survivor);
    final groupScore = _groupScore(survivor);

    final weights = switch (strategy) {
      TriageStrategy.proximity => (p: 0.55, m: 0.20, e: 0.10, g: 0.15),
      TriageStrategy.medical => (p: 0.20, m: 0.55, e: 0.10, g: 0.15),
      TriageStrategy.elapsed => (p: 0.20, m: 0.15, e: 0.55, g: 0.10),
      TriageStrategy.groupSize => (p: 0.20, m: 0.15, e: 0.10, g: 0.55),
    };

    final combined = proximityScore * weights.p +
        medicalScore * weights.m +
        elapsedScore * weights.e +
        groupScore * weights.g;

    // Una baliza en silencio prolongado pierde prioridad: puede que ya la
    // hayan rescatado, o que el dispositivo se haya apagado. No se descarta,
    // pero deja de encabezar la lista.
    final silencePenalty = survivor.isStale(now) ? 0.55 : 1.0;

    return (combined * silencePenalty * 1000).round().clamp(0, 1000);
  }

  /// 0..1 según la banda de cercanía. Se usa la banda y no los metros crudos
  /// para no dejar que el ruido del RSSI reordene la lista a cada segundo.
  double _proximityScore(Survivor s) {
    final estimate = s.distance(estimator);
    return switch (estimate.band) {
      ProximityBand.immediate => 1.0,
      ProximityBand.near => 0.75,
      ProximityBand.medium => 0.45,
      ProximityBand.far => 0.20,
      ProximityBand.unknown => 0.10,
    };
  }

  double _medicalScore(Survivor s) {
    var value = s.signal.medicalProfile.severityScore / 100;
    if (s.signal.hasFlag(SignalFlag.trapped)) value += 0.30;
    if (s.signal.hasFlag(SignalFlag.mobilityImpaired)) value += 0.20;
    if (s.signal.hasFlag(SignalFlag.minorsPresent)) value += 0.15;
    if (s.signal.hasFlag(SignalFlag.lowBattery)) value += 0.10;
    return value.clamp(0.0, 1.0);
  }

  /// Crece con el tiempo de espera y satura a las 6 horas, que es el orden de
  /// magnitud en que la supervivencia bajo escombros empieza a caer de forma
  /// pronunciada.
  double _elapsedScore(Survivor s) {
    final minutes = s.signal.elapsedMinutes;
    return (minutes / 360).clamp(0.0, 1.0);
  }

  double _groupScore(Survivor s) =>
      ((s.signal.peopleCount - 1) / 9).clamp(0.0, 1.0);

  /// Ordena de mayor a menor prioridad.
  ///
  /// El desempate final es por `beaconId` para que el orden sea **estable**:
  /// una lista que se reordena sola mientras el rescatista la mira es una
  /// fuente de errores.
  List<Survivor> rank(List<Survivor> survivors, DateTime now) {
    final scored = survivors
        .map((s) => (survivor: s, score: score(s, now)))
        .toList(growable: false);

    final sorted = List.of(scored)
      ..sort((a, b) {
        final byScore = b.score.compareTo(a.score);
        if (byScore != 0) return byScore;
        return a.survivor.beaconId.compareTo(b.survivor.beaconId);
      });

    return sorted.map((e) => e.survivor).toList(growable: false);
  }
}
