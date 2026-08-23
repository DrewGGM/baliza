/// Catálogos codificados que viajan dentro de la trama BLE de 16 bytes.
///
/// Cada `código` es el valor real que se serializa. **Nunca** se debe reordenar
/// ni reutilizar un código existente: una baliza emitida por una versión previa
/// de la app debe seguir siendo interpretable por versiones posteriores.
library;

/// Naturaleza del mensaje que transporta la baliza.
enum MessageType {
  /// Solicitud de auxilio activa.
  sos(1),

  /// "Estoy bien": permite descartar a alguien de la lista de búsqueda.
  safe(2),

  /// Presencia de un equipo de rescate, para que las víctimas sepan que hay
  /// ayuda cerca y para coordinar rescatistas entre sí.
  responder(3);

  const MessageType(this.code);
  final int code;

  static MessageType? fromCode(int code) {
    for (final v in MessageType.values) {
      if (v.code == code) return v;
    }
    return null;
  }
}

/// Grupo sanguíneo. Se transmite para acelerar el triaje y una eventual
/// transfusión en campo.
enum BloodType {
  unknown(0, 'Desconocido'),
  oNegative(1, 'O−'),
  oPositive(2, 'O+'),
  aNegative(3, 'A−'),
  aPositive(4, 'A+'),
  bNegative(5, 'B−'),
  bPositive(6, 'B+'),
  abNegative(7, 'AB−'),
  abPositive(8, 'AB+');

  const BloodType(this.code, this.label);
  final int code;
  final String label;

  static BloodType fromCode(int code) {
    for (final v in BloodType.values) {
      if (v.code == code) return v;
    }
    return BloodType.unknown;
  }
}

/// Franja etaria. Se transmite en franjas y no como edad exacta: basta para
/// priorizar el triaje y reduce la identificabilidad de la persona.
enum AgeBand {
  unknown(0, 'Desconocida'),
  infant(1, '0–2 años'),
  child(2, '3–11 años'),
  adolescent(3, '12–17 años'),
  youngAdult(4, '18–39 años'),
  adult(5, '40–59 años'),
  senior(6, '60–74 años'),
  elder(7, '75+ años');

  const AgeBand(this.code, this.label);
  final int code;
  final String label;

  static AgeBand fromCode(int code) {
    for (final v in AgeBand.values) {
      if (v.code == code) return v;
    }
    return AgeBand.unknown;
  }

  /// Franjas que el protocolo de triaje considera de atención prioritaria.
  bool get isVulnerable =>
      this == AgeBand.infant ||
      this == AgeBand.child ||
      this == AgeBand.senior ||
      this == AgeBand.elder;
}

/// Condiciones médicas preexistentes relevantes para una atención de urgencia.
/// Viajan como máscara de bits en un único byte.
enum MedicalCondition {
  diabetes(0, 'Diabetes'),
  cardiac(1, 'Cardiopatía'),
  respiratory(2, 'Enfermedad respiratoria'),
  epilepsy(3, 'Epilepsia'),
  pregnancy(4, 'Embarazo'),
  anticoagulants(5, 'Anticoagulantes'),
  renal(6, 'Enfermedad renal'),
  immunosuppressed(7, 'Inmunosupresión');

  const MedicalCondition(this.bit, this.label);
  final int bit;
  final String label;

  /// Condiciones que elevan la prioridad de atención por riesgo de
  /// descompensación rápida bajo aplastamiento o deshidratación prolongada.
  bool get isCritical =>
      this == MedicalCondition.cardiac ||
      this == MedicalCondition.respiratory ||
      this == MedicalCondition.anticoagulants ||
      this == MedicalCondition.pregnancy;
}

/// Alergias que condicionan la medicación que puede administrarse en campo.
enum Allergy {
  penicillin(0, 'Penicilina'),
  sulfa(1, 'Sulfas'),
  nsaid(2, 'AINEs'),
  latex(3, 'Látex'),
  iodine(4, 'Yodo / contraste'),
  anesthetics(5, 'Anestésicos'),
  seafood(6, 'Mariscos'),
  other(7, 'Otra');

  const Allergy(this.bit, this.label);
  final int bit;
  final String label;
}

/// Circunstancias de la persona que emite la baliza. Máscara de bits.
enum SignalFlag {
  /// La persona pulsó el botón de auxilio de forma deliberada.
  manual(0),

  /// La baliza se activó sola tras detectar un evento sísmico.
  autoDetected(1),

  /// La trama incluye ficha médica diligenciada.
  medicalPresent(2),

  /// La persona declara estar atrapada o inmovilizada bajo estructura.
  trapped(3),

  /// Movilidad reducida (silla de ruedas, fractura, discapacidad motriz).
  mobilityImpaired(4),

  /// Batería del emisor por debajo del umbral crítico.
  lowBattery(5),

  /// Hay menores de edad en el mismo punto.
  minorsPresent(6),

  /// Reservado para versiones futuras del protocolo.
  reserved(7);

  const SignalFlag(this.bit);
  final int bit;
}
