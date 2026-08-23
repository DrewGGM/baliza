import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp;

import '../../domain/ports/beacon_transport.dart';
import '../../domain/services/sos_payload_codec.dart';
import 'ble_protocol.dart';

/// Escáner BLE real: escucha balizas ajenas y las traduce a dominio.
///
/// ## Tres decisiones que importan
///
/// **`continuousUpdates: true`.** Por defecto flutter_blue_plus entrega cada
/// dispositivo una sola vez. Aquí hace falta lo contrario: un flujo constante
/// de lecturas del mismo dispositivo, porque la distancia se estima
/// precisamente de cómo evoluciona el RSSI. Sin esto la pantalla de rescate
/// mostraría una única medición congelada.
///
/// **Filtro por UUID de servicio.** El filtrado ocurre en el sistema
/// operativo, no en Dart. En una ciudad hay cientos de anuncios BLE por
/// minuto; despertar el proceso por cada uno vaciaría la batería del
/// rescatista, que es tan crítica como la de la víctima.
///
/// **`androidScanMode.lowLatency`.** Consume más, pero durante un rescate la
/// latencia es lo que se está comprando.
class BleScanner implements BeaconScanner {
  BleScanner({SosPayloadCodec codec = const SosPayloadCodec()}) : _codec = codec;

  final SosPayloadCodec _codec;

  final StreamController<RadioState> _state =
      StreamController<RadioState>.broadcast();
  final StreamController<BeaconReception> _out =
      StreamController<BeaconReception>.broadcast();

  StreamSubscription<List<fbp.ScanResult>>? _scanSub;
  StreamSubscription<fbp.BluetoothAdapterState>? _adapterSub;

  RadioState _current = RadioState.unknown;
  bool _scanning = false;

  /// Cuántos anuncios se descartaron por no ser Balizas. Sirve para
  /// diagnosticar en campo si el problema es que no hay nadie o que el filtro
  /// está mal puesto.
  int _rejected = 0;
  int get rejectedCount => _rejected;

  @override
  Stream<RadioState> get radioState => _state.stream;

  @override
  RadioState get currentState => _current;

  @override
  Stream<BeaconReception> get receptions => _out.stream;

  @override
  bool get isScanning => _scanning;

  Future<void> initialize() async {
    _adapterSub ??= fbp.FlutterBluePlus.adapterState.listen((s) {
      _push(switch (s) {
        fbp.BluetoothAdapterState.on => RadioState.ready,
        fbp.BluetoothAdapterState.off => RadioState.off,
        fbp.BluetoothAdapterState.unauthorized => RadioState.unauthorized,
        fbp.BluetoothAdapterState.unavailable => RadioState.unsupported,
        _ => RadioState.unknown,
      });
    });

    if (!await fbp.FlutterBluePlus.isSupported) {
      _push(RadioState.unsupported);
    }
  }

  @override
  Future<void> start() async {
    if (_scanning) return;
    await initialize();

    _scanSub ??= fbp.FlutterBluePlus.scanResults.listen(
      _onResults,
      onError: (Object e) => debugPrint('[BleScanner] error de escaneo: $e'),
    );

    await fbp.FlutterBluePlus.startScan(
      withServices: <fbp.Guid>[fbp.Guid(BleProtocol.serviceUuid)],
      continuousUpdates: true,
      androidScanMode: fbp.AndroidScanMode.lowLatency,
      androidLegacy: true,
    );

    _scanning = true;
  }

  void _onResults(List<fbp.ScanResult> results) {
    final now = DateTime.now();
    for (final result in results) {
      final reception = _translate(result, now);
      if (reception == null) {
        _rejected++;
        continue;
      }
      if (!_out.isClosed) _out.add(reception);
    }
  }

  /// Traduce un anuncio BLE a dominio, o devuelve `null` si no es una Baliza.
  ///
  /// Rechaza en tres pasos, del más barato al más caro: identificador de
  /// fabricante, firma de dos bytes y, por último, el CRC del códec.
  BeaconReception? _translate(fbp.ScanResult result, DateTime at) {
    final raw = result.advertisementData.manufacturerData[
        BleProtocol.manufacturerId];
    if (raw == null || raw.length < BleProtocol.manufacturerDataLength) {
      return null;
    }

    if (raw[0] != BleProtocol.signature[0] ||
        raw[1] != BleProtocol.signature[1]) {
      return null;
    }

    final payload = Uint8List.fromList(
      raw.sublist(2, BleProtocol.manufacturerDataLength),
    );

    final signal = _codec.tryDecode(payload);
    if (signal == null) return null;

    return BeaconReception(signal: signal, rssi: result.rssi, at: at);
  }

  @override
  Future<void> stop() async {
    if (!_scanning) return;
    _scanning = false;
    try {
      await fbp.FlutterBluePlus.stopScan();
    } catch (e) {
      debugPrint('[BleScanner] fallo al detener escaneo: $e');
    }
  }

  void _push(RadioState s) {
    _current = s;
    if (!_state.isClosed) _state.add(s);
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _scanSub?.cancel();
    await _adapterSub?.cancel();
    await _state.close();
    await _out.close();
  }
}
