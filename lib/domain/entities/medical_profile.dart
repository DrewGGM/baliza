import '../value_objects/enums.dart';

/// Ficha médica mínima que la persona decide compartir dentro de su baliza.
///
/// El diseño obedece a una restricción dura del protocolo: **todo el perfil
/// debe caber en tres bytes** de la trama BLE. Por eso no hay nombre, cédula ni
/// texto libre — sólo catálogos cerrados. Esa limitación resultó ser también
/// una garantía de privacidad: una baliza capturada por un tercero no permite
/// identificar a la persona, sólo atenderla.
class MedicalProfile {
  const MedicalProfile({
    this.bloodType = BloodType.unknown,
    this.ageBand = AgeBand.unknown,
    this.conditions = const {},
    this.allergies = const {},
  });

  /// Perfil vacío: la persona no ha diligenciado nada. La trama viaja igual,
  /// pero sin el indicador [SignalFlag.medicalPresent].
  static const MedicalProfile empty = MedicalProfile();

  final BloodType bloodType;
  final AgeBand ageBand;
  final Set<MedicalCondition> conditions;
  final Set<Allergy> allergies;

  /// `true` si la persona diligenció al menos un dato aprovechable.
  bool get isPresent =>
      bloodType != BloodType.unknown ||
      ageBand != AgeBand.unknown ||
      conditions.isNotEmpty ||
      allergies.isNotEmpty;

  /// Condiciones que exigen atención prioritaria en el triaje.
  Set<MedicalCondition> get criticalConditions =>
      conditions.where((c) => c.isCritical).toSet();

  /// Severidad agregada del perfil, en el rango 0–100.
  ///
  /// Alimenta el ordenamiento de la lista de rescate. No es un diagnóstico:
  /// es una heurística de priorización que sólo compara personas entre sí.
  int get severityScore {
    var score = 0;
    score += criticalConditions.length * 20;
    score += (conditions.length - criticalConditions.length) * 8;
    if (ageBand.isVulnerable) score += 15;
    if (allergies.isNotEmpty) score += 5;
    return score.clamp(0, 100);
  }

  MedicalProfile copyWith({
    BloodType? bloodType,
    AgeBand? ageBand,
    Set<MedicalCondition>? conditions,
    Set<Allergy>? allergies,
  }) {
    return MedicalProfile(
      bloodType: bloodType ?? this.bloodType,
      ageBand: ageBand ?? this.ageBand,
      conditions: conditions ?? this.conditions,
      allergies: allergies ?? this.allergies,
    );
  }

  /// Serializa el conjunto de condiciones a una máscara de un byte.
  int get conditionsMask {
    var mask = 0;
    for (final c in conditions) {
      mask |= 1 << c.bit;
    }
    return mask;
  }

  /// Serializa el conjunto de alergias a una máscara de un byte.
  int get allergiesMask {
    var mask = 0;
    for (final a in allergies) {
      mask |= 1 << a.bit;
    }
    return mask;
  }

  /// Reconstruye el conjunto de condiciones desde su máscara de bits.
  static Set<MedicalCondition> conditionsFromMask(int mask) {
    return MedicalCondition.values
        .where((c) => (mask & (1 << c.bit)) != 0)
        .toSet();
  }

  /// Reconstruye el conjunto de alergias desde su máscara de bits.
  static Set<Allergy> allergiesFromMask(int mask) {
    return Allergy.values.where((a) => (mask & (1 << a.bit)) != 0).toSet();
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is MedicalProfile &&
        other.bloodType == bloodType &&
        other.ageBand == ageBand &&
        _setEquals(other.conditions, conditions) &&
        _setEquals(other.allergies, allergies);
  }

  @override
  int get hashCode =>
      Object.hash(bloodType, ageBand, conditionsMask, allergiesMask);

  static bool _setEquals<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  String toString() =>
      'MedicalProfile(${bloodType.label}, ${ageBand.label}, '
      '${conditions.length} cond., ${allergies.length} alergias)';
}
