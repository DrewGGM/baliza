// Pruebas de la política de energía.
//
// Bajo escombros la batería es un reloj de arena. La política decide qué
// señales retirar y en qué orden, con una regla que no admite excepción: la
// radio no se apaga nunca, porque es lo único que funciona sin ver a nadie.

import 'package:baliza/domain/services/power_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const policy = PowerPolicy();

  group('Niveles según la carga', () {
    test('con la batería alta se emiten todas las señales', () {
      expect(policy.tierFor(100), PowerTier.full);
      expect(policy.tierFor(60), PowerTier.full);
    });

    test('por debajo del 50 % se retira la linterna', () {
      expect(policy.tierFor(40), PowerTier.saving);
      expect(policy.tierFor(25), PowerTier.saving);
    });

    test('por debajo del 25 % la sirena pasa a intermitente', () {
      expect(policy.tierFor(15), PowerTier.low);
      expect(policy.tierFor(10), PowerTier.low);
    });

    test('por debajo del 10 % sólo queda la radio', () {
      expect(policy.tierFor(5), PowerTier.critical);
      expect(policy.tierFor(0), PowerTier.critical);
    });

    test('sin lectura de batería se asume el mejor caso', () {
      // Recortar señales por una lectura que no existe sería peor que no
      // recortarlas: dejaría a alguien sin sirena por un fallo del sensor.
      expect(policy.tierFor(null), PowerTier.full);
    });
  });

  group('La radio nunca se apaga', () {
    test('el nivel crítico retira todo lo auxiliar y nada más', () {
      expect(PowerTier.critical.torch, isFalse);
      expect(PowerTier.critical.vibration, isFalse);
      expect(PowerTier.critical.siren, isFalse);
    });
  });

  group('Histéresis', () {
    test('bajar de nivel es inmediato', () {
      expect(policy.tierFor(40, current: PowerTier.full), PowerTier.saving);
    });

    test('subir de nivel exige margen suficiente', () {
      // Sin margen, una batería que fluctúa alrededor del umbral encendería y
      // apagaría la linterna cada pocos segundos, gastando más que dejarla fija.
      expect(policy.tierFor(51, current: PowerTier.saving), PowerTier.saving);
      expect(policy.tierFor(53, current: PowerTier.saving), PowerTier.full);
      expect(policy.tierFor(26, current: PowerTier.low), PowerTier.low);
      expect(policy.tierFor(28, current: PowerTier.low), PowerTier.saving);
    });

    test('una batería que fluctúa en el umbral no oscila de nivel', () {
      var tier = policy.tierFor(60);
      var changes = 0;
      for (final reading in <int>[26, 24, 26, 24, 25, 26, 24, 25, 26, 24]) {
        final next = policy.tierFor(reading, current: tier);
        if (next != tier) changes++;
        tier = next;
      }

      // Cruzar el umbral hacia abajo sí produce un escalón, por diseño. Lo que
      // no debe ocurrir es que suba y baje en bucle.
      expect(changes, lessThanOrEqualTo(2));
      expect(policy.tierFor(26, current: tier), tier);
    });
  });

  group('Explicación y autonomía', () {
    test('el nivel pleno no genera aviso', () {
      expect(policy.explain(PowerTier.full, 80), isNull);
    });

    test('el nivel crítico explica que sólo queda la radio', () {
      // La app decide por quien no está en condiciones de decidir, pero se lo
      // dice: hacerlo a escondidas sería distinto.
      expect(policy.explain(PowerTier.critical, 5), contains('radio'));
    });

    test('ahorrar alarga la autonomía estimada', () {
      final full = policy.estimatedBeaconLife(50, PowerTier.full);
      final critical = policy.estimatedBeaconLife(50, PowerTier.critical);
      expect(critical, isNotNull);
      expect(full, isNotNull);
      expect(critical!, greaterThan(full!));
    });

    test('sin lectura de batería no se estima autonomía', () {
      expect(policy.estimatedBeaconLife(null, PowerTier.full), isNull);
    });
  });
}
