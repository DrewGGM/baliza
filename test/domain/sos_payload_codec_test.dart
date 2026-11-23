// Pruebas del códec del protocolo de 16 bytes.
//
// Es la pieza más crítica del dominio: si el códec se equivoca, un rescatista
// lee un grupo sanguíneo que no es. Por eso aquí no basta con un caso feliz,
// sino que se barren de forma exhaustiva los catálogos y las máscaras.

import 'dart:typed_data';

import 'package:baliza/domain/entities/medical_profile.dart';
import 'package:baliza/domain/entities/sos_signal.dart';
import 'package:baliza/domain/services/sos_payload_codec.dart';
import 'package:baliza/domain/value_objects/enums.dart';
import 'package:flutter_test/flutter_test.dart';

/// Señal con todos los campos poblados, para comprobar que nada se pierde.
SosSignal buildRichSignal() => SosSignal(
  beaconId: 0xDEADBEEF,
  messageType: MessageType.sos,
  flags: {SignalFlag.manual, SignalFlag.trapped},
  batteryPercent: 42,
  elapsedMinutes: 37,
  peopleCount: 3,
  medicalProfile: const MedicalProfile(
    bloodType: BloodType.oNegative,
    ageBand: AgeBand.senior,
    conditions: {MedicalCondition.cardiac, MedicalCondition.diabetes},
    allergies: {Allergy.penicillin},
  ),
);

