// Pruebas del detector sísmico.
//
// Una falsa alarma emite una baliza que nadie necesita y consume batería que
// puede hacer falta luego; un falso negativo deja sin señal a quien quedó
// inconsciente. Por eso el detector exige corroboración entre sensores
// distintos y dentro de una ventana temporal acotada.

import 'package:baliza/domain/ports/clock.dart';
import 'package:baliza/domain/services/disaster_detector.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime(2026, 8, 10, 7, 34, 27);

  group('Corroboración con barómetro disponible', () {
    late ManualClock clock;
    late DisasterDetector detector;

    setUp(() {
      clock = ManualClock(t0);
      detector = DisasterDetector(clock: clock, barometerAvailable: true);
    });

    test('con barómetro exige tres sensores', () {
      expect(detector.requiredSensorCount, 3);
    });

    test('tres sensores dentro de la ventana disparan la detección', () {
      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.accelerometer,
            magnitude: 30,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.accumulating,
      );

      clock.advance(const Duration(milliseconds: 200));
      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.gyroscope,
            magnitude: 8,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.accumulating,
      );

      clock.advance(const Duration(milliseconds: 200));
      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.barometer,
            magnitude: 1.2,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.disasterDetected,
      );
    });

    test('el mismo sensor repetido no basta para disparar', () {
      // Un teléfono que se cae al suelo golpea el acelerómetro varias veces.
      // Eso no es un sismo.
      var verdict = DetectionVerdict.idle;
      for (var i = 0; i < 5; i++) {
        verdict = detector.record(
          SensorAnomaly(
            kind: SensorKind.accelerometer,
            magnitude: 40,
            at: clock.now(),
          ),
        );
        clock.advance(const Duration(milliseconds: 100));
      }
      expect(verdict, DetectionVerdict.accumulating);
    });

    test('una anomalía vieja no cuenta como simultánea', () {
      // Defecto corregido: sin caducidad, una sacudida de la mañana se sumaba
      // a dos lecturas de la tarde y disparaba una alarma inexistente.
      detector.record(
        SensorAnomaly(
          kind: SensorKind.accelerometer,
          magnitude: 30,
          at: clock.now(),
        ),
      );

      clock.advance(const Duration(hours: 9));
      detector.record(
        SensorAnomaly(
          kind: SensorKind.gyroscope,
          magnitude: 8,
          at: clock.now(),
        ),
      );

      clock.advance(const Duration(milliseconds: 100));
      final verdict = detector.record(
        SensorAnomaly(
          kind: SensorKind.barometer,
          magnitude: 1.2,
          at: clock.now(),
        ),
      );

      expect(verdict, DetectionVerdict.accumulating);
      expect(detector.corroboratingSensors.length, 2);
    });
  });

  group('Ventana estrecha sin barómetro', () {
    DisasterDetector buildDetector(ManualClock clock) => DisasterDetector(
      clock: clock,
      barometerAvailable: false,
      corroborationWindow: const Duration(milliseconds: 1200),
      narrowWindowDivisor: 3.0,
    );

    test('sin barómetro exige dos sensores y estrecha la ventana', () {
      // Al perder el tercer testigo se compensa exigiendo más simultaneidad.
      final detector = buildDetector(ManualClock(t0));
      expect(detector.requiredSensorCount, 2);
      expect(detector.effectiveWindow.inMilliseconds, 400);
    });

    test('dos sensores dentro de los 400 ms disparan la detección', () {
      final clock = ManualClock(t0);
      final detector = buildDetector(clock);

      detector.record(
        SensorAnomaly(
          kind: SensorKind.accelerometer,
          magnitude: 30,
          at: clock.now(),
        ),
      );
      clock.advance(const Duration(milliseconds: 200));

      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.gyroscope,
            magnitude: 8,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.disasterDetected,
      );
    });

    test('a 700 ms la ventana estrecha rechaza la corroboración', () {
      // 700 ms cae fuera de los 400 ms efectivos pero dentro de los 1200 ms
      // nominales: si el estrechamiento fuese código muerto, esto pasaría.
      final clock = ManualClock(t0);
      final detector = buildDetector(clock);

      detector.record(
        SensorAnomaly(
          kind: SensorKind.accelerometer,
          magnitude: 30,
          at: clock.now(),
        ),
      );
      clock.advance(const Duration(milliseconds: 700));

      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.gyroscope,
            magnitude: 8,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.accumulating,
      );
    });
  });

  group('Enfriamiento ante réplicas', () {
    test('suprime las réplicas y vuelve a detectar al enfriarse', () {
      final clock = ManualClock(t0);
      final detector = DisasterDetector(
        clock: clock,
        barometerAvailable: false,
        cooldown: const Duration(seconds: 30),
      );

      detector.record(
        SensorAnomaly(
          kind: SensorKind.accelerometer,
          magnitude: 30,
          at: clock.now(),
        ),
      );
      clock.advance(const Duration(milliseconds: 100));
      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.gyroscope,
            magnitude: 8,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.disasterDetected,
      );
      expect(detector.isInCooldown, isTrue);

      clock.advance(const Duration(seconds: 5));
      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.accelerometer,
            magnitude: 35,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.suppressedByCooldown,
      );

      clock.advance(const Duration(seconds: 40));
      expect(detector.isInCooldown, isFalse);

      detector.record(
        SensorAnomaly(
          kind: SensorKind.accelerometer,
          magnitude: 30,
          at: clock.now(),
        ),
      );
      clock.advance(const Duration(milliseconds: 50));
      expect(
        detector.record(
          SensorAnomaly(
            kind: SensorKind.gyroscope,
            magnitude: 8,
            at: clock.now(),
          ),
        ),
        DetectionVerdict.disasterDetected,
      );
    });
  });

  group('Autodescubrimiento del barómetro', () {
    test('una lectura barométrica sube la exigencia a tres sensores', () {
      final clock = ManualClock(t0);
      final detector = DisasterDetector(
        clock: clock,
        barometerAvailable: false,
      );

      expect(detector.barometerAvailable, isFalse);

      detector.record(
        SensorAnomaly(
          kind: SensorKind.barometer,
          magnitude: 1.0,
          at: clock.now(),
        ),
      );

      expect(detector.barometerAvailable, isTrue);
      expect(detector.requiredSensorCount, 3);
    });
  });
}
