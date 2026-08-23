import 'dart:typed_data';

import '../entities/medical_profile.dart';
import '../entities/sos_signal.dart';
import '../value_objects/enums.dart';

/// Error de decodificación de una trama Baliza.
class PayloadDecodeException implements Exception {
  const PayloadDecodeException(this.reason);
  final String reason;
  @override
  String toString() => 'PayloadDecodeException: $reason';
}

/// Serializa y deserializa el protocolo Baliza v1.
///
/// ## Por qué 16 bytes
///
/// Una trama de anuncio BLE *legacy* tiene 31 bytes en total. De ahí salen
/// 3 bytes de Flags, 4 bytes para declarar el UUID de servicio de 16 bits y
/// 4 bytes de cabecera de Manufacturer Specific Data. Quedan 20 bytes útiles.
/// Fijamos el mensaje en 16 para dejar margen a extensiones y para que la
/// trama siga cabiendo si en el futuro se añade un nombre local corto.
///
/// Esa restricción es la que explica todo el diseño: no hay nombres, ni
/// documento de identidad, ni texto libre. Sólo catálogos cerrados y máscaras
/// de bits. El efecto secundario es deseable: una baliza interceptada permite
/// atender a la persona pero no identificarla.
///
/// ## Mapa de la trama
///
///     Offset  Tam  Campo
///     0       1    versión (4 bits altos) | tipo de mensaje (4 bits bajos)
///     1       1    indicadores de situación (máscara de bits)
///     2       4    identificador de baliza, uint32 big-endian
///     6       1    batería 0..100  (0xFF = desconocida)
///     7       1    minutos transcurridos 0..254 (255 = 254 o más)
///     8       1    grupo sanguíneo (4 bits altos) | franja etaria (4 bajos)
///     9       1    condiciones médicas (máscara de bits)
///     10      1    alergias (máscara de bits)
///     11      1    personas en el punto 0..254 (255 = 254 o más)
///     12      2    reservado, debe ser 0 en v1
///     14      2    CRC-16/CCITT-FALSE sobre los bytes 0..13
///
/// Todos los enteros multibyte viajan en big-endian (orden de red).
class SosPayloadCodec {
  const SosPayloadCodec();

  /// Longitud exacta de una trama Baliza, en bytes.
  static const int payloadLength = 16;

  /// Versión del protocolo que produce este códec.
  static const int protocolVersion = 1;

  /// Valor centinela para campos de un byte cuyo dato se desconoce o se sale
  /// del rango representable.
  static const int unknownByte = 0xFF;

  /// Umbral de batería por debajo del cual se marca [SignalFlag.lowBattery].
  static const int lowBatteryThreshold = 15;

  static const int _offsetHeader = 0;
  static const int _offsetFlags = 1;
  static const int _offsetBeaconId = 2;
  static const int _offsetBattery = 6;
  static const int _offsetElapsed = 7;
  static const int _offsetBloodAge = 8;
  static const int _offsetConditions = 9;
  static const int _offsetAllergies = 10;
  static const int _offsetPeople = 11;
  static const int _offsetReserved = 12;
  static const int _offsetCrc = 14;

  // ---------------------------------------------------------------- encode --

  /// Convierte una señal de dominio en los 16 bytes que se emiten por BLE.
  Uint8List encode(SosSignal signal) {
    final bytes = Uint8List(payloadLength);
    final view = ByteData.view(bytes.buffer);

    bytes[_offsetHeader] =
        ((protocolVersion & 0x0F) << 4) | (signal.messageType.code & 0x0F);
    bytes[_offsetFlags] = _flagsMask(signal);

    view.setUint32(_offsetBeaconId, signal.beaconId & 0xFFFFFFFF, Endian.big);

    final battery = signal.batteryPercent;
    bytes[_offsetBattery] = battery == null ? unknownByte : battery.clamp(0, 100);

    bytes[_offsetElapsed] = _saturate(signal.elapsedMinutes);

    final profile = signal.medicalProfile;
    bytes[_offsetBloodAge] =
        ((profile.bloodType.code & 0x0F) << 4) | (profile.ageBand.code & 0x0F);
    bytes[_offsetConditions] = profile.conditionsMask;
    bytes[_offsetAllergies] = profile.allergiesMask;

    bytes[_offsetPeople] = _saturate(signal.peopleCount);

    view.setUint16(_offsetReserved, 0, Endian.big);
    view.setUint16(_offsetCrc, crc16(bytes.sublist(0, _offsetCrc)), Endian.big);

    return bytes;
  }

  /// Satura un entero al rango 0..254, reservando 255 como "254 o más".
  int _saturate(int value) {
    if (value < 0) return 0;
    if (value > 254) return unknownByte;
    return value;
  }

