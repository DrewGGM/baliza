import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/ports/device_services.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import '../widgets/permission_tile.dart';

/// Pantalla de permisos, reutilizada por la bienvenida y por los ajustes.
///
/// Se revisa el estado cada vez que la app vuelve a primer plano: si la
/// persona sale a los ajustes del sistema a conceder algo, al regresar debe
/// encontrarlo ya reflejado y no un estado obsoleto que la haga dudar.
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({this.embedded = false, super.key});

  /// `true` cuando se muestra dentro de la bienvenida, sin barra propia.
  final bool embedded;

  @override
  State<PermissionsScreen> createState() => PermissionsScreenState();
}

class PermissionsScreenState extends State<PermissionsScreen>
    with WidgetsBindingObserver {
  Map<AppPermission, PermissionState> _states = <AppPermission, PermissionState>{
    for (final p in AppPermission.values) p: PermissionState.denied,
  };

  AppPermission? _busy;
  bool _loading = true;
  bool _firstLoadDone = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // La primera carga va aquí y no en initState: `RuntimeScope.of` registra
    // una dependencia de InheritedWidget, y hacerlo en initState lanza una
    // excepción. Como la llamada iba sin await, esa excepción se tragaba en
    // silencio y la pantalla se quedaba girando para siempre.
    if (_firstLoadDone) return;
    _firstLoadDone = true;
    unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  Future<void> refresh() async {
    try {
      final service = RuntimeScope.of(context).permissions;
      final states = await service.checkAll();
      if (!mounted) return;
      setState(() {
        _states = states;
        _loading = false;
      });
    } catch (e) {
      // Pase lo que pase, la pantalla debe dejar de cargar. Un indicador que
      // gira sin fin no comunica nada y no da salida.
      debugPrint('[PermissionsScreen] no se pudo leer el estado: $e');
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _request(AppPermission permission) async {
    setState(() => _busy = permission);
    final runtime = RuntimeScope.of(context);

    // La exención de batería no pasa por `permission_handler`: la gestiona el
    // propio servicio en primer plano, que sabe abrir el diálogo correcto.
    if (permission == AppPermission.batteryOptimization) {
      await runtime.keepAlive.requestPermissions();
    } else {
      await runtime.permissions.request(permission);
    }

    if (!mounted) return;
    setState(() => _busy = null);
    await refresh();
  }

  Future<void> _openSettings() async {
    await RuntimeScope.of(context).permissions.openSystemSettings();
  }

  /// `true` si todos los permisos imprescindibles están resueltos.
  bool get allEssentialGranted => AppPermission.values
      .where((p) => p.essential)
      .every((p) => _states[p]?.isSatisfied ?? false);

  int get pendingCount =>
      _states.values.where((s) => !s.isSatisfied).length;

  @override
  Widget build(BuildContext context) {
    final body = _loading
        ? const Center(child: CircularProgressIndicator())
        : ListView(
            padding: EdgeInsets.fromLTRB(
              Space.xl,
              widget.embedded ? Space.md : Space.lg,
              Space.xl,
              Space.xxxl,
            ),
            children: <Widget>[
              if (widget.embedded) ...<Widget>[
                Text('Permisos', style: BalizaText.display),
                const SizedBox(height: Space.sm),
                Text(
                  'Concede cada uno cuando entiendas para qué sirve. Puedes '
                  'cambiarlos después desde Ajustes.',
                  style: BalizaText.body.copyWith(
                    color: BalizaColors.textSecondary,
                  ),
                ),
                const SizedBox(height: Space.xl),
              ],

              if (allEssentialGranted && pendingCount == 0)
                const InlineNotice(
                  message: 'Todo listo. Baliza puede emitir y buscar sin '
                      'limitaciones.',
                  icon: Icons.verified,
                  color: BalizaColors.safe,
                )
              else if (!allEssentialGranted)
                const InlineNotice(
                  message: 'Falta algún permiso imprescindible. Sin ellos la '
                      'app no puede emitir tu señal ni detectar a nadie.',
                  icon: Icons.priority_high,
                ),

              const SizedBox(height: Space.lg),

              ...AppPermission.values.map((p) {
                final state = _states[p] ?? PermissionState.denied;
                return Padding(
                  padding: const EdgeInsets.only(bottom: Space.md),
                  child: PermissionTile(
                    permission: p,
                    state: state,
                    busy: _busy == p,
                    onRequest: () => _request(p),
                    onOpenSettings: _openSettings,
                  ),
                );
              }),

              const SizedBox(height: Space.lg),
              BalizaCard(
                color: BalizaColors.infoSoft,
                borderColor: BalizaColors.info.withValues(alpha: 0.3),
                padding: const EdgeInsets.all(Space.lg),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    const Icon(
                      Icons.lock_outline,
                      size: 20,
                      color: BalizaColors.info,
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Text(
                        'Baliza no pide permiso de cámara, ni de micrófono, ni '
                        'de contactos, ni de almacenamiento. No tiene servidor '
                        'ni cuenta: nada de lo que guardas sale del teléfono.',
                        style: BalizaText.caption,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(title: const Text('Permisos')),
      body: body,
    );
  }
}
