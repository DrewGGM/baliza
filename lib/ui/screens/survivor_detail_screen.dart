import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/entities/survivor.dart';
import '../../domain/services/distance_estimator.dart';
import '../../domain/value_objects/enums.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'rescue_screen.dart';

/// Detalle de una baliza: todo lo que se sabe de esa persona y hacia dónde ir.
class SurvivorDetailScreen extends StatelessWidget {
  const SurvivorDetailScreen({required this.beaconId, super.key});

  final int beaconId;

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);

    return AnimatedBuilder(
      animation: runtime.rescue,
      builder: (context, _) {
        final survivor = runtime.rescue.registry[beaconId];

        if (survivor == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('Baliza')),
            body: const EmptyState(
              icon: Icons.signal_cellular_nodata,
              title: 'Baliza retirada',
              message: 'Esta señal ya no está en la lista.',
            ),
          );
        }

        final estimator = runtime.rescue.ranker.estimator;
        final estimate = survivor.distance(estimator);
        final now = runtime.rescue.now;
        final color = SurvivorCard.bandColor(estimate.band);

        return Scaffold(
          appBar: AppBar(
            title: Text('Baliza ${survivor.shortCode}'),
            actions: <Widget>[
              IconButton(
                tooltip: 'Copiar código',
                icon: const Icon(Icons.copy_all_outlined),
                onPressed: () {
                  Clipboard.setData(
                    ClipboardData(text: survivor.shortCode),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Código ${survivor.shortCode} copiado'),
                    ),
                  );
                },
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.lg,
              Space.xl,
              Space.xxxl,
            ),
            children: <Widget>[
              _ProximityPanel(
                survivor: survivor,
                estimate: estimate,
                color: color,
                stale: survivor.isStale(now),
              ),
              const SizedBox(height: Space.xl),
              const SectionHeader('Ficha médica'),
              _MedicalPanel(survivor: survivor),
              const SizedBox(height: Space.xl),
              const SectionHeader('Situación'),
              _SituationPanel(survivor: survivor, now: now),
              const SizedBox(height: Space.xl),
              const SectionHeader('Calidad de la señal'),
              _SignalPanel(survivor: survivor, estimate: estimate),
              const SizedBox(height: Space.xxl),
              OutlinedButton.icon(
                onPressed: () {
                  runtime.rescue.markAsAttended(survivor.beaconId);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.task_alt),
                label: const Text('Marcar como atendida'),
              ),
              const SizedBox(height: Space.sm),
              Text(
                'Retirarla sólo la quita de tu lista. Si la baliza sigue '
                'emitiendo, volverá a aparecer.',
                style: BalizaText.caption,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Panel principal: la banda de cercanía y la tendencia.
///
/// Es lo primero y lo más grande porque responde a la única pregunta que el
/// rescatista se hace mientras camina: ¿voy bien?
class _ProximityPanel extends StatelessWidget {
  const _ProximityPanel({
    required this.survivor,
    required this.estimate,
    required this.color,
    required this.stale,
  });

  final Survivor survivor;
  final DistanceEstimate estimate;
  final Color color;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final trend = survivor.trend;

    return BalizaCard(
      color: color.withValues(alpha: 0.08),
      borderColor: color.withValues(alpha: 0.3),
      child: Column(
        children: <Widget>[
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              PulseRings(size: 190, color: color, active: !stale),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    estimate.band.label.toUpperCase(),
                    style: BalizaText.numericSmall.copyWith(
                      color: color,
                      letterSpacing: 1.4,
                    ),
                  ),
                  const SizedBox(height: Space.xs),
                  Text(
                    estimate.band.description,
                    style: BalizaText.caption,
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: Space.md),
            decoration: BoxDecoration(
              color: BalizaColors.base.withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(Radii.md),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(SurvivorCard.trendIcon(trend), color: color, size: 22),
                const SizedBox(width: Space.sm),
                Text(
                  trend.label,
                  style: BalizaText.bodyStrong.copyWith(color: color),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          Text(
            stale
                ? 'Esta baliza dejó de emitir. Busca en el último punto donde '
                    'la señal era más fuerte.'
                : 'Camina despacio y observa si la señal mejora. '
                    'Si empeora, vuelve y prueba otra dirección.',
            style: BalizaText.caption,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _MedicalPanel extends StatelessWidget {
  const _MedicalPanel({required this.survivor});

  final Survivor survivor;

  @override
  Widget build(BuildContext context) {
    final profile = survivor.signal.medicalProfile;

    if (!profile.isPresent) {
      return BalizaCard(
        child: Row(
          children: <Widget>[
            const Icon(
              Icons.help_outline,
              color: BalizaColors.textTertiary,
              size: 22,
            ),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                'Esta persona no compartió ficha médica.',
                style: BalizaText.body.copyWith(
                  color: BalizaColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return BalizaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DataPoint(
                  label: 'Grupo sanguíneo',
                  value: profile.bloodType.label,
                  icon: Icons.water_drop_outlined,
                  valueColor: profile.bloodType == BloodType.unknown
                      ? BalizaColors.textTertiary
                      : BalizaColors.danger,
                ),
              ),
              Expanded(
                child: DataPoint(
                  label: 'Edad',
                  value: profile.ageBand.label,
                  icon: Icons.cake_outlined,
                ),
              ),
            ],
          ),
          if (profile.conditions.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.lg),
            Text(
              'CONDICIONES',
              style: BalizaText.caption.copyWith(
                color: BalizaColors.textTertiary,
                fontSize: 11,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: profile.conditions
                  .map(
                    (c) => StatusChip(
                      label: c.label,
                      color: c.isCritical
                          ? BalizaColors.danger
                          : BalizaColors.textSecondary,
                    ),
                  )
                  .toList(),
            ),
          ],
          if (profile.allergies.isNotEmpty) ...<Widget>[
            const SizedBox(height: Space.lg),
            Text(
              'ALERGIAS — NO ADMINISTRAR',
              style: BalizaText.caption.copyWith(
                color: BalizaColors.danger,
                fontSize: 11,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: Space.sm),
            Wrap(
              spacing: Space.sm,
              runSpacing: Space.sm,
              children: profile.allergies
                  .map(
                    (a) => StatusChip(
                      label: a.label,
                      color: BalizaColors.danger,
                      icon: Icons.block,
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _SituationPanel extends StatelessWidget {
  const _SituationPanel({required this.survivor, required this.now});

  final Survivor survivor;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final signal = survivor.signal;

    return BalizaCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DataPoint(
                  label: 'Personas',
                  value: '${signal.peopleCount}',
                  icon: Icons.groups_outlined,
                ),
              ),
              Expanded(
                child: DataPoint(
                  label: 'Pidiendo ayuda',
                  value: signal.elapsedMinutes >= 60
                      ? '${signal.elapsedMinutes ~/ 60} h '
                          '${signal.elapsedMinutes % 60} min'
                      : '${signal.elapsedMinutes} min',
                  icon: Icons.schedule,
                ),
              ),
              Expanded(
                child: DataPoint(
                  label: 'Batería',
                  value: signal.batteryPercent == null
                      ? '—'
                      : '${signal.batteryPercent}%',
                  icon: Icons.battery_std_outlined,
                  valueColor: signal.hasLowBattery
                      ? BalizaColors.warning
                      : null,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: <Widget>[
              StatusChip(
                label: signal.isAutoDetected
                    ? 'Activada por sismo'
                    : 'Activada por la persona',
                color: signal.isAutoDetected
                    ? BalizaColors.warning
                    : BalizaColors.safe,
                icon: signal.isAutoDetected
                    ? Icons.auto_awesome_motion
                    : Icons.touch_app_outlined,
              ),
              if (signal.hasFlag(SignalFlag.trapped))
                const StatusChip(
                  label: 'Declara estar atrapada',
                  color: BalizaColors.danger,
                  icon: Icons.compress,
                ),
              if (signal.hasFlag(SignalFlag.mobilityImpaired))
                const StatusChip(
                  label: 'Movilidad reducida',
                  color: BalizaColors.warning,
                  icon: Icons.accessible,
                ),
              if (signal.hasFlag(SignalFlag.minorsPresent))
                const StatusChip(
                  label: 'Hay menores',
                  color: BalizaColors.warning,
                  icon: Icons.child_care,
                ),
            ],
          ),
          if (signal.isAutoDetected) ...<Widget>[
            const SizedBox(height: Space.lg),
            const InlineNotice(
              message: 'La baliza se activó sola porque la persona no '
                  'respondió al aviso. Puede estar inconsciente.',
              icon: Icons.priority_high,
              color: BalizaColors.danger,
            ),
          ],
        ],
      ),
    );
  }
}

/// Transparencia sobre la calidad de la medición.
///
/// Se muestra a propósito: un rescatista que sabe que la estimación es débil
/// confía menos en ella y busca con más criterio propio. Ocultar la
/// incertidumbre sería más bonito y mucho más peligroso.
class _SignalPanel extends StatelessWidget {
  const _SignalPanel({required this.survivor, required this.estimate});

  final Survivor survivor;
  final DistanceEstimate estimate;

  @override
  Widget build(BuildContext context) {
    final confidence = (estimate.confidence * 100).round();

    return BalizaCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: DataPoint(
                  label: 'Potencia',
                  value: survivor.lastRssi == null
                      ? '—'
                      : '${survivor.lastRssi} dBm',
                  icon: Icons.network_check,
                ),
              ),
              Expanded(
                child: DataPoint(
                  label: 'Muestras',
                  value: '${estimate.sampleCount}',
                  icon: Icons.stacked_line_chart,
                ),
              ),
              Expanded(
                child: DataPoint(
                  label: 'Confianza',
                  value: '$confidence%',
                  icon: Icons.verified_outlined,
                  valueColor: confidence >= 70
                      ? BalizaColors.safe
                      : confidence >= 40
                          ? BalizaColors.warning
                          : BalizaColors.danger,
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.lg),
          Text(
            confidence < 40
                ? 'La señal es inestable. La distancia mostrada puede estar '
                    'muy equivocada; quédate quieto unos segundos para que se '
                    'estabilice.'
                : 'La distancia por Bluetooth es orientativa. Úsala para '
                    'acercarte, no como una medida exacta.',
            style: BalizaText.caption,
          ),
        ],
      ),
    );
  }
}
