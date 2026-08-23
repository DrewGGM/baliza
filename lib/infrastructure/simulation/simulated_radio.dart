import 'dart:async';
import 'dart:math';

import '../../domain/entities/sos_signal.dart';
import '../../domain/ports/beacon_transport.dart';
import '../../domain/services/distance_estimator.dart';

/// Una baliza virtual que vive en el simulador.
class SimulatedPeer {
  SimulatedPeer({
    required this.signal,
    required this.distanceMeters,
    this.driftMetersPerTick = 0,
    this.minDistance = 0.5,
    this.maxDistance = 60,
  });

  SosSignal signal;

  /// Distancia actual al dispositivo local, en metros.
  double distanceMeters;

  /// Cuánto se acerca (negativo) o se aleja (positivo) en cada anuncio.
  /// Permite ensayar la lectura de tendencia sin moverse del escritorio.
  final double driftMetersPerTick;

  final double minDistance;
  final double maxDistance;

  void tick() {
    if (driftMetersPerTick == 0) return;
    distanceMeters =
        (distanceMeters + driftMetersPerTick).clamp(minDistance, maxDistance);
  }
}

/// Bus de radio en memoria que sustituye al Bluetooth.
///
/// ## Por qué existe
///
/// El emulador de Android no tiene radio Bluetooth, y probar de verdad exige
/// dos teléfonos físicos y a alguien dispuesto a esconderse bajo escombros.
/// Ninguna de las dos cosas está disponible durante el desarrollo diario.
///
/// Este bus implementa los mismos puertos que el transporte real, así que la
/// aplicación entera —detección, emisión, escaneo, triaje, interfaz— se puede
/// recorrer de principio a fin sin hardware. Lo único que queda sin ejercitar
/// es la capa nativa de BLE, que es justo la porción que se mantuvo delgada a
/// propósito.
///
/// ## Modelo físico
///
/// Convierte la distancia de cada baliza virtual en un RSSI plausible
/// invirtiendo el mismo modelo log-distancia que usa el estimador, y le suma
/// ruido gaussiano. Sin ese ruido la simulación mentiría: mostraría lecturas
/// perfectas que en la calle no existen, y el filtrado por media recortada
/// parecería innecesario.
class SimulatedRadioBus {
  SimulatedRadioBus({
    Random? random,
    this.advertiseInterval = const Duration(milliseconds: 900),
    this.noiseStdDev = 4.0,
    this.environment = PropagationEnvironment.rubble,
    this.referenceRssiAtOneMeter = -59,
  }) : _random = random ?? Random();

  final Random _random;

  /// Cada cuánto emite cada baliza virtual.
  final Duration advertiseInterval;

  /// Desviación estándar del ruido de RSSI, en dB. Cuatro decibelios es lo
  /// típico de un enlace BLE en interiores.
  final double noiseStdDev;

  final PropagationEnvironment environment;
  final int referenceRssiAtOneMeter;

  final List<SimulatedPeer> _peers = [];
  final StreamController<BeaconReception> _receptions =
      StreamController<BeaconReception>.broadcast();

  Timer? _timer;

  /// Señal que el dispositivo local está emitiendo, si la hay.
  SosSignal? _localTransmission;

  Stream<BeaconReception> get receptions => _receptions.stream;

  List<SimulatedPeer> get peers => List.unmodifiable(_peers);

  bool get isRunning => _timer != null;

  SosSignal? get localTransmission => _localTransmission;

  void setLocalTransmission(SosSignal? signal) => _localTransmission = signal;

  void addPeer(SimulatedPeer peer) => _peers.add(peer);

  void removePeer(int beaconId) =>
      _peers.removeWhere((p) => p.signal.beaconId == beaconId);

  void clearPeers() => _peers.clear();

  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(advertiseInterval, (_) => _emitRound());
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Fuerza una ronda de anuncios sin esperar al temporizador.
  void emitNow() => _emitRound();

  void _emitRound() {
    final now = DateTime.now();
    for (final peer in _peers) {
      peer.tick();
      final rssi = rssiForDistance(peer.distanceMeters);
      if (_receptions.isClosed) return;
      _receptions.add(
        BeaconReception(signal: peer.signal, rssi: rssi, at: now),
      );
    }
  }

  /// Invierte el modelo log-distancia para obtener el RSSI que produciría una
  /// baliza situada a [meters], y le añade ruido.
  int rssiForDistance(double meters) {
    final d = meters.clamp(0.1, 10000.0);
    final ideal = referenceRssiAtOneMeter -
        10 * environment.pathLossExponent * (log(d) / ln10);
    final noisy = ideal + _gaussian() * noiseStdDev;
    return noisy.round().clamp(-110, -20);
  }

  /// Ruido gaussiano estándar por el método de Box-Muller.
  double _gaussian() {
    final u1 = 1.0 - _random.nextDouble();
    final u2 = 1.0 - _random.nextDouble();
    return sqrt(-2.0 * log(u1)) * cos(2 * pi * u2);
  }

  Future<void> dispose() async {
    stop();
    _peers.clear();
    await _receptions.close();
  }
}

/// Emisor simulado: en vez de anunciar por BLE, deja la señal en el bus.
class SimulatedTransmitter implements BeaconTransmitter {
  SimulatedTransmitter(this._bus);

  final SimulatedRadioBus _bus;

  final StreamController<RadioState> _state =
      StreamController<RadioState>.broadcast();
  RadioState _current = RadioState.ready;
  bool _transmitting = false;

  @override
  Stream<RadioState> get radioState => _state.stream;

  @override
  RadioState get currentState => _current;

  @override
  bool get isTransmitting => _transmitting;

  @override
  Future<void> start(SosSignal signal) async {
    _transmitting = true;
    _bus.setLocalTransmission(signal);
    _push(RadioState.ready);
  }

  @override
  Future<void> update(SosSignal signal) async {
    if (!_transmitting) return;
    _bus.setLocalTransmission(signal);
  }

  @override
  Future<void> stop() async {
    _transmitting = false;
    _bus.setLocalTransmission(null);
  }

  void _push(RadioState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _state.close();
  }
}

/// Escáner simulado: escucha el bus en memoria.
class SimulatedScanner implements BeaconScanner {
  SimulatedScanner(this._bus);

  final SimulatedRadioBus _bus;

  final StreamController<RadioState> _state =
      StreamController<RadioState>.broadcast();
  final StreamController<BeaconReception> _out =
      StreamController<BeaconReception>.broadcast();

  StreamSubscription<BeaconReception>? _sub;
  RadioState _current = RadioState.ready;
  bool _scanning = false;

  @override
  Stream<RadioState> get radioState => _state.stream;

  @override
  RadioState get currentState => _current;

  @override
  Stream<BeaconReception> get receptions => _out.stream;

  @override
  bool get isScanning => _scanning;

  @override
  Future<void> start() async {
    if (_scanning) return;
    _scanning = true;
    _bus.start();
    _sub = _bus.receptions.listen((r) {
      if (!_out.isClosed) _out.add(r);
    });
    _current = RadioState.ready;
    if (!_state.isClosed) _state.add(_current);
  }

  @override
  Future<void> stop() async {
    _scanning = false;
    await _sub?.cancel();
    _sub = null;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _state.close();
    await _out.close();
  }
}