  /// Construye la máscara de indicadores, derivando los que son consecuencia
  /// del estado en vez de confiar en que quien llama los haya puesto bien.
  int _flagsMask(SosSignal signal) {
    var mask = 0;
    for (final f in signal.flags) {
      mask |= 1 << f.bit;
    }

    // Derivados: el códec es la única fuente de verdad para estos dos.
    if (signal.medicalProfile.isPresent) {
      mask |= 1 << SignalFlag.medicalPresent.bit;
    } else {
      mask &= ~(1 << SignalFlag.medicalPresent.bit);
    }

    final battery = signal.batteryPercent;
    if (battery != null && battery <= lowBatteryThreshold) {
      mask |= 1 << SignalFlag.lowBattery.bit;
    } else {
      mask &= ~(1 << SignalFlag.lowBattery.bit);
    }

    return mask & 0xFF;
  }

  // ---------------------------------------------------------------- decode --

  /// Reconstruye una señal a partir de los bytes recibidos por BLE.
  ///
  /// Lanza [PayloadDecodeException] si la trama no es una Baliza válida. Se
  /// prefiere fallar de forma explícita antes que entregar al rescatista una
  /// ficha médica corrupta: un dato equivocado sobre alergias puede matar.
  SosSignal decode(Uint8List bytes) {
    if (bytes.length != payloadLength) {
      throw PayloadDecodeException(
        'longitud ${bytes.length}, se esperaban $payloadLength bytes',
      );
    }

    final view = ByteData.view(bytes.buffer, bytes.offsetInBytes);

    final expectedCrc = view.getUint16(_offsetCrc, Endian.big);
    final actualCrc = crc16(bytes.sublist(0, _offsetCrc));
    if (expectedCrc != actualCrc) {
      throw PayloadDecodeException(
        'CRC inválido: trama 0x${expectedCrc.toRadixString(16)}, '
        'calculado 0x${actualCrc.toRadixString(16)}',
      );
    }

    final header = bytes[_offsetHeader];
    final version = (header >> 4) & 0x0F;
    if (version != protocolVersion) {
      throw PayloadDecodeException(
        'versión de protocolo no soportada: $version',
      );
    }

    final messageType = MessageType.fromCode(header & 0x0F);
    if (messageType == null) {
      throw PayloadDecodeException(
        'tipo de mensaje desconocido: ${header & 0x0F}',
      );
    }

    final flagsMask = bytes[_offsetFlags];
    final flags =
        SignalFlag.values.where((f) => (flagsMask & (1 << f.bit)) != 0).toSet();

    final rawBattery = bytes[_offsetBattery];
    final battery = rawBattery == unknownByte ? null : rawBattery.clamp(0, 100);

    final bloodAge = bytes[_offsetBloodAge];
    final profile = MedicalProfile(
      bloodType: BloodType.fromCode((bloodAge >> 4) & 0x0F),
      ageBand: AgeBand.fromCode(bloodAge & 0x0F),
      conditions: MedicalProfile.conditionsFromMask(bytes[_offsetConditions]),
      allergies: MedicalProfile.allergiesFromMask(bytes[_offsetAllergies]),
    );

    return SosSignal(
      beaconId: view.getUint32(_offsetBeaconId, Endian.big),
      messageType: messageType,
      flags: flags,
      batteryPercent: battery,
      elapsedMinutes: bytes[_offsetElapsed],
      peopleCount: bytes[_offsetPeople],
      medicalProfile: profile,
    );
  }

  /// Intenta decodificar y devuelve `null` en vez de lanzar.
  ///
  /// Es la vía que usa el escáner: en un entorno urbano llegan cientos de
  /// anuncios BLE por minuto y casi ninguno es una Baliza. Que un televisor
  /// vecino emita basura no debe interrumpir la búsqueda.
  SosSignal? tryDecode(Uint8List bytes) {
    try {
      return decode(bytes);
    } on PayloadDecodeException {
      return null;
    } on RangeError {
      return null;
    }
  }

  // ------------------------------------------------------------------- crc --

  /// CRC-16/CCITT-FALSE: polinomio 0x1021, inicial 0xFFFF, sin reflexión.
  ///
  /// Se eligió por ser el estándar de facto en enlaces de radio cortos y por
  /// detectar de forma fiable las ráfagas de error típicas de un canal 2.4 GHz
  /// saturado, que es exactamente el escenario tras un sismo urbano.
  static int crc16(List<int> data) {
    var crc = 0xFFFF;
    for (final byte in data) {
      crc ^= (byte & 0xFF) << 8;
      for (var i = 0; i < 8; i++) {
        if ((crc & 0x8000) != 0) {
          crc = ((crc << 1) ^ 0x1021) & 0xFFFF;
        } else {
          crc = (crc << 1) & 0xFFFF;
        }
      }
    }
    return crc & 0xFFFF;
  }
}
