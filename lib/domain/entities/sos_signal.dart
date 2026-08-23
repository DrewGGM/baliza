import '../value_objects/enums.dart';
import 'medical_profile.dart';

/// Contenido lógico de una baliza: lo que una persona le está diciendo al
/// mundo cuando no hay red.
///
/// Es un objeto de valor inmutable y sin dependencias de plataforma. Su
/// serialización vive en `SosPayloadCodec`, no aquí: la señal no sabe que
/// existe el Bluetooth.
class SosSignal {
  const SosSignal({
    required this.beaconId,
    required this.messageType,
    this.flags = const {},
    this.batteryPercent,
    this.elapsedMinutes = 0,
    this.peopleCount = 1,
    this.medicalProfile = MedicalProfile.empty,
  });

  /// Identificador seudónimo de 32 bits. No se deriva de ningún dato del
  /// dispositivo ni de la persona: se sortea. Ver `BeaconIdentity` para la
  /// política de rotación.
  final int beaconId;

  final MessageType messageType;

  /// Circunstancias declaradas o inferidas de quien emite.
  final Set<SignalFlag> flags;

  /// Carga de la batería del emisor, 0..100. `null` si no se pudo leer.
  ///
  /// Para el rescatista es información táctica: una baliza al 4% va a
  /// desaparecer pronto y debe atenderse antes que una al 80%.
  final int? batteryPercent;

  /// Minutos que lleva activa la emisión. Saturado a 254 por el protocolo.
  final int elapsedMinutes;

  /// Cuántas personas hay en el mismo punto. Cambia por completo la logística
  /// del rescate: no es lo mismo una persona que un aula con quince.
  final int peopleCount;

  final MedicalProfile medicalProfile;

  bool get isSos => messageType == MessageType.sos;
  bool get isSafe => messageType == MessageType.safe;
  bool get isResponder => messageType == MessageType.responder;

  bool hasFlag(SignalFlag flag) => flags.contains(flag);

  bool get isTrapped => hasFlag(SignalFlag.trapped);
  bool get isAutoDetected => hasFlag(SignalFlag.autoDetected);
  bool get hasLowBattery => hasFlag(SignalFlag.lowBattery);

  SosSignal copyWith({
    int? beaconId,
    MessageType? messageType,
    Set<SignalFlag>? flags,
    int? batteryPercent,
    bool clearBattery = false,
    int? elapsedMinutes,
    int? peopleCount,
    MedicalProfile? medicalProfile,
  }) {
    return SosSignal(
      beaconId: beaconId ?? this.beaconId,
      messageType: messageType ?? this.messageType,
      flags: flags ?? this.flags,
      batteryPercent:
          clearBattery ? null : (batteryPercent ?? this.batteryPercent),
      elapsedMinutes: elapsedMinutes ?? this.elapsedMinutes,
      peopleCount: peopleCount ?? this.peopleCount,
      medicalProfile: medicalProfile ?? this.medicalProfile,
    );
  }

  @override
  String toString() =>
      'SosSignal(#${beaconId.toRadixString(16).padLeft(8, '0')}, '
      '${messageType.name}, ${elapsedMinutes}min, ${peopleCount}p)';
}
