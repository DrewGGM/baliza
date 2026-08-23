import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/tokens.dart';
import 'common.dart';

/// Botón principal de auxilio.
///
/// ## Por qué activar es un toque y desactivar exige mantener pulsado
///
/// Activar tiene que ser lo más fácil que hay en la app: un solo toque, sin
/// confirmación, sobre el objetivo más grande de la pantalla. Un diálogo de
/// "¿estás seguro?" antes de pedir auxilio es una barrera puesta exactamente
/// en el peor momento.
///
/// Desactivar es lo contrario. Un roce accidental —el teléfono en el bolsillo,
/// una mano temblando, un objeto encima— no puede apagar la única señal que
/// alguien tiene. Por eso apagar exige mantener pulsado dos segundos, con
/// realimentación visual del progreso.
class SosButton extends StatefulWidget {
  const SosButton({
    required this.active,
    required this.onActivate,
    required this.onDeactivate,
    this.enabled = true,
    super.key,
  });

  final bool active;
  final VoidCallback onActivate;
  final VoidCallback onDeactivate;
  final bool enabled;

  /// Cuánto hay que mantener pulsado para detener la emisión.
  static const holdToStop = Duration(milliseconds: 2000);

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(
    vsync: this,
    duration: SosButton.holdToStop,
  )..addStatusListener(_onHoldStatus);

  bool _pressed = false;

  /// Suprime el `onTap` que el sistema entrega al soltar tras completar la
  /// pulsación sostenida.
  ///
  /// Sin esto aparece un fallo grave: al mantener pulsado se detiene la
  /// emisión, pero al levantar el dedo `onTap` llega igual y para entonces el
  /// botón ya está inactivo, de modo que se interpreta como una activación
  /// nueva. El resultado es que detener **reinicia** la baliza con otro
  /// identificador y el cronómetro a cero, justo lo contrario de lo que la
  /// persona pidió.
  bool _suppressNextTap = false;

  void _onHoldStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) {
      HapticFeedback.heavyImpact();
      _suppressNextTap = true;
      widget.onDeactivate();
      _hold.reset();
      setState(() => _pressed = false);
    }
  }

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  void _handleTap() {
    if (_suppressNextTap) {
      _suppressNextTap = false;
      return;
    }
    if (!widget.enabled || widget.active) return;
    HapticFeedback.heavyImpact();
    widget.onActivate();
  }

  void _handleDown() {
    if (!widget.active) {
      setState(() => _pressed = true);
      return;
    }
    setState(() => _pressed = true);
    _hold.forward();
  }

  void _handleUp() {
    if (widget.active) _hold.reverse();
    setState(() => _pressed = false);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.active;
    final accent = active ? BalizaColors.danger : BalizaColors.amber;
    const size = Touch.sosButton;

    return Semantics(
      button: true,
      label: active
          ? 'Emitiendo auxilio. Mantén pulsado dos segundos para detener.'
          : 'Pedir auxilio',
      child: GestureDetector(
        onTap: _handleTap,
        onTapDown: (_) => _handleDown(),
        onTapUp: (_) => _handleUp(),
        onTapCancel: _handleUp,
        child: SizedBox(
          width: size + 96,
          height: size + 96,
          child: Stack(
            alignment: Alignment.center,
            children: <Widget>[
              // Ondas: sólo mientras se emite de verdad.
              PulseRings(
                size: size + 96,
                color: accent,
                active: active,
              ),

              // Resplandor difuso bajo el botón.
              AnimatedContainer(
                duration: Motion.normal,
                width: size + (active ? 40 : 16),
                height: size + (active ? 40 : 16),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withValues(alpha: active ? 0.34 : 0.16),
                      blurRadius: active ? 64 : 36,
                      spreadRadius: active ? 8 : 2,
                    ),
                  ],
                ),
              ),

              // Aro de progreso al mantener pulsado para detener.
              if (active)
                AnimatedBuilder(
                  animation: _hold,
                  builder: (context, _) {
                    if (_hold.value == 0) return const SizedBox.shrink();
                    return SizedBox(
                      width: size + 22,
                      height: size + 22,
                      child: CircularProgressIndicator(
                        value: _hold.value,
                        strokeWidth: 6,
                        backgroundColor: Colors.transparent,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          BalizaColors.textPrimary,
                        ),
                      ),
                    );
                  },
                ),

              // Cuerpo del botón.
              AnimatedScale(
                scale: _pressed ? 0.95 : 1,
                duration: Motion.fast,
                child: Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color.lerp(accent, Colors.white, 0.18)!,
                        accent,
                        Color.lerp(accent, Colors.black, 0.22)!,
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.22),
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Icon(
                        active ? Icons.podcasts : Icons.sos_rounded,
                        size: active ? 60 : 68,
                        color: BalizaColors.base,
                      ),
                      const SizedBox(height: Space.sm),
                      Text(
                        active ? 'EMITIENDO' : 'PEDIR AYUDA',
                        style: BalizaText.captionStrong.copyWith(
                          color: BalizaColors.base,
                          letterSpacing: 1.6,
                        ),
                      ),
                      if (active) ...<Widget>[
                        const SizedBox(height: Space.xs),
                        Text(
                          'mantén para detener',
                          style: BalizaText.caption.copyWith(
                            color: BalizaColors.base.withValues(alpha: 0.62),
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
