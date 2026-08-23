import '../../domain/entities/medical_profile.dart';
import '../../domain/entities/sos_signal.dart';
import '../../domain/value_objects/enums.dart';
import 'simulated_radio.dart';

/// Escenarios precargados para recorrer la app sin hardware.
///
/// No son adornos de demostración: son el banco de pruebas con el que se
/// valida que la lista de rescate ordena bien, que la tendencia de proximidad
/// reacciona al caminar y que la interfaz aguanta desde cero balizas hasta
/// una decena simultánea.
class SimulationScenario {
  const SimulationScenario({
    required this.id,
    required this.name,
    required this.description,
    required this.build,
  });

  final String id;
  final String name;
  final String description;
  final List<SimulatedPeer> Function() build;

  static SosSignal _sos({
    required int id,
    int minutes = 0,
    int people = 1,
    int? battery = 60,
    Set<SignalFlag> flags = const {SignalFlag.manual},
    MedicalProfile profile = MedicalProfile.empty,
  }) {
    return SosSignal(
      beaconId: id,
      messageType: MessageType.sos,
      flags: flags,
      batteryPercent: battery,
      elapsedMinutes: minutes,
      peopleCount: people,
      medicalProfile: profile,
    );
  }

  /// Nadie alrededor. Verifica el estado vacío de la pantalla de rescate.
  static final empty = SimulationScenario(
    id: 'empty',
    name: 'Sin señales',
    description: 'Nadie emitiendo alrededor. Comprueba el estado vacío.',
    build: () => [],
  );

  /// Una sola persona acercándose: valida la lectura de tendencia.
  static final single = SimulationScenario(
    id: 'single',
    name: 'Una persona',
    description:
        'Una baliza a 18 m que se acerca. Verifica la tendencia "te estás acercando".',
    build: () => [
      SimulatedPeer(
        signal: _sos(
          id: 0xA1B2C3D4,
          minutes: 12,
          battery: 74,
          profile: const MedicalProfile(
            bloodType: BloodType.oPositive,
            ageBand: AgeBand.youngAdult,
          ),
        ),
        distanceMeters: 18,
        driftMetersPerTick: -0.35,
      ),
    ],
  );

  /// Colapso de un edificio: varias personas a distintas distancias, con
  /// perfiles médicos y urgencias distintas. Es el escenario que valida el
  /// ordenamiento de triaje.
  static final collapse = SimulationScenario(
    id: 'collapse',
    name: 'Colapso de edificio',
    description:
        'Seis balizas con gravedad y distancia dispares. Valida el orden de triaje.',
    build: () => [
      // Muy cerca, sin gravedad: debería encabezar por cercanía.
      SimulatedPeer(
        signal: _sos(id: 0x8C41B70F, minutes: 8, battery: 88),
        distanceMeters: 1.4,
      ),
      // Lejos pero crítico: sube al cambiar la estrategia a "Gravedad".
      SimulatedPeer(
        signal: _sos(
          id: 0x3D92A45E,
          minutes: 95,
          battery: 12,
          flags: {SignalFlag.autoDetected, SignalFlag.trapped},
          profile: const MedicalProfile(
            bloodType: BloodType.abNegative,
            ageBand: AgeBand.elder,
            conditions: {
              MedicalCondition.cardiac,
              MedicalCondition.anticoagulants,
            },
            allergies: {Allergy.penicillin},
          ),
        ),
        distanceMeters: 26,
        driftMetersPerTick: -0.2,
      ),
      // Un grupo: sube al ordenar por número de personas.
      SimulatedPeer(
        signal: _sos(
          id: 0x71E5C82B,
          minutes: 40,
          people: 9,
          battery: 55,
          flags: {SignalFlag.manual, SignalFlag.minorsPresent},
          profile: const MedicalProfile(ageBand: AgeBand.child),
        ),
        distanceMeters: 11,
      ),
      // Batería agonizante: el indicador debe destacarlo.
      SimulatedPeer(
        signal: _sos(
          id: 0xE20D3F91,
          minutes: 210,
          battery: 3,
          flags: {SignalFlag.autoDetected, SignalFlag.trapped},
          profile: const MedicalProfile(
            bloodType: BloodType.aPositive,
            ageBand: AgeBand.adult,
            conditions: {MedicalCondition.diabetes},
          ),
        ),
        distanceMeters: 7.5,
        driftMetersPerTick: 0.12,
      ),
      // Movilidad reducida a media distancia.
      SimulatedPeer(
        signal: _sos(
          id: 0x9AB6742D,
          minutes: 63,
          battery: 41,
          flags: {SignalFlag.manual, SignalFlag.mobilityImpaired},
          profile: const MedicalProfile(
            bloodType: BloodType.bPositive,
            ageBand: AgeBand.senior,
            conditions: {MedicalCondition.respiratory},
          ),
        ),
        distanceMeters: 14,
      ),
      // Muy lejos, al límite del alcance.
      SimulatedPeer(
        signal: _sos(id: 0x4F17E6C3, minutes: 5, battery: 96),
        distanceMeters: 44,
        driftMetersPerTick: -0.5,
      ),
    ],
  );

  /// Mezcla de tipos de mensaje: auxilio, gente a salvo y otro equipo de
  /// rescate. Valida que la lista filtra correctamente.
  static final mixed = SimulationScenario(
    id: 'mixed',
    name: 'Zona con rescatistas',
    description:
        'Auxilios, personas a salvo y otro equipo de rescate en la misma zona.',
    build: () => [
      SimulatedPeer(
        signal: _sos(id: 0xB3C85A19, minutes: 30, battery: 60),
        distanceMeters: 6,
      ),
      SimulatedPeer(
        signal: const SosSignal(
          beaconId: 0x62F09D74,
          messageType: MessageType.safe,
          batteryPercent: 70,
        ),
        distanceMeters: 9,
      ),
      SimulatedPeer(
        signal: const SosSignal(
          beaconId: 0xD84E21B6,
          messageType: MessageType.responder,
          batteryPercent: 85,
        ),
        distanceMeters: 20,
      ),
    ],
  );

  /// Saturación: valida el rendimiento de la lista y que nada se atasque.
  static final crowded = SimulationScenario(
    id: 'crowded',
    name: 'Saturación',
    description: 'Veinte balizas simultáneas. Prueba de carga de la interfaz.',
    build: () => List.generate(20, (i) {
      return SimulatedPeer(
        signal: _sos(
          id: 0x5C000000 + (i * 0x1F3B7) + 0x2A41,
          minutes: (i * 17) % 240,
          people: 1 + (i % 4),
          battery: 100 - (i * 4),
          profile: i.isEven
              ? MedicalProfile(
                  bloodType: BloodType.fromCode(1 + (i % 8)),
                  ageBand: AgeBand.fromCode(1 + (i % 7)),
                )
              : MedicalProfile.empty,
        ),
        distanceMeters: 2.0 + i * 2.3,
        driftMetersPerTick: i.isEven ? -0.15 : 0.1,
      );
    }),
  );

  static final all = <SimulationScenario>[
    empty,
    single,
    collapse,
    mixed,
    crowded,
  ];

  static SimulationScenario byId(String id) =>
      all.firstWhere((s) => s.id == id, orElse: () => empty);
}
