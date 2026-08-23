import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/entities/medical_profile.dart';
import '../../domain/value_objects/enums.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

/// Formulario de ficha médica.
///
/// ## Todo por selección, nada por escrito
///
/// No hay un solo campo de texto libre, y no es por simplificar: el protocolo
/// sólo transporta tres bytes de datos médicos, así que un texto libre no
/// cabría. Pero la restricción resultó acertada también en lo humano — nadie
/// escribe párrafos en un formulario, y menos con el pulso alterado. Tocar
/// opciones es rápido, se puede hacer con una mano y no tiene faltas de
/// ortografía que luego un rescatista tenga que interpretar.
class MedicalProfileScreen extends StatelessWidget {
  const MedicalProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);

    return AnimatedBuilder(
      animation: runtime.settings,
      builder: (context, _) {
        final settings = runtime.settings;
        final profile = settings.profile;

        void update(MedicalProfile next) =>
            unawaited(settings.setProfile(next));

        return Scaffold(
          appBar: AppBar(title: const Text('Mi ficha médica')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              Space.xl,
              Space.lg,
              Space.xl,
              Space.xxxl,
            ),
            children: <Widget>[
              const InlineNotice(
                message: 'Estos datos viajan dentro de tu señal para que quien '
                    'te encuentre sepa cómo atenderte. No incluyen tu nombre '
                    'ni tu documento, y nunca salen de tu teléfono hacia '
                    'ningún servidor.',
                icon: Icons.lock_outline,
                color: BalizaColors.info,
              ),
              const SizedBox(height: Space.xl),

              const SectionHeader('Grupo sanguíneo'),
              _ChoiceGrid<BloodType>(
                values: BloodType.values,
                selected: profile.bloodType,
                labelOf: (v) => v.label,
                onSelect: (v) => update(profile.copyWith(bloodType: v)),
              ),
              const SizedBox(height: Space.xl),

              const SectionHeader('Edad'),
              _ChoiceGrid<AgeBand>(
                values: AgeBand.values,
                selected: profile.ageBand,
                labelOf: (v) => v.label,
                onSelect: (v) => update(profile.copyWith(ageBand: v)),
              ),
              const SizedBox(height: Space.xl),

              const SectionHeader('Condiciones médicas'),
              _MultiChoice<MedicalCondition>(
                values: MedicalCondition.values,
                selected: profile.conditions,
                labelOf: (v) => v.label,
                highlight: (v) => v.isCritical,
                onToggle: (v) {
                  final next = Set<MedicalCondition>.from(profile.conditions);
                  next.contains(v) ? next.remove(v) : next.add(v);
                  update(profile.copyWith(conditions: next));
                },
              ),
              const SizedBox(height: Space.xl),

              const SectionHeader('Alergias'),
              _MultiChoice<Allergy>(
                values: Allergy.values,
                selected: profile.allergies,
                labelOf: (v) => v.label,
                highlight: (_) => true,
                onToggle: (v) {
                  final next = Set<Allergy>.from(profile.allergies);
                  next.contains(v) ? next.remove(v) : next.add(v);
                  update(profile.copyWith(allergies: next));
                },
              ),
              const SizedBox(height: Space.xl),

              const SectionHeader('Personas contigo'),
              _PeopleCounter(
                value: settings.peopleCount,
                onChanged: (v) => unawaited(settings.setPeopleCount(v)),
              ),
              const SizedBox(height: Space.xl),

              _ProfileSummary(profile: profile),
            ],
          ),
        );
      },
    );
  }
}

/// Rejilla de opción única.
class _ChoiceGrid<T> extends StatelessWidget {
  const _ChoiceGrid({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelect,
  });

  final List<T> values;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onSelect;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: values.map((v) {
        final isSelected = v == selected;
        return _Pill(
          label: labelOf(v),
          selected: isSelected,
          onTap: () => onSelect(v),
        );
      }).toList(),
    );
  }
}

/// Rejilla de opción múltiple.
class _MultiChoice<T> extends StatelessWidget {
  const _MultiChoice({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onToggle,
    required this.highlight,
  });

  final List<T> values;
  final Set<T> selected;
  final String Function(T) labelOf;
  final bool Function(T) highlight;
  final ValueChanged<T> onToggle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Space.sm,
      runSpacing: Space.sm,
      children: values.map((v) {
        final isSelected = selected.contains(v);
        return _Pill(
          label: labelOf(v),
          selected: isSelected,
          accent: highlight(v) ? BalizaColors.danger : BalizaColors.amber,
          onTap: () => onToggle(v),
        );
      }).toList(),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.selected,
    required this.onTap,
    this.accent = BalizaColors.amber,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(
            horizontal: Space.lg,
            vertical: Space.md,
          ),
          decoration: BoxDecoration(
            color: selected
                ? accent.withValues(alpha: 0.16)
                : BalizaColors.surface,
            borderRadius: BorderRadius.circular(Radii.md),
            border: Border.all(
              color: selected
                  ? accent.withValues(alpha: 0.5)
                  : BalizaColors.outline,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (selected) ...<Widget>[
                Icon(Icons.check, size: 16, color: accent),
                const SizedBox(width: Space.sm),
              ],
              Text(
                label,
                style: BalizaText.body.copyWith(
                  color: selected ? accent : BalizaColors.textSecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Contador de personas en el mismo punto.
class _PeopleCounter extends StatelessWidget {
  const _PeopleCounter({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return BalizaCard(
      padding: const EdgeInsets.all(Space.lg),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('Cuántas personas hay contigo', style: BalizaText.body),
                const SizedBox(height: Space.xs),
                Text(
                  'Cambia por completo cómo se organiza el rescate.',
                  style: BalizaText.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: Space.md),
          _StepperButton(
            icon: Icons.remove,
            onTap: value > 1 ? () => onChanged(value - 1) : null,
          ),
          SizedBox(
            width: 52,
            child: Text(
              '$value',
              textAlign: TextAlign.center,
              style: BalizaText.numericSmall,
            ),
          ),
          _StepperButton(
            icon: Icons.add,
            onTap: value < 99 ? () => onChanged(value + 1) : null,
          ),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  const _StepperButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: BalizaColors.surfaceHighest,
      borderRadius: BorderRadius.circular(Radii.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: SizedBox(
          width: 48,
          height: 48,
          child: Icon(
            icon,
            color: enabled
                ? BalizaColors.textPrimary
                : BalizaColors.textDisabled,
          ),
        ),
      ),
    );
  }
}

/// Resumen de lo que se va a transmitir.
class _ProfileSummary extends StatelessWidget {
  const _ProfileSummary({required this.profile});

  final MedicalProfile profile;

  @override
  Widget build(BuildContext context) {
    if (!profile.isPresent) {
      return const InlineNotice(
        message: 'Tu ficha está vacía. Puedes emitir igual, pero quien te '
            'encuentre no sabrá nada de ti.',
        icon: Icons.info_outline,
      );
    }

    return BalizaCard(
      color: BalizaColors.safeSoft,
      borderColor: BalizaColors.safe.withValues(alpha: 0.3),
      child: Row(
        children: <Widget>[
          const Icon(Icons.check_circle, color: BalizaColors.safe, size: 24),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Ficha lista',
                  style: BalizaText.bodyStrong.copyWith(
                    color: BalizaColors.safe,
                  ),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'Se guarda sola. Viajará dentro de tu señal cada vez que '
                  'pidas ayuda.',
                  style: BalizaText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
