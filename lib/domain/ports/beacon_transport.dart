import '../entities/sos_signal.dart';

/// Una recepción cruda: qué señal llegó y con cuánta potencia.
class BeaconReception {
  const BeaconReception({
    required this.signal,
    required this.rssi,
    required this.at,
  });

  final SosSignal signal;

  /// Potencia recibida en dBm. Siempre negativa en la práctica.
  final int rssi;

  final DateTime at;

  @override
  String toString() => 'BeaconReception($signal, $rssi dBm)';
}

/// Estado del radio del dispositivo.
enum RadioState {
  /// Listo para emitir y escuchar.
  ready('Listo'),

  /// El hardware existe pero está apagado.
  off('Bluetooth apagado'),

  /// Faltan permisos del sistema.
  unauthorized('Permisos pendientes'),

  /// El dispositivo no soporta la operación (típico: emitir en equipos viejos).
  unsupported('No compatible'),

  /// Aún no se ha determinado.
  unknown('Comprobando');

  const RadioState(this.label);
  final String label;

  bool get isReady => this == RadioState.ready;
}

/// Emite balizas al exterior.
///
/// La implementación real usa anuncios BLE; la de simulación entrega las
/// señales a un bus en memoria. La capa de aplicación no distingue una de otra,
/// que es lo que permite ejercitar la app completa sin dos teléfonos.
abstract interface class BeaconTransmitter {
  /// Estado del radio, con cambios en vivo.
  Stream<RadioState> get radioState;

  RadioState get currentState;

  /// `true` si actualmente se está emitiendo.
  bool get isTransmitting;

  /// Empieza a emitir la señal indicada, reemplazando la anterior si la había.
  Future<void> start(SosSignal signal);

  /// Actualiza el contenido sin cortar la emisión.
  ///
  /// Se usa cada minuto para refrescar los minutos transcurridos y la batería,
  /// datos que el rescatista necesita al día.
  Future<void> update(SosSignal signal);

  /// Detiene la emisión.
  Future<void> stop();

  Future<void> dispose();
}

/// Escucha balizas ajenas.
abstract interface class BeaconScanner {
  Stream<RadioState> get radioState;

  RadioState get currentState;

  /// Recepciones ya decodificadas y validadas. Lo que no es una Baliza válida
  /// jamás llega a este flujo.
  Stream<BeaconReception> get receptions;

  bool get isScanning;

  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}
