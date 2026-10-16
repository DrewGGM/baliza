// Pruebas del seguimiento de balizas detectadas.
//
// El registro agrega todas las lecturas de un mismo identificador. Lo que se
// verifica aquí es que no pierda el hilo de una baliza ni acumule historial sin
// límite, y que una baliza que se calla siga siendo visible: que se apague es
// información crítica, no un motivo para borrarla de la pantalla.

import 'package:baliza/domain/entities/sos_signal.dart';
import 'package:baliza/domain/entities/survivor.dart';
import 'package:baliza/domain/value_objects/enums.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime t0 = DateTime(2026, 8, 10, 8, 0);

SosSignal signalFor(int beaconId, {MessageType type = MessageType.sos}) =>
    SosSignal(beaconId: beaconId, messageType: type);

void main() {
  group('Código corto legible', () {
    test('se muestra como cuatro dígitos hexadecimales separados', () {
      final survivor = Survivor(
        beaconId: 0xDEADB47C,
        signal: signalFor(0xDEADB47C),
        firstSeen: t0,
        lastSeen: t0,
      );
      // Sólo los 16 bits bajos: es lo que un rescatista puede cantar por radio.
      expect(survivor.shortCode, 'B4-7C');
    });

    test('rellena con ceros los identificadores pequeños', () {
      final survivor = Survivor(
        beaconId: 0x0005,
        signal: signalFor(0x0005),
        firstSeen: t0,
        lastSeen: t0,
      );
      expect(survivor.shortCode, '00-05');
    });
  });

  group('Historial de lecturas', () {
    test('conserva como mucho el máximo de muestras', () {
      final survivor = Survivor(
        beaconId: 1,
        signal: signalFor(1),
        firstSeen: t0,
        lastSeen: t0,
      );

      for (var i = 0; i < Survivor.maxSamples + 10; i++) {
        survivor.update(
          signal: signalFor(1),
          rssi: -50 - i,
          at: t0.add(Duration(seconds: i)),
        );
      }

      expect(survivor.rssiSamples.length, Survivor.maxSamples);
      // Se descartan las viejas, no las recientes.
      expect(survivor.lastRssi, -50 - (Survivor.maxSamples + 9));
    });

    test('sin lecturas no hay última potencia', () {
      final survivor = Survivor(
        beaconId: 1,
        signal: signalFor(1),
        firstSeen: t0,
        lastSeen: t0,
      );
      expect(survivor.lastRssi, isNull);
    });
  });

  group('Silencio de una baliza', () {
    test('se considera callada pasado el umbral', () {
      final survivor = Survivor(
        beaconId: 1,
        signal: signalFor(1),
        firstSeen: t0,
        lastSeen: t0,
      );

      expect(survivor.isStale(t0.add(const Duration(seconds: 30))), isFalse);
      expect(survivor.isStale(t0.add(const Duration(minutes: 2))), isTrue);
    });
  });

  group('Registro de balizas', () {
    test(
      'la primera observación crea la entrada y las siguientes la agregan',
      () {
        final registry = SurvivorRegistry();

        expect(
          registry.observe(signal: signalFor(0xAAA), rssi: -60, at: t0),
          isTrue,
        );
        expect(
          registry.observe(
            signal: signalFor(0xAAA),
            rssi: -55,
            at: t0.add(const Duration(seconds: 1)),
          ),
          isFalse,
        );

        expect(registry.length, 1);
        expect(registry[0xAAA]!.rssiSamples, <int>[-60, -55]);
      },
    );

    test('separa las balizas por tipo de mensaje', () {
      final registry = SurvivorRegistry();
      registry.observe(signal: signalFor(1), rssi: -60, at: t0);
      registry.observe(
        signal: signalFor(2, type: MessageType.responder),
        rssi: -60,
        at: t0,
      );
      registry.observe(
        signal: signalFor(3, type: MessageType.safe),
        rssi: -60,
        at: t0,
      );

      expect(registry.sosOnly.single.beaconId, 1);
      expect(registry.responders.single.beaconId, 2);
      expect(registry.safe.single.beaconId, 3);
    });

    test('la purga sólo descarta lo que lleva mucho tiempo callado', () {
      final registry = SurvivorRegistry();
      registry.observe(signal: signalFor(1), rssi: -60, at: t0);
      registry.observe(
        signal: signalFor(2),
        rssi: -60,
        at: t0.add(const Duration(minutes: 29)),
      );

      final purged = registry.purgeSilent(t0.add(const Duration(minutes: 45)));

      expect(purged, 1);
      expect(registry.length, 1);
      expect(registry[2], isNotNull);
    });
  });
}
