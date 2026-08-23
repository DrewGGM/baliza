import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../domain/entities/medical_profile.dart';
import '../domain/ports/device_services.dart';
import '../domain/services/disaster_detector.dart';
import '../domain/services/distance_estimator.dart';
import '../domain/services/triage.dart';
import '../domain/value_objects/enums.dart';

/// Preferencias de la persona usuaria y su ficha médica, con persistencia.
///
/// Todo se guarda **sólo en el dispositivo**. La app no tiene servidor, no
/// tiene cuenta y no envía nada a ninguna parte: es una decisión de producto,
/// no una limitación. Una herramienta para zonas de desastre no puede depender
/// de una infraestructura que en un desastre es lo primero que cae.
class AppSettings extends ChangeNotifier {
  AppSettings(this._store);

  final SettingsStore _store;

  static const _kProfile = 'medical_profile';
  static const _kSensitivity = 'detection_sensitivity';
  static const _kAutoDetection = 'auto_detection_enabled';
  static const _kSiren = 'siren_enabled';
  static const _kVibration = 'vibration_enabled';
  static const _kTorch = 'torch_enabled';
  static const _kEnvironment = 'propagation_environment';
  static const _kStrategy = 'triage_strategy';
  static const _kPeopleCount = 'people_count';
  static const _kOnboarded = 'onboarding_completed';
  static const _kSimulation = 'simulation_enabled';

  MedicalProfile _profile = MedicalProfile.empty;
  DetectionSensitivity _sensitivity = DetectionSensitivity.medium;
  bool _autoDetection = false;
  bool _siren = true;
  bool _vibration = true;
  bool _torch = true;
  PropagationEnvironment _environment = PropagationEnvironment.rubble;
  TriageStrategy _strategy = TriageStrategy.proximity;
  int _peopleCount = 1;
  bool _onboarded = false;
  bool _simulation = false;

  MedicalProfile get profile => _profile;
  DetectionSensitivity get sensitivity => _sensitivity;

  /// Detección automática de sismos en segundo plano.
  ///
  /// Viene **desactivada** de fábrica: mantener los sensores despiertos gasta
  /// batería y es una decisión que le corresponde a la persona, no a nosotros.
  bool get autoDetection => _autoDetection;

  bool get siren => _siren;
  bool get vibration => _vibration;
  bool get torch => _torch;
  PropagationEnvironment get environment => _environment;
  TriageStrategy get strategy => _strategy;

  /// Cuántas personas hay contigo. Viaja en la baliza y cambia la logística
  /// del rescate.
  int get peopleCount => _peopleCount;

  bool get onboarded => _onboarded;

  /// Modo simulación: sustituye el radio real por el bus en memoria.
  bool get simulation => _simulation;

  DetectionThresholds get thresholds =>
      const DetectionThresholds().scaled(_sensitivity);

  DistanceEstimator get estimator =>
      DistanceEstimator(environment: _environment);

  TriageRanker get ranker =>
      TriageRanker(estimator: estimator, strategy: _strategy);

  /// Carga desde disco. Si algo está corrupto se cae al valor por defecto sin
  /// romper el arranque: la app tiene que abrir siempre.
  Future<void> load() async {
    _profile = _decodeProfile(await _store.readString(_kProfile));
    _sensitivity = _enumByName(
      DetectionSensitivity.values,
      await _store.readString(_kSensitivity),
      DetectionSensitivity.medium,
    );
    _environment = _enumByName(
      PropagationEnvironment.values,
      await _store.readString(_kEnvironment),
      PropagationEnvironment.rubble,
    );
    _strategy = _enumByName(
      TriageStrategy.values,
      await _store.readString(_kStrategy),
      TriageStrategy.proximity,
    );
    _autoDetection = await _store.readBool(_kAutoDetection) ?? false;
    _siren = await _store.readBool(_kSiren) ?? true;
    _vibration = await _store.readBool(_kVibration) ?? true;
    _torch = await _store.readBool(_kTorch) ?? true;
    _onboarded = await _store.readBool(_kOnboarded) ?? false;
    _simulation = await _store.readBool(_kSimulation) ?? false;
    _peopleCount = (await _store.readInt(_kPeopleCount) ?? 1).clamp(1, 255);
    notifyListeners();
  }

  Future<void> setProfile(MedicalProfile value) async {
    _profile = value;
    await _store.writeString(_kProfile, _encodeProfile(value));
    notifyListeners();
  }

  Future<void> setSensitivity(DetectionSensitivity value) async {
    _sensitivity = value;
    await _store.writeString(_kSensitivity, value.name);
    notifyListeners();
  }

  Future<void> setAutoDetection(bool value) async {
    _autoDetection = value;
    await _store.writeBool(_kAutoDetection, value);
    notifyListeners();
  }

  Future<void> setSiren(bool value) async {
    _siren = value;
    await _store.writeBool(_kSiren, value);
    notifyListeners();
  }

  Future<void> setVibration(bool value) async {
    _vibration = value;
    await _store.writeBool(_kVibration, value);
    notifyListeners();
  }

  Future<void> setTorch(bool value) async {
    _torch = value;
    await _store.writeBool(_kTorch, value);
    notifyListeners();
  }

  Future<void> setEnvironment(PropagationEnvironment value) async {
    _environment = value;
    await _store.writeString(_kEnvironment, value.name);
    notifyListeners();
  }

  Future<void> setStrategy(TriageStrategy value) async {
    _strategy = value;
    await _store.writeString(_kStrategy, value.name);
    notifyListeners();
  }

  Future<void> setPeopleCount(int value) async {
    _peopleCount = value.clamp(1, 255);
    await _store.writeInt(_kPeopleCount, _peopleCount);
    notifyListeners();
  }

  Future<void> setOnboarded(bool value) async {
    _onboarded = value;
    await _store.writeBool(_kOnboarded, value);
    notifyListeners();
  }

  Future<void> setSimulation(bool value) async {
    _simulation = value;
    await _store.writeBool(_kSimulation, value);
    notifyListeners();
  }

  // ------------------------------------------------------- serialización --

  static String _encodeProfile(MedicalProfile p) => jsonEncode({
        'blood': p.bloodType.code,
        'age': p.ageBand.code,
        'conditions': p.conditionsMask,
        'allergies': p.allergiesMask,
      });

  static MedicalProfile _decodeProfile(String? raw) {
    if (raw == null || raw.isEmpty) return MedicalProfile.empty;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return MedicalProfile(
        bloodType: BloodType.fromCode((map['blood'] as num?)?.toInt() ?? 0),
        ageBand: AgeBand.fromCode((map['age'] as num?)?.toInt() ?? 0),
        conditions: MedicalProfile.conditionsFromMask(
          (map['conditions'] as num?)?.toInt() ?? 0,
        ),
        allergies: MedicalProfile.allergiesFromMask(
          (map['allergies'] as num?)?.toInt() ?? 0,
        ),
      );
    } catch (_) {
      // Preferencia corrupta: se descarta en silencio. Perder la ficha médica
      // es malo, pero no abrir la app en una emergencia es peor.
      return MedicalProfile.empty;
    }
  }

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) {
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }
}
