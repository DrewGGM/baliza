// Pruebas del ordenamiento por prioridad de atención.
//
// Esto no es un protocolo de triaje clínico y las pruebas no pretenden que lo
// sea: lo que se verifica es que el orden propuesto responda al criterio que
// el rescatista eligió, y que sea estable, porque una lista que se reordena
// sola mientras alguien la mira es una fuente de errores.

import 'package:baliza/domain/entities/medical_profile.dart';
import 'package:baliza/domain/entities/sos_signal.dart';
import 'package:baliza/domain/entities/survivor.dart';
import 'package:baliza/domain/services/triage.dart';
import 'package:baliza/domain/value_objects/enums.dart';
import 'package:flutter_test/flutter_test.dart';

final DateTime now = DateTime(2026, 8, 10, 8, 0);

/// Lecturas de señal fuerte y débil, para situar balizas cerca y lejos sin
/// depender de los umbrales exactos de cada banda.
const List<int> strongSignal = <int>[-45, -45, -45, -45, -45, -45];
const List<int> weakSignal = <int>[-95, -95, -95, -95, -95, -95];

Survivor buildSurvivor({
  required int beaconId,
  List<int> rssi = strongSignal,
  int elapsedMinutes = 10,
  int peopleCount = 1,
  MedicalProfile medical = MedicalProfile.empty,
  Set<SignalFlag> flags = const <SignalFlag>{},
  Duration silence = Duration.zero,
}) {
  final signal = SosSignal(
    beaconId: beaconId,
    messageType: MessageType.sos,
    flags: flags,
    elapsedMinutes: elapsedMinutes,
    peopleCount: peopleCount,
    medicalProfile: medical,
  );
  return Survivor(
    beaconId: beaconId,
    signal: signal,
    firstSeen: now.subtract(Duration(minutes: elapsedMinutes)),
    lastSeen: now.subtract(silence),
    rssiSamples: List<int>.of(rssi),
  );
}

void main() {
  const ranker = TriageRanker();

  group('El puntaje respeta sus límites', () {
    test('siempre queda dentro de 0..1000', () {
      final minimal = buildSurvivor(
        beaconId: 1,
        rssi: <int>[],
        elapsedMinutes: 0,
      );
      final maximal = buildSurvivor(
        beaconId: 2,
        elapsedMinutes: 5000,
        peopleCount: 900,
        medical: const MedicalProfile(
          ageBand: AgeBand.infant,
          conditions: {MedicalCondition.cardiac, MedicalCondition.respiratory},
        ),
        flags: const {SignalFlag.trapped, SignalFlag.mobilityImpaired},
      );

      expect(ranker.score(minimal, now), inInclusiveRange(0, 1000));
      expect(ranker.score(maximal, now), inInclusiveRange(0, 1000));
    });
  });

  group('Cada estrategia ordena por su criterio', () {
    test('por cercanía, la señal más fuerte va primero', () {
      final near = buildSurvivor(beaconId: 0xAAA, rssi: strongSignal);
      final far = buildSurvivor(beaconId: 0xBBB, rssi: weakSignal);

      final ordered = ranker.rank(<Survivor>[far, near], now);

      expect(ordered.first.beaconId, near.beaconId);
    });

    test('por gravedad, el perfil más grave va primero', () {
      final severe = buildSurvivor(
        beaconId: 0xAAA,
        medical: const MedicalProfile(
          ageBand: AgeBand.elder,
          conditions: {
            MedicalCondition.cardiac,
            MedicalCondition.anticoagulants,
          },
        ),
      );
      final mild = buildSurvivor(beaconId: 0xBBB);

      final ordered = ranker.withStrategy(TriageStrategy.medical).rank(
        <Survivor>[mild, severe],
        now,
      );

      expect(ordered.first.beaconId, severe.beaconId);
    });

    test('por tiempo, quien lleva más esperando va primero', () {
      final waiting = buildSurvivor(beaconId: 0xAAA, elapsedMinutes: 240);
      final recent = buildSurvivor(beaconId: 0xBBB, elapsedMinutes: 2);

      final ordered = ranker.withStrategy(TriageStrategy.elapsed).rank(
        <Survivor>[recent, waiting],
        now,
      );

      expect(ordered.first.beaconId, waiting.beaconId);
    });

    test('por número de personas, el grupo mayor va primero', () {
      final group = buildSurvivor(beaconId: 0xAAA, peopleCount: 8);
      final alone = buildSurvivor(beaconId: 0xBBB);

      final ordered = ranker.withStrategy(TriageStrategy.groupSize).rank(
        <Survivor>[alone, group],
        now,
      );

      expect(ordered.first.beaconId, group.beaconId);
    });
  });

  group('Matices del ordenamiento', () {
    test('estar atrapado sube la prioridad médica', () {
      final trapped = buildSurvivor(
        beaconId: 0xAAA,
        flags: const {SignalFlag.trapped},
      );
      final free = buildSurvivor(beaconId: 0xBBB);

      final medicalRanker = ranker.withStrategy(TriageStrategy.medical);

      expect(
        medicalRanker.score(trapped, now),
        greaterThan(medicalRanker.score(free, now)),
      );
    });

    test('el silencio prolongado hace perder prioridad', () {
      // Puede que ya la hayan rescatado o que el aparato se haya apagado. No
      // se descarta de la lista, pero deja de encabezarla.
      final silent = buildSurvivor(
        beaconId: 0xAAA,
        silence: const Duration(minutes: 5),
      );
      final active = buildSurvivor(beaconId: 0xBBB);

      expect(silent.isStale(now), isTrue);
      expect(ranker.score(silent, now), lessThan(ranker.score(active, now)));
    });

    test('a igualdad de puntaje el orden es estable por identificador', () {
      final first = buildSurvivor(beaconId: 0x1111);
      final second = buildSurvivor(beaconId: 0x2222);

      expect(ranker.score(first, now), ranker.score(second, now));

      final ordered = ranker.rank(<Survivor>[second, first], now);
      expect(ordered.map((s) => s.beaconId).toList(), <int>[
        first.beaconId,
        second.beaconId,
      ]);
    });

    test('ordenar no pierde ni duplica balizas', () {
      final survivors = <Survivor>[
        buildSurvivor(beaconId: 0x1111, rssi: weakSignal),
        buildSurvivor(beaconId: 0x2222, elapsedMinutes: 300),
        buildSurvivor(beaconId: 0x3333, peopleCount: 5),
      ];

      final ordered = ranker.rank(survivors, now);

      expect(ordered.length, survivors.length);
      expect(
        ordered.map((s) => s.beaconId).toSet(),
        survivors.map((s) => s.beaconId).toSet(),
      );
    });
  });
}
