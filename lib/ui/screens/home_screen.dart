import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/detection_controller.dart';
import '../../application/sos_controller.dart';
import '../../domain/ports/beacon_transport.dart';
import '../../domain/value_objects/enums.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/sos_button.dart';
import 'medical_profile_screen.dart';

/// Pantalla principal: pedir ayuda.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Refresca el cronómetro de emisión una vez por segundo.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        runtime.sos,
        runtime.detection,
        runtime.settings,
      ]),
      builder: (context, _) {
        final sos = runtime.sos;
        final detection = runtime.detection;
        final transmitting = sos.isTransmitting;

        return Scaffold(
          body: SafeArea(
            child: CustomScrollView(
              slivers: <Widget>[
                SliverToBoxAdapter(child: _Header(transmitting: transmitting)),

                // La cuenta atrás desplaza todo lo demás: cuando aparece, es lo
                // único que importa.
                if (detection.isAwaitingResponse)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Space.xl,
                        0,
                        Space.xl,
                        Space.lg,
                      ),
                      child: _CountdownCard(detection: detection),
                    ),
                  ),

                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Space.xl),
                    child: Column(
                      children: <Widget>[
                        const SizedBox(height: Space.sm),
                        _StateSummary(sos: sos),

                        // El espacio libre se reparte 3:2 en lugar de empujar
                        // el botón contra el borde inferior.
                        //
                        // El botón debe quedar en la mitad baja, que es donde
                        // alcanza el pulgar con una sola mano; pero con un
                        // único separador arriba se iba al extremo y dejaba un
                        // vacío enorme bajo la cabecera. Repartido queda
                        // centrado en su zona y la pantalla se lee equilibrada.
                        const Spacer(flex: 3),

                        SosButton(
                          active: transmitting,
                          enabled: sos.radioState != RadioState.unsupported,
                          onActivate: () => unawaited(sos.startSos()),
                          onDeactivate: () => unawaited(sos.stopSos()),
                        ),

                        const Spacer(flex: 2),

                        _SecondaryActions(sos: sos),
                        const SizedBox(height: Space.lg),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.transmitting});

  final bool transmitting;

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  transmitting ? 'Pidiendo ayuda' : 'Baliza',
                  style: BalizaText.display.copyWith(
                    color: transmitting
                        ? BalizaColors.danger
                        : BalizaColors.textPrimary,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  transmitting
                      ? 'Tu señal está saliendo. No apagues el teléfono.'
                      : 'Tu señal de vida cuando no hay red',
                  style: BalizaText.caption,
                ),
              ],
            ),
          ),
          if (runtime.isSimulated)
            const StatusChip(
              label: 'SIMULACIÓN',
              color: BalizaColors.info,
              icon: Icons.science_outlined,
            ),
        ],
      ),
    );
  }
}

/// Resumen del estado de emisión.
class _StateSummary extends StatelessWidget {
  const _StateSummary({required this.sos});

  final SosController sos;

  static String _formatElapsed(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);
    final settings = runtime.settings;

