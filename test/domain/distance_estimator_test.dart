// Pruebas del estimador de distancia y de la tendencia de proximidad.
//
// El estimador no pretende ser exacto —el Bluetooth es demasiado ruidoso—,
// así que lo que se verifica es que sea honesto: que ordene bien, que absorba
// los valores atípicos y que baje la confianza cuando la serie es dispersa.

import 'package:baliza/domain/services/distance_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const estimator = DistanceEstimator(
    environment: PropagationEnvironment.openField,
  );

  group('Estimador de distancia', () {
    test('el RSSI de referencia corresponde a un metro', () {
      expect(estimator.metersFromRssi(-59), closeTo(1.0, 0.01));
    });

    test('una señal más fuerte implica menos distancia', () {
      expect(
        estimator.metersFromRssi(-40),
        lessThan(estimator.metersFromRssi(-80)),
      );
    });

    test('los escombros estiman más cerca que el campo abierto', () {
      // A igual RSSI, un medio que atenúa más implica que la fuente está más
      // cerca de lo que parecería en campo abierto.
      const rubble = DistanceEstimator(
        environment: PropagationEnvironment.rubble,
      );
      expect(
        rubble.metersFromRssi(-80),
        lessThan(estimator.metersFromRssi(-80)),
      );
    });
  });

  group('Estimador: bandas de proximidad', () {
    test('clasifica cada distancia en su banda', () {
      expect(estimator.bandForMeters(1.5), ProximityBand.immediate);
      expect(estimator.bandForMeters(3), ProximityBand.near);
      expect(estimator.bandForMeters(10), ProximityBand.medium);
      expect(estimator.bandForMeters(40), ProximityBand.far);
    });

    test('un valor no numérico cae en la banda desconocida', () {
      expect(estimator.bandForMeters(double.nan), ProximityBand.unknown);
    });

    test('sin muestras la estimación es desconocida', () {
      expect(estimator.estimate(<int>[]).band, ProximityBand.unknown);
    });
  });

  group('Estimador: confianza y valores atípicos', () {
    test('una serie estable da confianza alta y la distancia correcta', () {
      final estimate = estimator.estimate(List<int>.filled(8, -59));
      expect(estimate.confidence, greaterThan(0.9));
      expect(estimate.meters, closeTo(1.0, 0.2));
    });

    test('una serie dispersa da confianza baja', () {
      // Mostrar una distancia con confianza alta a partir de lecturas que
      // saltan 60 dB sería mentirle al rescatista.
      const noisy = <int>[-30, -90, -35, -95, -40, -88, -33, -92];
      expect(estimator.estimate(noisy).confidence, lessThan(0.6));
    });

    test('la media recortada absorbe una lectura atípica', () {
      const outlier = <int>[-59, -59, -59, -59, -59, -59, -59, -120];
      expect(estimator.estimate(outlier).meters, closeTo(1.0, 0.5));
    });
  });

  group('Tendencia de proximidad', () {
    test('reconoce que el rescatista se acerca', () {
      expect(
        trendFromSamples(<int>[-90, -88, -70, -65]),
        ProximityTrend.closer,
      );
    });

    test('reconoce que el rescatista se aleja', () {
      expect(
        trendFromSamples(<int>[-60, -62, -85, -90]),
        ProximityTrend.farther,
      );
    });

    test('reconoce una señal estable', () {
      expect(
        trendFromSamples(<int>[-70, -71, -70, -69]),
        ProximityTrend.steady,
      );
    });

    test('con pocas muestras no se pronuncia', () {
      expect(trendFromSamples(<int>[-70, -71]), ProximityTrend.unknown);
    });
  });
}
