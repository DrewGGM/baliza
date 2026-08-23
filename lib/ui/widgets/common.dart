import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// Tarjeta base de la app.
class BalizaCard extends StatelessWidget {
  const BalizaCard({
    required this.child,
    this.padding = const EdgeInsets.all(Space.xl),
    this.color,
    this.borderColor,
    this.onTap,
    super.key,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? BalizaColors.surface,
        borderRadius: BorderRadius.circular(Radii.lg),
        border: Border.all(color: borderColor ?? BalizaColors.outline),
      ),
      child: child,
    );

    if (onTap == null) return content;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.lg),
        child: content,
      ),
    );
  }
}

/// Etiqueta compacta de estado.
class StatusChip extends StatelessWidget {
  const StatusChip({
    required this.label,
    required this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.md,
        vertical: Space.xs + 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Radii.pill),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (icon != null) ...<Widget>[
            Icon(icon, size: 14, color: color),
            const SizedBox(width: Space.xs + 2),
          ],
          Text(
            label,
            style: BalizaText.caption.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Encabezado de sección.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.title, {this.trailing, super.key});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: BalizaText.captionStrong.copyWith(
                color: BalizaColors.textTertiary,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// Estado vacío con guía, no un simple "no hay nada".
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    this.action,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: BalizaColors.surface,
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: BalizaColors.textTertiary),
            ),
            const SizedBox(height: Space.xl),
            Text(title, style: BalizaText.title, textAlign: TextAlign.center),
            const SizedBox(height: Space.sm),
            Text(
              message,
              style: BalizaText.body.copyWith(color: BalizaColors.textSecondary),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...<Widget>[
              const SizedBox(height: Space.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// Aviso en línea, para advertencias que no son emergencia.
class InlineNotice extends StatelessWidget {
  const InlineNotice({
    required this.message,
    this.icon = Icons.info_outline,
    this.color = BalizaColors.warning,
    this.onAction,
    this.actionLabel,
    super.key,
  });

  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(Radii.md),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(icon, size: 20, color: color),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  message,
                  style: BalizaText.caption.copyWith(
                    color: BalizaColors.textPrimary,
                  ),
                ),
                if (onAction != null && actionLabel != null) ...<Widget>[
                  const SizedBox(height: Space.sm),
                  GestureDetector(
                    onTap: onAction,
                    child: Text(
                      actionLabel!,
                      style: BalizaText.caption.copyWith(
                        color: color,
                        fontWeight: FontWeight.w700,
                        decoration: TextDecoration.underline,
                        decorationColor: color,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Anillos concéntricos que laten hacia fuera desde el botón de auxilio.
///
/// La animación no es decorativa: es la confirmación continua de que la baliza
/// sigue viva. Alguien atrapado a oscuras mira la pantalla para saber si el
/// teléfono sigue pidiendo ayuda, y un elemento estático no responde a esa
/// pregunta. El ritmo es lento a propósito, cercano a un pulso en reposo.
class PulseRings extends StatefulWidget {
  const PulseRings({
    required this.size,
    required this.color,
    this.active = true,
    this.ringCount = 3,
    super.key,
  });

  final double size;
  final Color color;
  final bool active;
  final int ringCount;

  @override
  State<PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Motion.pulse,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.repeat();
  }

  @override
  void didUpdateWidget(PulseRings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!widget.active && _controller.isAnimating) {
      _controller
        ..stop()
        ..reset();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return SizedBox.square(dimension: widget.size);

    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size.square(widget.size),
            painter: _PulsePainter(
              progress: _controller.value,
              color: widget.color,
              ringCount: widget.ringCount,
            ),
          );
        },
      ),
    );
  }
}

class _PulsePainter extends CustomPainter {
  _PulsePainter({
    required this.progress,
    required this.color,
    required this.ringCount,
  });

  final double progress;
  final Color color;
  final int ringCount;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxRadius = size.width / 2;
    final minRadius = maxRadius * 0.46;

    for (var i = 0; i < ringCount; i++) {
      // Cada anillo va desfasado, de modo que la emisión se ve continua.
      final t = (progress + i / ringCount) % 1.0;
      final radius = minRadius + (maxRadius - minRadius) * t;
      // El anillo se desvanece según se aleja, como una onda real.
      final opacity = (1 - t) * 0.55;
      if (opacity <= 0.01) continue;

      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(1.5, 4 * (1 - t))
          ..color = color.withValues(alpha: opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_PulsePainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}

/// Fila de dato: etiqueta discreta arriba, valor destacado abajo.
///
/// El valor pesa más que la etiqueta a propósito: quien mira quiere el dato,
/// no el nombre del dato.
class DataPoint extends StatelessWidget {
  const DataPoint({
    required this.label,
    required this.value,
    this.valueColor,
    this.icon,
    super.key,
  });

  final String label;
  final String value;
  final Color? valueColor;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label.toUpperCase(),
          style: BalizaText.caption.copyWith(
            color: BalizaColors.textTertiary,
            fontSize: 11,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: Space.xs),
        Row(
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 16, color: valueColor ?? BalizaColors.textPrimary),
              const SizedBox(width: Space.xs + 2),
            ],
            Flexible(
              child: Text(
                value,
                style: BalizaText.bodyStrong.copyWith(color: valueColor),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