    if (!sos.isTransmitting) {
      return Column(
        children: <Widget>[
          if (sos.radioState == RadioState.off)
            const InlineNotice(
              message: 'El Bluetooth está apagado. Sin él no se puede emitir '
                  'ni detectar a nadie.',
              icon: Icons.bluetooth_disabled,
            )
          else if (sos.radioState == RadioState.unsupported)
            const InlineNotice(
              message: 'Este dispositivo no permite emitir por Bluetooth. '
                  'Puedes usar el modo Buscar para ayudar a otras personas.',
              icon: Icons.error_outline,
              color: BalizaColors.danger,
            ),
          if (!settings.profile.isPresent) ...<Widget>[
            const SizedBox(height: Space.md),
            InlineNotice(
              message: 'No has llenado tu ficha médica. Sin ella, quien te '
                  'encuentre no sabrá tu grupo sanguíneo ni tus alergias.',
              icon: Icons.medical_information_outlined,
              actionLabel: 'Llenarla ahora',
              onAction: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const MedicalProfileScreen(),
                ),
              ),
            ),
          ],
        ],
      );
    }

    final signal = sos.signal;

    return BalizaCard(
      color: BalizaColors.dangerSoft,
      borderColor: BalizaColors.dangerBorder,
      child: Column(
        children: <Widget>[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'EMITIENDO DESDE HACE',
                    style: BalizaText.caption.copyWith(
                      color: BalizaColors.textTertiary,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    _formatElapsed(sos.elapsed),
                    style: BalizaText.numeric.copyWith(
                      color: BalizaColors.danger,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    'TU CÓDIGO',
                    style: BalizaText.caption.copyWith(
                      color: BalizaColors.textTertiary,
                      fontSize: 11,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(sos.shortCode, style: BalizaText.numericSmall),
                  const SizedBox(height: Space.xs),
                  Text(
                    'dilo en voz alta',
                    style: BalizaText.caption.copyWith(fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          const Divider(),
          const SizedBox(height: Space.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: DataPoint(
                  label: 'Batería',
                  value: signal?.batteryPercent == null
                      ? '—'
                      : '${signal!.batteryPercent}%',
                  icon: Icons.battery_std_outlined,
                  valueColor: (signal?.batteryPercent ?? 100) <= 15
                      ? BalizaColors.warning
                      : null,
                ),
              ),
              Expanded(
                child: DataPoint(
                  label: 'Contigo',
                  value: '${settings.peopleCount}',
                  icon: Icons.groups_outlined,
                ),
              ),
              Expanded(
                child: DataPoint(
                  label: 'Ficha',
                  value: settings.profile.isPresent ? 'Enviada' : 'Vacía',
                  icon: Icons.medical_information_outlined,
                  valueColor: settings.profile.isPresent
                      ? BalizaColors.safe
                      : BalizaColors.warning,
                ),
              ),
            ],
          ),
          if (signal != null && signal.hasFlag(SignalFlag.autoDetected)) ...[
            const SizedBox(height: Space.lg),
            const StatusChip(
              label: 'Activada automáticamente por sismo',
              color: BalizaColors.warning,
              icon: Icons.auto_awesome_motion,
            ),
          ],
          if (sos.keepAliveFailed) ...<Widget>[
            const SizedBox(height: Space.lg),
            const InlineNotice(
              message: 'No se pudo asegurar la emisión en segundo plano. '
                  'Mantén la pantalla encendida: si se apaga, el sistema '
                  'puede detener la señal en pocos minutos.',
              icon: Icons.screen_lock_portrait,
              color: BalizaColors.danger,
            ),
          ],
          if (sos.degradations.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.lg),
            InlineNotice(
              message: '${sos.degradations.join(', ')}. '
                  'La señal de radio sigue saliendo.',
              icon: Icons.warning_amber_rounded,
            ),
          ],
        ],
      ),
    );
  }
}

/// Cuenta atrás de "¿estás bien?".
class _CountdownCard extends StatelessWidget {
  const _CountdownCard({required this.detection});

  final DetectionController detection;

  @override
  Widget build(BuildContext context) {
    final remaining = detection.remaining ?? Duration.zero;
    final seconds = remaining.inSeconds;

    return BalizaCard(
      color: BalizaColors.warningSoft,
      borderColor: BalizaColors.warning.withValues(alpha: 0.4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Icon(
                Icons.crisis_alert,
                color: BalizaColors.warning,
                size: 26,
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Text('Detectamos un sismo', style: BalizaText.title),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          Text(
            'Si no respondes, emitiremos una señal de auxilio '
            'automáticamente.',
            style: BalizaText.body.copyWith(color: BalizaColors.textSecondary),
          ),
          const SizedBox(height: Space.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Text(
                '$seconds s',
                style: BalizaText.numeric.copyWith(
                  color: BalizaColors.warning,
                ),
              ),
              const SizedBox(width: Space.lg),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(Radii.pill),
                  child: LinearProgressIndicator(
                    value: 1 - detection.countdownProgress,
                    minHeight: 8,
                    backgroundColor: BalizaColors.surfaceHighest,
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      BalizaColors.warning,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.xl),
          Row(
            children: <Widget>[
              Expanded(
                child: OutlinedButton(
                  onPressed: () => unawaited(detection.reportOkay()),
                  child: const Text('Estoy bien'),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: BalizaColors.danger,
                    foregroundColor: BalizaColors.textPrimary,
                  ),
                  onPressed: () => unawaited(detection.reportNeedHelp()),
                  child: const Text('Necesito ayuda'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Acciones secundarias bajo el botón principal.
class _SecondaryActions extends StatelessWidget {
  const _SecondaryActions({required this.sos});

  final SosController sos;

  @override
  Widget build(BuildContext context) {
    if (sos.isTransmitting) {
      return Text(
        'Mantén el teléfono lo más destapado posible. '
        'El Bluetooth no atraviesa bien el metal ni el agua.',
        style: BalizaText.caption,
        textAlign: TextAlign.center,
      );
    }

    return Row(
      children: <Widget>[
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => unawaited(sos.broadcastSafe()),
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: const Text('Estoy a salvo'),
          ),
        ),
        const SizedBox(width: Space.md),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const MedicalProfileScreen(),
              ),
            ),
            icon: const Icon(Icons.medical_information_outlined, size: 20),
            label: const Text('Mi ficha'),
          ),
        ),
      ],
    );
  }
}
