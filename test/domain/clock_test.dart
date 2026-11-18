// Pruebas del reloj simulado.
//
// Todas las pruebas que dependen del tiempo se apoyan en ManualClock, así que
// si este reloj se adelanta o se atrasa, ninguna de ellas sería confiable.

import 'package:baliza/domain/ports/clock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final start = DateTime.utc(2026, 11, 19, 19, 50);

  group('ManualClock', () {
    test('devuelve el instante con el que se creó', () {
      expect(ManualClock(start).now(), start);
    });

    test('no avanza solo', () async {
      final clock = ManualClock(start);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(clock.now(), start);
    });

    test('avanza exactamente lo pedido', () {
      final clock = ManualClock(start)
        ..advance(const Duration(minutes: 2))
        ..advance(const Duration(seconds: 1));
      expect(clock.now(), start.add(const Duration(minutes: 2, seconds: 1)));
    });

    test('setTo lo sitúa en un instante concreto', () {
      final target = DateTime.utc(2027, 1, 1);
      final clock = ManualClock(start)..setTo(target);
      expect(clock.now(), target);
    });
  });
}
