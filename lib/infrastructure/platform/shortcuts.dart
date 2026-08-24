import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Órdenes que pueden llegar desde fuera de la aplicación.
enum ShortcutAction {
  /// Alguien pulsó "Pedir ayuda" en el panel de ajustes rápidos.
  startSos('start_sos');

  const ShortcutAction(this.code);
  final String code;

  static ShortcutAction? fromCode(String? code) {
    if (code == null) return null;
    for (final a in ShortcutAction.values) {
      if (a.code == code) return a;
    }
    return null;
  }
}

/// Recibe las órdenes del atajo de ajustes rápidos.
///
/// ## Dos caminos, porque hay dos escenarios
///
/// **La app ya estaba abierta**: el sistema entrega un intent nuevo y la parte
/// nativa llama a `onAction` de inmediato.
///
/// **La app estaba cerrada**: el atajo la arranca desde cero. Cuando llega el
/// intent el canal todavía no existe, así que la orden queda guardada en la
/// parte nativa y Flutter la reclama al terminar de arrancar con
/// `consumePendingAction`.
///
/// Sin el segundo camino el atajo funcionaría sólo con la app ya abierta, que
/// es precisamente el caso en el que no hace falta.
class ShortcutReceiver {
  ShortcutReceiver() {
    if (_isSupported) {
      _channel.setMethodCallHandler(_onCall);
    }
  }

  static const MethodChannel _channel =
      MethodChannel('co.edu.eam.baliza/shortcuts');

  final StreamController<ShortcutAction> _actions =
      StreamController<ShortcutAction>.broadcast();

  /// Órdenes recibidas mientras la app está viva.
  Stream<ShortcutAction> get actions => _actions.stream;

  bool get _isSupported => !kIsWeb && Platform.isAndroid;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'onAction') return;
    final action = ShortcutAction.fromCode(call.arguments as String?);
    if (action != null && !_actions.isClosed) _actions.add(action);
  }

  /// Reclama la orden que quedó pendiente del arranque, si la hubo.
  ///
  /// Devuelve `null` cuando la app se abrió con normalidad.
  Future<ShortcutAction?> consumePending() async {
    if (!_isSupported) return null;
    try {
      final code = await _channel.invokeMethod<String>('consumePendingAction');
      return ShortcutAction.fromCode(code);
    } catch (e) {
      debugPrint('[ShortcutReceiver] no se pudo leer la orden pendiente: $e');
      return null;
    }
  }

  Future<void> dispose() async {
    await _actions.close();
  }
}
