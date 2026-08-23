import '../services/distance_estimator.dart';
import 'sos_signal.dart';

/// Una baliza detectada, seguida en el tiempo.
///
/// Agrega todas las lecturas de un mismo `beaconId`: la señal más reciente, el
/// historial de RSSI del que sale la distancia, y las marcas de tiempo que
/// permiten saber si sigue viva o si dejó de emitir.
class Survivor {
  Survivor({
    required this.beaconId,
    required SosSignal signal,
    required DateTime firstSeen,
    required DateTime lastSeen,
    List<int>? rssiSamples,
  }) : _rssiSamples = rssiSamples ?? <int>[] {
    _signal = signal;
    _firstSeen = firstSeen;
    _lastSeen = lastSeen;
  }

  /// Cuántas lecturas de RSSI se conservan por baliza.
  static const int maxSamples = 24;

  final int beaconId;

  late SosSignal _signal;
  late DateTime _firstSeen;
  late DateTime _lastSeen;
  final List<int> _rssiSamples;

  SosSignal get signal => _signal;
  DateTime get firstSeen => _firstSeen;
  DateTime get lastSeen => _lastSeen;
  List<int> get rssiSamples => List.unmodifiable(_rssiSamples);

  /// Última potencia recibida, o `null` si aún no hay lecturas.
  int? get lastRssi => _rssiSamples.isEmpty ? null : _rssiSamples.last;

  /// Identificador corto y legible que el rescatista puede cantar por radio.
  ///
  /// Cuatro dígitos hexadecimales en mayúscula: "B4-7C". Es mucho más fácil de
  /// comunicar por voz que un entero de 32 bits, y basta para distinguir las
  /// balizas que un mismo equipo tiene a la vista.
  String get shortCode {
    final hex = (beaconId & 0xFFFF).toRadixString(16).toUpperCase().padLeft(4, '0');
    return '${hex.substring(0, 2)}-${hex.substring(2)}';
  }

  /// Incorpora una nueva lectura.
  void update({
    required SosSignal signal,
    required int rssi,
    required DateTime at,
  }) {
    _signal = signal;
    _lastSeen = at;
    if (at.isBefore(_firstSeen)) _firstSeen = at;
    _rssiSamples.add(rssi);
    if (_rssiSamples.length > maxSamples) {
      _rssiSamples.removeRange(0, _rssiSamples.length - maxSamples);
    }
  }

  /// Tiempo transcurrido desde la última recepción.
  Duration silenceFor(DateTime now) => now.difference(_lastSeen);

  /// `true` si lleva más de [threshold] sin emitir.
  ///
  /// No se elimina de la lista: una baliza que se apaga es información crítica
  /// —batería agotada, dispositivo aplastado— y el rescatista debe seguir
  /// viendo la última posición conocida.
  bool isStale(DateTime now, {Duration threshold = const Duration(seconds: 45)}) =>
      silenceFor(now) > threshold;

  /// Cuánto lleva emitiendo, según nuestras propias observaciones.
  Duration trackedFor(DateTime now) => now.difference(_firstSeen);

  DistanceEstimate distance(DistanceEstimator estimator) =>
      estimator.estimate(_rssiSamples);

  ProximityTrend get trend => trendFromSamples(_rssiSamples);

  bool get isSos => _signal.isSos;
  bool get isSafe => _signal.isSafe;
  bool get isResponder => _signal.isResponder;

  @override
  String toString() =>
      'Survivor($shortCode, ${_signal.messageType.name}, '
      'rssi=${lastRssi ?? '-'}, n=${_rssiSamples.length})';
}

/// Registro vivo de todas las balizas detectadas en la sesión de rescate.
class SurvivorRegistry {
  SurvivorRegistry();

  final Map<int, Survivor> _byId = {};

  /// Todas las balizas conocidas, sin ordenar.
  List<Survivor> get all => _byId.values.toList(growable: false);

  int get length => _byId.length;
  bool get isEmpty => _byId.isEmpty;
  bool get isNotEmpty => _byId.isNotEmpty;

  Survivor? operator [](int beaconId) => _byId[beaconId];

  /// Registra una recepción, creando la entrada si es la primera vez.
  ///
  /// Devuelve `true` si la baliza no se había visto antes, para que la capa de
  /// aplicación pueda avisar al rescatista de un hallazgo nuevo.
  bool observe({
    required SosSignal signal,
    required int rssi,
    required DateTime at,
  }) {
    final existing = _byId[signal.beaconId];
    if (existing == null) {
      _byId[signal.beaconId] = Survivor(
        beaconId: signal.beaconId,
        signal: signal,
        firstSeen: at,
        lastSeen: at,
        rssiSamples: [rssi],
      );
      return true;
    }
    existing.update(signal: signal, rssi: rssi, at: at);
    return false;
  }

  /// Balizas que piden auxilio, que es lo que ocupa la pantalla de rescate.
  List<Survivor> get sosOnly =>
      _byId.values.where((s) => s.isSos).toList(growable: false);

  /// Equipos de rescate detectados alrededor.
  List<Survivor> get responders =>
      _byId.values.where((s) => s.isResponder).toList(growable: false);

  /// Personas que ya reportaron estar bien.
  List<Survivor> get safe =>
      _byId.values.where((s) => s.isSafe).toList(growable: false);

  void remove(int beaconId) => _byId.remove(beaconId);

  void clear() => _byId.clear();

  /// Descarta balizas que llevan mucho tiempo en silencio.
  ///
  /// El umbral es deliberadamente largo: sólo se limpian las que llevan tanto
  /// tiempo calladas que ya no aportan a la operación en curso.
  int purgeSilent(DateTime now, {Duration threshold = const Duration(minutes: 30)}) {
    final doomed = _byId.entries
        .where((e) => e.value.silenceFor(now) > threshold)
        .map((e) => e.key)
        .toList();
    for (final id in doomed) {
      _byId.remove(id);
    }
    return doomed.length;
  }
}
