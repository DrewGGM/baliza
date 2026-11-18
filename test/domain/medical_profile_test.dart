// Pruebas de la ficha médica.
//
// La puntuación de severidad no es un triaje clínico: sólo ordena a quién
// atender primero cuando hay varias señales en pantalla y un solo equipo.

import 'package:baliza/domain/entities/medical_profile.dart';
import 'package:baliza/domain/value_objects/enums.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Presencia de la ficha', () {
    test('una ficha vacía no se considera presente', () {
      expect(MedicalProfile.empty.isPresent, isFalse);
    });

    test('sólo el grupo sanguíneo ya la hace presente', () {
      const profile = MedicalProfile(bloodType: BloodType.aPositive);
      expect(profile.isPresent, isTrue);
    });
  });

  group('Puntuación de severidad', () {
    test('un perfil crítico puntúa más que uno leve', () {
      const critical = MedicalProfile(
        ageBand: AgeBand.elder,
        conditions: {MedicalCondition.cardiac, MedicalCondition.anticoagulants},
      );
      const mild = MedicalProfile(
        ageBand: AgeBand.youngAdult,
        conditions: {MedicalCondition.diabetes},
      );

      expect(critical.severityScore, greaterThan(mild.severityScore));
    });

    test('la severidad está acotada a 100', () {
      const worstCase = MedicalProfile(
        ageBand: AgeBand.infant,
        conditions: {
          MedicalCondition.cardiac,
          MedicalCondition.respiratory,
          MedicalCondition.anticoagulants,
          MedicalCondition.pregnancy,
          MedicalCondition.diabetes,
          MedicalCondition.epilepsy,
          MedicalCondition.renal,
          MedicalCondition.immunosuppressed,
        },
        allergies: {Allergy.penicillin},
      );

      expect(worstCase.severityScore, 100);
    });
  });

  group('Conversión a códigos y reconstrucción', () {
    test('una ficha reconstruida desde sus códigos es igual a la original', () {
      const original = MedicalProfile(
        bloodType: BloodType.abNegative,
        ageBand: AgeBand.senior,
        conditions: {MedicalCondition.cardiac},
        allergies: {Allergy.latex},
      );

      final rebuilt = MedicalProfile(
        bloodType: BloodType.fromCode(original.bloodType.code),
        ageBand: AgeBand.fromCode(original.ageBand.code),
        conditions: MedicalProfile.conditionsFromMask(original.conditionsMask),
        allergies: MedicalProfile.allergiesFromMask(original.allergiesMask),
      );

      expect(rebuilt, original);
    });

    test('la ficha vacía y la ficha con todo marcado sobreviven el viaje', () {
      final full = MedicalProfile(
        conditions: MedicalCondition.values.toSet(),
        allergies: Allergy.values.toSet(),
      );

      for (final profile in [MedicalProfile.empty, full]) {
        expect(
          MedicalProfile.conditionsFromMask(profile.conditionsMask),
          profile.conditions,
        );
        expect(
          MedicalProfile.allergiesFromMask(profile.allergiesMask),
          profile.allergies,
        );
      }
    });

    test('un código fuera de catálogo queda sin definir en vez de fallar', () {
      expect(BloodType.fromCode(15), BloodType.unknown);
      expect(AgeBand.fromCode(15), AgeBand.unknown);
    });
  });
}
