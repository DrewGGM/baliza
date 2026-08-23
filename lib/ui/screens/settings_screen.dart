import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/baliza_runtime.dart';
import '../../domain/services/disaster_detector.dart';
import '../../domain/services/distance_estimator.dart';
import '../../infrastructure/simulation/scenarios.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'medical_profile_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        runtime.settings,
        runtime.detection,
      ]),
      builder: (context, _) {
        final settings = runtime.settings;
        final detection = runtime.detection;

        return Scaffold(
          body: SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                Space.lg,
                Space.xl,
                Space.xxxl,
              ),
              children: <Widget>[
                Text('Ajustes', style: BalizaText.display),
                const SizedBox(height: Space.xl),

                // -- Ficha médica -------------------------------------------
                BalizaCard(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const MedicalProfileScreen(),
                    ),
                  ),
                  padding: const EdgeInsets.all(Space.lg),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.medical_information_outlined,
                        color: settings.profile.isPresent
                            ? BalizaColors.safe
                            : BalizaColors.warning,
                        size: 26,
                      ),
                      const SizedBox(width: Space.lg),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text('Mi ficha médica', style: BalizaText.body),
                            const SizedBox(height: 2),
                            Text(
                              settings.profile.isPresent
                                  ? '${settings.profile.bloodType.label} · '
                                      '${settings.profile.conditions.length} '
                                      'condiciones · '
                                      '${settings.profile.allergies.length} '
                                      'alergias'
                                  : 'Sin llenar',
                              style: BalizaText.caption.copyWith(
                                color: settings.profile.isPresent
                                    ? BalizaColors.textSecondary
                                    : BalizaColors.warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(
                        Icons.chevron_right,
                        color: BalizaColors.textTertiary,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),

                // -- Detección automática -----------------------------------
                const SectionHeader('Detección automática de sismos'),
                BalizaCard(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.autoDetection,
                        onChanged: (v) async {
                          await settings.setAutoDetection(v);
                          if (v) {
                            await detection.start();
                          } else {
                            await detection.stop();
                          }
                        },
                        title: Text('Vigilar sensores', style: BalizaText.body),
                        subtitle: Text(
                          'Si detectamos un sismo te preguntaremos si estás '
                          'bien. Si no respondes, emitimos auxilio solos.',
                          style: BalizaText.caption,
                        ),
                      ),
                      if (settings.autoDetection) ...<Widget>[
                        const Divider(height: Space.xl),
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: DataPoint(
                                label: 'Estado',
                                value: detection.isMonitoring
                                    ? 'Vigilando'
                                    : 'Detenida',
                                icon: Icons.sensors,
                                valueColor: detection.isMonitoring
                                    ? BalizaColors.safe
                                    : BalizaColors.warning,
                              ),
                            ),
                            Expanded(
                              child: DataPoint(
                                label: 'Sensores',
                                value: '${detection.requiredSensorCount} '
                                    'requeridos',
                                icon: Icons.hub_outlined,
                              ),
                            ),
                            Expanded(
                              child: DataPoint(
                                label: 'Barómetro',
                                value: detection.hasBarometer ? 'Sí' : 'No',
                                icon: Icons.speed,
                                valueColor: detection.hasBarometer
                                    ? BalizaColors.safe
                                    : BalizaColors.textTertiary,
                              ),
                            ),
                          ],
                        ),
                        if (!detection.hasBarometer) ...<Widget>[
                          const SizedBox(height: Space.lg),
                          const InlineNotice(
                            message: 'Tu equipo no tiene barómetro. Usamos dos '
                                'sensores en lugar de tres y exigimos que '
                                'coincidan en una ventana más estrecha, para '
                                'compensar la falta del tercero.',
                            icon: Icons.info_outline,
                            color: BalizaColors.info,
                          ),
                        ],
                        const SizedBox(height: Space.lg),
                        Text(
                          'SENSIBILIDAD',
                          style: BalizaText.caption.copyWith(
                            color: BalizaColors.textTertiary,
                            fontSize: 11,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: Space.sm),
                        SegmentedButton<DetectionSensitivity>(
                          segments: DetectionSensitivity.values
                              .map(
                                (s) => ButtonSegment<DetectionSensitivity>(
                                  value: s,
                                  label: Text(s.label),
                                ),
                              )
                              .toList(),
                          selected: <DetectionSensitivity>{
                            settings.sensitivity,
                          },
                          onSelectionChanged: (set) async {
                            await settings.setSensitivity(set.first);
                            await detection.applySensitivity();
                          },
                        ),
                        const SizedBox(height: Space.sm),
                        Text(
                          'Más sensibilidad detecta sismos más leves, pero '
                          'también más falsas alarmas.',
                          style: BalizaText.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),

                // -- Señales de auxilio --------------------------------------
                const SectionHeader('Al pedir ayuda'),
                BalizaCard(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg),
                  child: Column(
                    children: <Widget>[
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.siren,
                        onChanged: (v) => unawaited(settings.setSiren(v)),
                        secondary: const Icon(Icons.volume_up_outlined),
                        title: Text('Sirena', style: BalizaText.body),
                        subtitle: Text(
                          'El último tramo del rescate se hace de oído.',
                          style: BalizaText.caption,
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.vibration,
                        onChanged: (v) => unawaited(settings.setVibration(v)),
                        secondary: const Icon(Icons.vibration),
                        title: Text('Vibración', style: BalizaText.body),
                        subtitle: Text(
                          'Patrón SOS en morse.',
                          style: BalizaText.caption,
                        ),
                      ),
                      const Divider(),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: settings.torch,
                        onChanged: (v) => unawaited(settings.setTorch(v)),
                        secondary: const Icon(Icons.flashlight_on_outlined),
                        title: Text('Linterna', style: BalizaText.body),
                        subtitle: Text(
                          'Destellos SOS. Gasta batería rápido.',
                          style: BalizaText.caption,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),

                // -- Entorno de propagación ----------------------------------
                const SectionHeader('Entorno'),
                BalizaCard(
                  padding: const EdgeInsets.all(Space.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        'Dónde estás buscando',
                        style: BalizaText.body,
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        'Ajusta cómo se traduce la potencia de señal en '
                        'distancia. El hormigón atenúa mucho más que el aire.',
                        style: BalizaText.caption,
                      ),
                      const SizedBox(height: Space.md),
                      SegmentedButton<PropagationEnvironment>(
                        segments: PropagationEnvironment.values
                            .map(
                              (e) => ButtonSegment<PropagationEnvironment>(
                                value: e,
                                label: Text(e.label),
                              ),
                            )
                            .toList(),
                        selected: <PropagationEnvironment>{
                          settings.environment,
                        },
                        onSelectionChanged: (set) =>
                            unawaited(settings.setEnvironment(set.first)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: Space.xl),

                // -- Simulación ----------------------------------------------
                if (runtime.isSimulated) _SimulationPanel(runtime: runtime),

                const SectionHeader('Modo de funcionamiento'),
                BalizaCard(
                  padding: const EdgeInsets.all(Space.lg),
                  child: SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: settings.simulation,
                    onChanged: (v) async {
                      await settings.setSimulation(v);
                      if (context.mounted) _showRestartNotice(context);
                    },
                    secondary: const Icon(Icons.science_outlined),
                    title: Text('Modo simulación', style: BalizaText.body),
                    subtitle: Text(
                      'Genera señales de prueba sin usar el Bluetooth. '
                      'Sirve para conocer la app antes de necesitarla.',
                      style: BalizaText.caption,
                    ),
                  ),
                ),
                const SizedBox(height: Space.xl),

                const _AboutPanel(),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showRestartNotice(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Cierra y abre la app para aplicar el cambio de modo.'),
        duration: Duration(seconds: 4),
      ),
    );
  }
}

/// Controles del modo simulación.
class _SimulationPanel extends StatelessWidget {
  const _SimulationPanel({required this.runtime});

  final BalizaRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader('Escenarios de simulación'),
        BalizaCard(
          color: BalizaColors.infoSoft,
          borderColor: BalizaColors.info.withValues(alpha: 0.3),
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Carga un escenario y ve a la pestaña Buscar.',
                style: BalizaText.caption,
              ),
              const SizedBox(height: Space.md),
              ...SimulationScenario.all.map(
                (s) => Padding(
                  padding: const EdgeInsets.only(bottom: Space.sm),
                  child: OutlinedButton(
                    onPressed: () {
                      runtime.loadScenario(s);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Escenario: ${s.name}')),
                      );
                    },
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Text(s.name, style: BalizaText.body),
                          Text(
                            s.description,
                            style: BalizaText.caption.copyWith(fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const Divider(height: Space.xl),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: BalizaColors.warning,
                  foregroundColor: BalizaColors.base,
                ),
                onPressed: () {
                  runtime.simulatedSensors?.injectQuake();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'Sismo simulado. Ve a la pestaña Auxilio.',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.bolt),
                label: const Text('Simular sismo'),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Dispara el ciclo completo: detección, pregunta "¿estás bien?" '
                'y emisión automática si no respondes.',
                style: BalizaText.caption,
              ),
            ],
          ),
        ),
        const SizedBox(height: Space.xl),
      ],
    );
  }
}

class _AboutPanel extends StatelessWidget {
  const _AboutPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        const SectionHeader('Acerca de'),
        BalizaCard(
          padding: const EdgeInsets.all(Space.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text('Baliza', style: BalizaText.bodyStrong),
              const SizedBox(height: Space.xs),
              Text(
                'Señalización de auxilio sin red, por Bluetooth de baja '
                'energía. Funciona sin internet, sin cobertura celular y sin '
                'GPS.',
                style: BalizaText.caption,
              ),
              const SizedBox(height: Space.lg),
              const InlineNotice(
                message: 'Baliza no sustituye a la línea de emergencias. '
                    'Si tienes cobertura, llama al 123.',
                icon: Icons.phone_in_talk_outlined,
                color: BalizaColors.info,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
