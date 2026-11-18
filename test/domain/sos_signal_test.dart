// Pruebas de la entidad de la señal.
//
// La señal es un objeto de valor: dos señales con los mismos datos son la
// misma señal, y copiarla cambiando un campo no debe arrastrar ningún otro.

import 'package:baliza/domain/entities/medical_profile.dart';
import 'package:baliza/domain/entities/sos_signal.dart';
import 'package:baliza/domain/value_objects/enums.dart';
import 'package:flutter_test/flutter_test.dart';

SosSignal buildSignal() => SosSignal(
  beaconId: 0x1234ABCD,
  messageType: MessageType.sos,
  flags: {SignalFlag.autoDetected, SignalFlag.trapped},
  batteryPercent: 40,
  elapsedMinutes: 12,
  peopleCount: 3,
  medicalProfile: const MedicalProfile(
    bloodType: BloodType.oNegative,
    ageBand: AgeBand.adult,
    conditions: {MedicalCondition.diabetes},
    allergies: {Allergy.penicillin},
  ),
);

void main() {
  group('Copia con un campo cambiado', () {
    test('sólo cambia el campo pedido', () {
      final original = buildSignal();
      final copy = original.copyWith(peopleCount: 5);

      expect(copy.peopleCount, 5);
      expect(copy.beaconId, original.beaconId);
      expect(copy.messageType, original.messageType);
      expect(copy.flags, original.flags);
      expect(copy.batteryPercent, original.batteryPercent);
      expect(copy.elapsedMinutes, original.elapsedMinutes);
      expect(copy.medicalProfile, original.medicalProfile);
    });

    test('clearBattery deja la batería sin dato', () {
      final copy = buildSignal().copyWith(clearBattery: true);
      expect(copy.batteryPercent, isNull);
    });

    test('copiar sin cambios da una señal igual', () {
      final original = buildSignal();
      expect(original.copyWith(), original);
    });
  });

  group('Igualdad por valor', () {
    test('dos señales con los mismos datos son iguales', () {
      expect(buildSignal(), buildSignal());
      expect(buildSignal().hashCode, buildSignal().hashCode);
    });

    test('el orden de las banderas no importa', () {
      final a = buildSignal().copyWith(
        flags: {SignalFlag.autoDetected, SignalFlag.trapped},
      );
      final b = buildSignal().copyWith(
        flags: {SignalFlag.trapped, SignalFlag.autoDetected},
      );
      expect(a, b);
    });

    test('un campo distinto basta para que no sean iguales', () {
      final original = buildSignal();
      expect(original.copyWith(elapsedMinutes: 13), isNot(original));
      expect(original.copyWith(flags: {SignalFlag.manual}), isNot(original));
    });
  });

  group('Consultas', () {
    test('las banderas se leen como propiedades', () {
      final signal = buildSignal();
      expect(signal.isSos, isTrue);
      expect(signal.isTrapped, isTrue);
      expect(signal.isAutoDetected, isTrue);
      expect(signal.hasLowBattery, isFalse);
    });
  });
}
