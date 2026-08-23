import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Contrato del servicio que mantiene vivo el proceso.
abstract interface class KeepAliveService {
  /// Configura los canales del servicio. Debe ser idempotente.
  Future<void> initialize();

  /// Solicita los permisos que el servicio necesita para sobrevivir.
  Future<void> requestPermissions();

  Future<bool> get isRunning;

  Future<void> start({required String title, required String body});

  Future<void> update({required String title, required String body});

  Future<void> stop();
}

/// Mantiene vivo el proceso mientras la baliza emite o busca.
///
/// ## Por qué hace falta
///
/// Una notificación persistente **no** impide que Android mate la aplicación.
/// Desde Android 8 el sistema congela los procesos en segundo plano a los pocos
/// minutos de apagar la pantalla, y desde Android 12 lo hace de forma aún más
/// agresiva. Sin un servicio en primer plano declarado, la baliza dejaría de
/// emitir justo cuando la persona lleva un rato quieta bajo escombros y ya no
/// está mirando el teléfono — es decir, en el único escenario que importa.
///
/// ## Qué hace y qué no
///
/// El servicio no emite: el anuncio BLE sigue viviendo en el aislado principal,
/// junto con el resto de la aplicación. Lo único que hace este servicio es
/// existir, y al existir le dice al sistema operativo que el proceso está
/// realizando trabajo visible para la persona usuaria y no debe terminarse.
///
/// Es la razón de que el manejador no haga nada en `onRepeatEvent`: cualquier
/// trabajo real ahí ocurriría en otro aislado, sin acceso al estado de la app.
class ForegroundKeepAlive implements KeepAliveService {
  ForegroundKeepAlive();

  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'baliza_foreground',
        channelName: 'Baliza activa',
        channelDescription:
            'Mantiene la emisión y la búsqueda cuando la pantalla se apaga.',
        // Importancia baja y sin sonido: este aviso acompaña a la sirena, que
        // ya es bastante ruido. No debe competir con ella.
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        playSound: false,
        enableVibration: false,
        showWhen: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: false,
        playSound: false,
      ),
      foregroundTaskOptions: ForegroundTaskOptions(
        // Un latido cada 15 s. No hace trabajo: sólo evita que el sistema
        // considere inactivo al servicio.
        eventAction: ForegroundTaskEventAction.repeat(15000),
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: false,
      ),
    );

    _initialized = true;
  }

  /// Solicita los permisos que el servicio necesita para sobrevivir.
  ///
  /// La exención de optimización de batería es especialmente importante en
  /// capas de fabricante agresivas (Xiaomi, Huawei, Samsung), que matan
  /// procesos incluso con servicio en primer plano declarado.
  @override
  Future<void> requestPermissions() async {
    try {
      final notification =
          await FlutterForegroundTask.checkNotificationPermission();
      if (notification != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }

      if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
        await FlutterForegroundTask.requestIgnoreBatteryOptimization();
      }
    } catch (e) {
      // Que el usuario deniegue estos permisos degrada la app, pero no la
      // rompe: seguirá emitiendo mientras la pantalla esté encendida.
      debugPrint('[ForegroundKeepAlive] permisos no concedidos: $e');
    }
  }

  @override
  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  @override
  Future<void> start({
    required String title,
    required String body,
  }) async {
    await initialize();

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 4210,
      notificationTitle: title,
      notificationText: body,
      callback: _startCallback,
    );
  }

  @override
  Future<void> update({
    required String title,
    required String body,
  }) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: body,
    );
  }

  @override
  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }
}

/// Punto de entrada del aislado del servicio.
///
/// Debe ser una función de nivel superior anotada con `vm:entry-point`: el
/// sistema la invoca desde código nativo, fuera del árbol de la aplicación.
@pragma('vm:entry-point')
void _startCallback() {
  FlutterForegroundTask.setTaskHandler(_KeepAliveHandler());
}

/// Manejador deliberadamente vacío.
///
/// Todo el trabajo real —anuncio BLE, escaneo, sensores— vive en el aislado
/// principal. Este manejador existe únicamente para que el servicio exista.
class _KeepAliveHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    debugPrint('[ForegroundKeepAlive] servicio iniciado');
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Sin trabajo: el latido sólo mantiene el servicio marcado como activo.
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundKeepAlive] servicio detenido (timeout: $isTimeout)');
  }
}

/// Implementación nula, para simulación y escritorio.
class NoopKeepAlive implements KeepAliveService {
  const NoopKeepAlive();

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<bool> get isRunning async => false;

  @override
  Future<void> start({required String title, required String body}) async =>
      debugPrint('[NoopKeepAlive] servicio ON: $title');

  @override
  Future<void> update({required String title, required String body}) async {}

  @override
  Future<void> stop() async => debugPrint('[NoopKeepAlive] servicio OFF');
}