void main() {
  const codec = SosPayloadCodec();

  group('CRC-16/CCITT-FALSE contra vectores conocidos', () {
    test('el vector canónico del estándar da 0x29B1', () {
      expect(SosPayloadCodec.crc16('123456789'.codeUnits), 0x29B1);
    });

    test('la entrada vacía da el valor inicial 0xFFFF', () {
      expect(SosPayloadCodec.crc16(<int>[]), 0xFFFF);
    });

    test('un único byte cero da 0xE1F0', () {
      expect(SosPayloadCodec.crc16(<int>[0x00]), 0xE1F0);
    });
  });

  group('Códec: ida y vuelta', () {
    final rich = buildRichSignal();
    final encoded = codec.encode(rich);
    final decoded = codec.decode(encoded);

    test('la trama mide exactamente 16 bytes', () {
      expect(encoded.length, 16);
    });

    test('el identificador de baliza se preserva', () {
      expect(decoded.beaconId, 0xDEADBEEF);
    });

    test('el tipo de mensaje se preserva', () {
      expect(decoded.messageType, MessageType.sos);
    });

    test('la batería se preserva', () {
      expect(decoded.batteryPercent, 42);
    });

    test('los minutos emitiendo se preservan', () {
      expect(decoded.elapsedMinutes, 37);
    });

    test('el número de personas se preserva', () {
      expect(decoded.peopleCount, 3);
    });

    test('el grupo sanguíneo se preserva', () {
      expect(decoded.medicalProfile.bloodType, BloodType.oNegative);
    });

    test('la franja etaria se preserva', () {
      expect(decoded.medicalProfile.ageBand, AgeBand.senior);
    });

    test('las condiciones médicas se preservan', () {
      expect(decoded.medicalProfile.conditions, <MedicalCondition>{
        MedicalCondition.cardiac,
        MedicalCondition.diabetes,
      });
    });

    test('las alergias se preservan', () {
      expect(decoded.medicalProfile.allergies, <Allergy>{Allergy.penicillin});
    });

    test('los indicadores manual y atrapado se preservan', () {
      expect(decoded.hasFlag(SignalFlag.manual), isTrue);
      expect(decoded.hasFlag(SignalFlag.trapped), isTrue);
    });
  });

  group('Códec: indicadores derivados', () {
    test('medicalPresent se deriva solo cuando hay ficha', () {
      final decoded = codec.decode(codec.encode(buildRichSignal()));
      expect(decoded.hasFlag(SignalFlag.medicalPresent), isTrue);
    });

    test('medicalPresent se limpia si la ficha está vacía', () {
      // El emisor declara el indicador, pero no hay ficha que respalde:
      // el códec debe corregir la mentira en vez de propagarla.
      final decoded = codec.decode(
        codec.encode(
          SosSignal(
            beaconId: 1,
            messageType: MessageType.sos,
            flags: const {SignalFlag.medicalPresent},
            batteryPercent: 80,
          ),
        ),
      );
      expect(decoded.hasFlag(SignalFlag.medicalPresent), isFalse);
    });

    test('lowBattery se activa por debajo del umbral', () {
      final decoded = codec.decode(
        codec.encode(
          SosSignal(
            beaconId: 1,
            messageType: MessageType.sos,
            batteryPercent: 9,
          ),
        ),
      );
      expect(decoded.hasFlag(SignalFlag.lowBattery), isTrue);
    });

    test('lowBattery se limpia con la batería alta', () {
      final decoded = codec.decode(
        codec.encode(
          SosSignal(
            beaconId: 1,
            messageType: MessageType.sos,
            flags: const {SignalFlag.lowBattery},
            batteryPercent: 95,
          ),
        ),
      );
      expect(decoded.hasFlag(SignalFlag.lowBattery), isFalse);
    });
  });

  group('Códec: bordes y saturación', () {
    test('el identificador máximo sobrevive', () {
      final decoded = codec.decode(
        codec.encode(
          const SosSignal(
            beaconId: 0xFFFFFFFF,
            messageType: MessageType.responder,
          ),
        ),
      );
      expect(decoded.beaconId, 0xFFFFFFFF);
      expect(decoded.messageType, MessageType.responder);
    });

    test('los minutos y las personas saturan en 255 en vez de desbordar', () {
      // Desbordar sería peor que saturar: un contador que da la vuelta
      // mostraría "2 minutos esperando" a alguien que lleva cuatro horas.
      final decoded = codec.decode(
        codec.encode(
          const SosSignal(
            beaconId: 1,
            messageType: MessageType.sos,
            elapsedMinutes: 5000,
            peopleCount: 900,
          ),
        ),
      );
      expect(decoded.elapsedMinutes, 255);
      expect(decoded.peopleCount, 255);
    });

    test('la ausencia de lectura de batería sobrevive como null', () {
      final decoded = codec.decode(
        codec.encode(
          const SosSignal(beaconId: 7, messageType: MessageType.safe),
        ),
      );
      expect(decoded.batteryPercent, isNull);
      expect(decoded.messageType, MessageType.safe);
    });
  });

  group('Códec: rechazo de tramas inválidas', () {
    Uint8List corruptedFrame() {
      final corrupt = Uint8List.fromList(codec.encode(buildRichSignal()));
      corrupt[3] = corrupt[3] ^ 0xFF; // altera el id sin recalcular el CRC
      return corrupt;
    }

    test('un CRC alterado hace que tryDecode devuelva null', () {
      expect(codec.tryDecode(corruptedFrame()), isNull);
    });

    test('un CRC alterado hace que decode lance', () {
      expect(
        () => codec.decode(corruptedFrame()),
        throwsA(isA<PayloadDecodeException>()),
      );
    });

    test('una longitud incorrecta se rechaza', () {
      expect(codec.tryDecode(Uint8List(10)), isNull);
    });

    test('una versión desconocida se rechaza aunque el CRC cuadre', () {
      final frame = Uint8List.fromList(codec.encode(buildRichSignal()));
      frame[0] = (9 << 4) | MessageType.sos.code;
      final crc = SosPayloadCodec.crc16(frame.sublist(0, 14));
      frame[14] = (crc >> 8) & 0xFF;
      frame[15] = crc & 0xFF;
      expect(codec.tryDecode(frame), isNull);
    });

    test('un tipo de mensaje desconocido se rechaza aunque el CRC cuadre', () {
      final frame = Uint8List.fromList(codec.encode(buildRichSignal()));
      frame[0] = (1 << 4) | 0x0F;
      final crc = SosPayloadCodec.crc16(frame.sublist(0, 14));
      frame[14] = (crc >> 8) & 0xFF;
      frame[15] = crc & 0xFF;
      expect(codec.tryDecode(frame), isNull);
    });
  });

  group('Códec: barrido exhaustivo de catálogos', () {
    test('todos los grupos sanguíneos y franjas etarias sobreviven', () {
      for (final blood in BloodType.values) {
        for (final age in AgeBand.values) {
          final decoded = codec.decode(
            codec.encode(
              SosSignal(
                beaconId: 0x12345678,
                messageType: MessageType.sos,
                medicalProfile: MedicalProfile(bloodType: blood, ageBand: age),
              ),
            ),
          );
          expect(decoded.medicalProfile.bloodType, blood);
          expect(decoded.medicalProfile.ageBand, age);
        }
      }
    });

    test('las 256 máscaras de condiciones son biyectivas', () {
      for (var mask = 0; mask < 256; mask++) {
        final conditions = MedicalProfile.conditionsFromMask(mask);
        expect(MedicalProfile(conditions: conditions).conditionsMask, mask);
      }
    });

    test('las 256 máscaras de alergias son biyectivas', () {
      for (var mask = 0; mask < 256; mask++) {
        final allergies = MedicalProfile.allergiesFromMask(mask);
        expect(MedicalProfile(allergies: allergies).allergiesMask, mask);
      }
    });

    test('la batería es exacta en los 101 valores posibles', () {
      for (var battery = 0; battery <= 100; battery++) {
        final decoded = codec.decode(
          codec.encode(
            SosSignal(
              beaconId: 1,
              messageType: MessageType.sos,
              batteryPercent: battery,
            ),
          ),
        );
        expect(decoded.batteryPercent, battery);
      }
    });
  });
}
