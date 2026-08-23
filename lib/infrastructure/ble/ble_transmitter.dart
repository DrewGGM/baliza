import 'dart:async';

import 'package:ble_peripheral/ble_peripheral.dart' as bp;
import 'package:flutter/foundation.dart';

import '../../domain/entities/sos_signal.dart';
import '../../domain/ports/beacon_transport.dart';
import '../../domain/services/sos_payload_codec.dart';
import 'ble_protocol.dart';

/// Emisor BLE real: anuncia la baliza como periférico.
///
/// ## Comportamiento en segundo plano
///
/// En **Android** la emisión sigue mientras el proceso viva; por eso la app
/// levanta un servicio en primer plano con notificación persistente, que es lo
/// único que impide al sistema matar el proceso al apagar la pantalla.
///
/// En **iOS** el sistema degrada los anuncios en segundo plano: el UUID de
/// servicio se traslada a un área especial de la trama y deja de ser visible
/// para escáneres que no lo busquen de forma explícita. Por eso el escáner de
/// esta app filtra siempre por [BleProtocol.serviceUuid]: es la única forma de
/// que un iPhone bloqueado siga siendo detectable por otro dispositivo Baliza.
class BleTransmitter implements BeaconTransmitter {
  BleTransmitter({SosPayloadCodec codec = const SosPayloadCodec()})
      : _codec = codec;

  final SosPayloadCodec _codec;

  final StreamController<RadioState> _state =
      StreamController<RadioState>.broadcast();

  RadioState _current = RadioState.unknown;
  bool _transmitting = false;
  bool _initialized = false;
  SosSignal? _pending;

  @override
  Stream<RadioState> get radioState => _state.stream;

  @override
  RadioState get currentState => _current;

  @override
  bool get isTransmitting => _transmitting;

  /// Prepara la pila de periférico. Es idempotente.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      bp.BlePeripheral.setAdvertisingStatusUpdateCallback(
        (bool advertising, String? error) {
          _transmitting = advertising;
          if (error != null) {
            debugPrint('[BleTransmitter] error de anuncio: $error');
            _push(RadioState.unsupported);
          } else {
            _push(RadioState.ready);
          }
        },
      );

      bp.BlePeripheral.setBleStateChangeCallback((bool available) {
        _push(available ? RadioState.ready : RadioState.off);
      });

      await bp.BlePeripheral.initialize();
      _initialized = true;
      _push(RadioState.ready);
    } catch (e) {
      debugPrint('[BleTransmitter] no se pudo inicializar: $e');
      _push(RadioState.unsupported);
      rethrow;
    }
  }

  @override
  Future<void> start(SosSignal signal) async {
    await initialize();
    _pending = signal;
    await _advertise(signal);
  }

  @override
  Future<void> update(SosSignal signal) async {
    if (!_transmitting) return;
    _pending = signal;
    // El anuncio BLE no admite cambiar la carga en caliente: hay que detener y
    // volver a empezar. El corte dura milisegundos y se hace cada 30 s, así
    // que el rescatista no lo percibe.
    await _stopAdvertising();
    await _advertise(signal);
  }

  Future<void> _advertise(SosSignal signal) async {
    final payload = _codec.encode(signal);
    final data = Uint8List(BleProtocol.manufacturerDataLength)
      ..setRange(0, 2, BleProtocol.signature)
      ..setRange(2, BleProtocol.manufacturerDataLength, payload);

    await bp.BlePeripheral.startAdvertising(
      services: <String>[BleProtocol.serviceUuid],
      localName: BleProtocol.localName,
      manufacturerData: bp.ManufacturerData(
        manufacturerId: BleProtocol.manufacturerId,
        data: data,
      ),
      // Los datos de fabricante van en la respuesta de escaneo para no agotar
      // los 31 bytes del anuncio principal, donde debe caber el UUID de
      // servicio por el que filtra el receptor.
      addManufacturerDataInScanResponse: true,
    );
    _transmitting = true;
  }

  Future<void> _stopAdvertising() async {
    try {
      await bp.BlePeripheral.stopAdvertising();
    } catch (e) {
      debugPrint('[BleTransmitter] fallo al detener anuncio: $e');
    }
  }

  @override
  Future<void> stop() async {
    await _stopAdvertising();
    _transmitting = false;
    _pending = null;
  }

  /// Señal que se está emitiendo, si la hay.
  SosSignal? get pending => _pending;

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
