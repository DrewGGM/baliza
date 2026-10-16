// Pruebas de la identidad de la baliza.
//
// Un identificador fijo convertiría la app en un rastreador; uno siempre
// cambiante rompería el rescate, porque el equipo perdería la pista justo
// mientras se acerca. La regla concilia ambas cosas: rota en reposo y se
// congela mientras hay una emergencia activa.

import 'package:baliza/domain/ports/clock.dart';
import 'package:baliza/domain/services/beacon_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rotación en reposo', () {
    late ManualClock clock;
    late BeaconIdentity identity;

    setUp(() {
      clock = ManualClock(DateTime(2026, 8, 10, 7, 0));
      identity = BeaconIdentity(
        clock: clock,
        rotationPeriod: const Duration(minutes: 15),
      );
    });

    test('el identificador no es ninguno de los centinelas', () {
      expect(identity.current, isNot(0));
      expect(identity.current, isNot(0xFFFFFFFF));
    });

    test('no rota antes de cumplirse el periodo', () {
      final first = identity.current;
      clock.advance(const Duration(minutes: 5));
      expect(identity.current, first);
    });

    test('rota una vez cumplido el periodo', () {
      final first = identity.current;
      clock.advance(const Duration(minutes: 16));
      expect(identity.current, isNot(first));
    });
  });

  group('Congelado durante la emergencia', () {
    test('no rota aunque pasen horas, y al terminar fuerza uno nuevo', () {
      final clock = ManualClock(DateTime(2026, 8, 10, 7, 0));
      final identity = BeaconIdentity(
        clock: clock,
        rotationPeriod: const Duration(minutes: 15),
      );

      identity.freeze();
      final frozen = identity.current;

      clock.advance(const Duration(hours: 3));
      expect(identity.current, frozen);
      expect(identity.isFrozen, isTrue);
      expect(identity.timeUntilRotation, isNull);

      identity.unfreeze();
      // Al terminar se fuerza uno nuevo para que la baliza usada durante la
      // emergencia no siga siendo rastreable después.
      expect(identity.current, isNot(frozen));
      expect(identity.isFrozen, isFalse);
    });
  });

  group('Supervivencia al cierre del proceso', () {
    test('restaura el identificador anterior y queda congelado', () {
      // Si el sistema mata la app, la baliza debe volver con el mismo código:
      // de lo contrario el equipo que la seguía vería desaparecer esa señal y
      // aparecer otra distinta justo mientras se acerca.
      final clock = ManualClock(DateTime(2026, 8, 10, 7, 0));
      final revived = BeaconIdentity(clock: clock);
      const previous = 0x48759ABC;

      revived.restore(previous);
      expect(revived.current, previous);
      expect(revived.isFrozen, isTrue);

      clock.advance(const Duration(hours: 2));
      expect(revived.current, previous);
    });

    test('rechaza restaurar los valores centinela', () {
      final clock = ManualClock(DateTime(2026, 8, 10, 7, 0));
      final guarded = BeaconIdentity(clock: clock);
      final before = guarded.current;

      guarded.restore(0);
      expect(guarded.current, before);

      guarded.restore(0xFFFFFFFF);
      expect(guarded.current, before);
    });
  });
}
