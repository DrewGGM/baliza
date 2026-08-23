import 'dart:async';

import 'package:flutter/material.dart';

import '../../application/rescue_controller.dart';
import '../../domain/entities/survivor.dart';
import '../../domain/ports/beacon_transport.dart';
import '../../domain/services/distance_estimator.dart';
import '../../domain/services/triage.dart';
import '../../domain/value_objects/enums.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'survivor_detail_screen.dart';

/// Pantalla de rescate: quién pide ayuda alrededor y por dónde empezar.
class RescueScreen extends StatelessWidget {
  const RescueScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);

    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[runtime.rescue, runtime.settings]),
      builder: (context, _) {
        final rescue = runtime.rescue;
        final survivors = rescue.visible;

        return Scaffold(
          body: SafeArea(
            child: Column(
              children: <Widget>[
                _RescueHeader(rescue: rescue),
                if (rescue.isScanning && survivors.isNotEmpty)
                  _StrategySelector(rescue: rescue),
                Expanded(
                  child: !rescue.isScanning
                      ? _IdleState(rescue: rescue)
                      : survivors.isEmpty
                          ? const _SearchingState()
                          : _SurvivorList(rescue: rescue, survivors: survivors),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RescueHeader extends StatelessWidget {
  const _RescueHeader({required this.rescue});

  final RescueController rescue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Buscar', style: BalizaText.display),
                const SizedBox(height: Space.xs),
                Text(
                  rescue.isScanning
                      ? rescue.sosCount == 0
                          ? 'Escuchando. Aún no hay señales.'
                          : rescue.sosCount == 1
                              ? '1 persona pide ayuda'
                              : '${rescue.sosCount} personas piden ayuda'
                      : 'Ayuda a encontrar a quien esté atrapado',
                  style: BalizaText.caption.copyWith(
                    color: rescue.sosCount > 0
                        ? BalizaColors.amber
                        : BalizaColors.textSecondary,
                    fontWeight:
                        rescue.sosCount > 0 ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
          if (rescue.isScanning)
            IconButton(
              onPressed: () => unawaited(rescue.stopScanning()),
              icon: const Icon(Icons.stop_circle_outlined),
              iconSize: 32,
              color: BalizaColors.amber,
              tooltip: 'Detener búsqueda',
            ),
        ],
      ),
    );
  }
}

/// Selector de criterio de orden.
class _StrategySelector extends StatelessWidget {
  const _StrategySelector({required this.rescue});

  final RescueController rescue;

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);
    final current = runtime.settings.strategy;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Space.xl),
        itemCount: TriageStrategy.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: Space.sm),
        itemBuilder: (context, i) {
          final strategy = TriageStrategy.values[i];
          final selected = strategy == current;
          return GestureDetector(
            onTap: () => unawaited(runtime.settings.setStrategy(strategy)),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: Space.lg),
              decoration: BoxDecoration(
                color: selected
                    ? BalizaColors.amberSoft
                    : BalizaColors.surface,
                borderRadius: BorderRadius.circular(Radii.pill),
                border: Border.all(
                  color: selected
                      ? BalizaColors.amberBorder
                      : BalizaColors.outline,
                ),
              ),
              child: Text(
                strategy.label,
                style: BalizaText.caption.copyWith(
                  color: selected
                      ? BalizaColors.amber
                      : BalizaColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _IdleState extends StatelessWidget {
  const _IdleState({required this.rescue});

  final RescueController rescue;

  @override
  Widget build(BuildContext context) {
    if (rescue.radioState == RadioState.off) {
      return const EmptyState(
        icon: Icons.bluetooth_disabled,
        title: 'Bluetooth apagado',
        message: 'Enciéndelo desde los ajustes del teléfono. '
            'Sin Bluetooth no se puede detectar a nadie.',
      );
    }

    return EmptyState(
      icon: Icons.travel_explore,
      title: 'Listo para buscar',
      message: 'Al empezar, el teléfono escuchará las balizas cercanas y te '
          'dirá hacia dónde moverte para acercarte a ellas.',
      action: FilledButton.icon(
        onPressed: () => unawaited(rescue.startScanning()),
        icon: const Icon(Icons.search),
        label: const Text('Empezar búsqueda'),
      ),
    );
  }
}

class _SearchingState extends StatelessWidget {
  const _SearchingState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const PulseRings(size: 180, color: BalizaColors.amber),
          const SizedBox(height: Space.xl),
          Text('Escuchando', style: BalizaText.title),
          const SizedBox(height: Space.sm),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
            child: Text(
              'Camina despacio. El alcance útil es de unos 10 a 30 metros '
              'y baja mucho entre escombros.',
              style: BalizaText.body.copyWith(
                color: BalizaColors.textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _SurvivorList extends StatelessWidget {
  const _SurvivorList({required this.rescue, required this.survivors});

  final RescueController rescue;
  final List<Survivor> survivors;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(Space.xl, Space.lg, Space.xl, Space.xxl),
      itemCount: survivors.length,
      separatorBuilder: (_, _) => const SizedBox(height: Space.md),
      itemBuilder: (context, i) {
        return SurvivorCard(
          survivor: survivors[i],
          rank: i + 1,
          estimator: rescue.ranker.estimator,
          now: rescue.now,
          onTap: () {
            rescue.focus(survivors[i].beaconId);
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SurvivorDetailScreen(beaconId: survivors[i].beaconId),
              ),
            );
          },
        );
      },
    );
  }
}

/// Tarjeta de una persona detectada.
class SurvivorCard extends StatelessWidget {
  const SurvivorCard({
    required this.survivor,
    required this.rank,
    required this.estimator,
    required this.now,
    this.onTap,
    super.key,
  });

  final Survivor survivor;
  final int rank;
  final DistanceEstimator estimator;
  final DateTime now;
  final VoidCallback? onTap;

  static Color bandColor(ProximityBand band) => switch (band) {
        ProximityBand.immediate => BalizaColors.safe,
        ProximityBand.near => BalizaColors.amber,
        ProximityBand.medium => BalizaColors.warning,
        ProximityBand.far => BalizaColors.textTertiary,
        ProximityBand.unknown => BalizaColors.textTertiary,
      };

  static IconData trendIcon(ProximityTrend trend) => switch (trend) {
        ProximityTrend.closer => Icons.trending_up,
        ProximityTrend.farther => Icons.trending_down,
        ProximityTrend.steady => Icons.trending_flat,
        ProximityTrend.unknown => Icons.more_horiz,
      };

  @override
  Widget build(BuildContext context) {
    final estimate = survivor.distance(estimator);
    final trend = survivor.trend;
    final stale = survivor.isStale(now);
    final signal = survivor.signal;
    final color = bandColor(estimate.band);

    return BalizaCard(
      onTap: onTap,
      color: stale ? BalizaColors.surface : BalizaColors.surfaceHigh,
      borderColor: stale ? BalizaColors.outline : color.withValues(alpha: 0.3),
      padding: const EdgeInsets.all(Space.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              // Indicador de orden: qué tan arriba está en la prioridad.
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(Radii.sm),
                  border: Border.all(color: color.withValues(alpha: 0.3)),
                ),
                child: Text(
                  '$rank',
                  style: BalizaText.bodyStrong.copyWith(color: color),
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Text(
                          survivor.shortCode,
                          style: BalizaText.bodyStrong.copyWith(
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(width: Space.sm),
                        if (signal.isResponder)
                          const StatusChip(
                            label: 'Rescate',
                            color: BalizaColors.info,
                            icon: Icons.shield_outlined,
                          )
                        else if (signal.isSafe)
                          const StatusChip(
                            label: 'A salvo',
                            color: BalizaColors.safe,
                            icon: Icons.check,
                          ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      stale
                          ? 'Sin señal desde hace '
                              '${_ago(survivor.silenceFor(now))}'
                          : '${estimate.band.description} · ${trend.label}',
                      style: BalizaText.caption.copyWith(
                        color: stale ? BalizaColors.warning : color,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(trendIcon(trend), color: color, size: 26),
            ],
          ),
          const SizedBox(height: Space.md),
          Wrap(
            spacing: Space.sm,
            runSpacing: Space.sm,
            children: <Widget>[
              if (signal.peopleCount > 1)
                StatusChip(
                  label: '${signal.peopleCount} personas',
                  color: BalizaColors.info,
                  icon: Icons.groups,
                ),
              if (signal.hasFlag(SignalFlag.trapped))
                const StatusChip(
                  label: 'Atrapada',
                  color: BalizaColors.danger,
                  icon: Icons.compress,
                ),
              if (signal.medicalProfile.criticalConditions.isNotEmpty)
                StatusChip(
                  label: signal.medicalProfile.criticalConditions
                      .map((c) => c.label)
                      .join(', '),
                  color: BalizaColors.danger,
                  icon: Icons.favorite_outline,
                ),
              if (signal.medicalProfile.bloodType != BloodType.unknown)
                StatusChip(
                  label: signal.medicalProfile.bloodType.label,
                  color: BalizaColors.textSecondary,
                  icon: Icons.water_drop_outlined,
                ),
              if (signal.hasFlag(SignalFlag.minorsPresent))
                const StatusChip(
                  label: 'Menores',
                  color: BalizaColors.warning,
                  icon: Icons.child_care,
                ),
              if (signal.hasLowBattery)
                StatusChip(
                  label: 'Batería ${signal.batteryPercent ?? 0}%',
                  color: BalizaColors.warning,
                  icon: Icons.battery_alert,
                ),
              if (signal.elapsedMinutes > 0)
                StatusChip(
                  label: 'Espera ${_minutes(signal.elapsedMinutes)}',
                  color: BalizaColors.textSecondary,
                  icon: Icons.schedule,
                ),
            ],
          ),
        ],
      ),
    );
  }

  static String _minutes(int minutes) {
    if (minutes < 60) return '${minutes}m';
    final h = minutes ~/ 60;
    final m = minutes % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}m';
  }

  static String _ago(Duration d) {
    if (d.inMinutes < 1) return '${d.inSeconds}s';
    if (d.inHours < 1) return '${d.inMinutes}m';
    return '${d.inHours}h';
  }
}
