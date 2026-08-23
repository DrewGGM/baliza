import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/ports/device_services.dart';
import '../theme/tokens.dart';
import 'common.dart';

/// Ficha de un permiso: qué es, para qué sirve, qué se pierde sin él, y su
/// estado actual.
///
/// ## Explicar antes de pedir
///
/// El diálogo del sistema es una caja negra: dice "¿Permitir que Baliza acceda
/// a dispositivos cercanos?" y nada más. Quien no sabe por qué se lo piden,
/// deniega — y en Android denegar dos veces convierte el permiso en
/// permanentemente denegado, un estado del que ya no se sale sin ir a los
/// ajustes del sistema.
///
/// Por eso cada permiso se pide **de uno en uno**, con su propósito y su
/// consecuencia a la vista, y sólo cuando la persona pulsa "Permitir" en
/// nuestra interfaz aparece el diálogo del sistema.
class PermissionTile extends StatelessWidget {
  const PermissionTile({
    required this.permission,
    required this.state,
    required this.onRequest,
    required this.onOpenSettings,
    this.busy = false,
    super.key,
  });

  final AppPermission permission;
  final PermissionState state;
  final Future<void> Function() onRequest;
  final Future<void> Function() onOpenSettings;
  final bool busy;

  static IconData _iconFor(AppPermission p) => switch (p) {
        AppPermission.bluetooth => Icons.bluetooth,
        AppPermission.location => Icons.my_location,
        AppPermission.notifications => Icons.notifications_active_outlined,
        AppPermission.batteryOptimization => Icons.battery_saver,
      };

  ({Color color, IconData icon, String label}) get _status => switch (state) {
        PermissionState.granted => (
            color: BalizaColors.safe,
            icon: Icons.check_circle,
            label: 'Concedido',
          ),
        PermissionState.denied => (
            color: permission.essential
                ? BalizaColors.warning
                : BalizaColors.textTertiary,
            icon: Icons.radio_button_unchecked,
            label: 'Pendiente',
          ),
        PermissionState.permanentlyDenied => (
            color: BalizaColors.warning,
            icon: Icons.settings,
            label: 'Requiere ajustes',
          ),
        PermissionState.unavailable => (
            color: BalizaColors.textTertiary,
            icon: Icons.remove_circle_outline,
            label: 'No aplica',
          ),
      };

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final satisfied = state.isSatisfied;

    return BalizaCard(
      padding: const EdgeInsets.all(Space.lg),
      borderColor: state == PermissionState.granted
          ? BalizaColors.safe.withValues(alpha: 0.35)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: status.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(Radii.sm),
                ),
                child: Icon(
                  _iconFor(permission),
                  size: 20,
                  color: status.color,
                ),
              ),
              const SizedBox(width: Space.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            permission.label,
                            style: BalizaText.bodyStrong,
                          ),
                        ),
                        if (permission.essential) ...<Widget>[
                          const SizedBox(width: Space.sm),
                          Text(
                            'IMPRESCINDIBLE',
                            style: BalizaText.caption.copyWith(
                              fontSize: 10,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                              color: BalizaColors.amber,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: <Widget>[
                        Icon(status.icon, size: 13, color: status.color),
                        const SizedBox(width: Space.xs),
                        Text(
                          status.label,
                          style: BalizaText.caption.copyWith(
                            color: status.color,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: Space.md),
          Text(permission.purpose, style: BalizaText.caption),

          // La consecuencia sólo se muestra cuando todavía es una consecuencia
          // posible. Repetirla con el permiso ya concedido sería ruido.
          if (!satisfied) ...<Widget>[
            const SizedBox(height: Space.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(
                  Icons.subdirectory_arrow_right,
                  size: 14,
                  color: status.color,
                ),
                const SizedBox(width: Space.xs + 2),
                Expanded(
                  child: Text(
                    permission.ifDenied,
                    style: BalizaText.caption.copyWith(color: status.color),
                  ),
                ),
              ],
            ),
          ],

          if (!satisfied) ...<Widget>[
            const SizedBox(height: Space.md),
            SizedBox(
              width: double.infinity,
              child: state.needsSystemSettings
                  ? OutlinedButton.icon(
                      onPressed: busy ? null : () => unawaited(onOpenSettings()),
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('Abrir ajustes del sistema'),
                    )
                  : FilledButton(
                      onPressed: busy ? null : () => unawaited(onRequest()),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Permitir'),
                    ),
            ),
            if (state.needsSystemSettings) ...<Widget>[
              const SizedBox(height: Space.sm),
              Text(
                'Lo denegaste antes, así que el sistema ya no vuelve a '
                'preguntar. Hay que concederlo a mano.',
                style: BalizaText.caption.copyWith(fontSize: 11),
              ),
            ],
          ],
        ],
      ),
    );
  }
}
