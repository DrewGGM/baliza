import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Órdenes que el aviso persistente puede enviar a la aplicación.
abstract final class KeepAliveCommand {
  /// Identificador del botón que detiene la emisión de auxilio.
  static const stopSos = 'baliza_stop_sos';

  /// Identificador del botón que detiene la búsqueda.
  static const stopScan = 'baliza_stop_scan';
}

/// Contrato del servicio que mantiene vivo el proceso.
abstract interface class KeepAliveService {
  /// Configura los canales del servicio. Debe ser idempotente.
  Future<void> initialize();

  /// Solicita los permisos que el servicio necesita para sobrevivir.
  Future<void> requestPermissions();

  Future<bool> get isRunning;

  /// Órdenes que llegan desde los botones del aviso persistente.
  ///
  /// Es el canal por el que "Detener" llega a la aplicación cuando la pantalla
  /// está bloqueada y no hay interfaz con la que interactuar.
  Stream<String> get commands;

  Future<void> start({
    required String title,
    required String body,
    List<KeepAliveButton> buttons,
  });

  Future<void> update({
    required String title,
    required String body,
    List<KeepAliveButton>? buttons,
  });

  Future<void> stop();

  Future<void> dispose();
}

/// Botón del aviso persistente, en términos del dominio de la aplicación.
class KeepAliveButton {
  const KeepAliveButton({required this.id, required this.text});

  final String id;
  final String text;
}

/// Mantiene vivo el proceso mientras la baliza emite o busca, y ofrece el
/// único control accesible cuando la pantalla está bloqueada.
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
/// ## Por qué el botón "Detener" vive aquí y no en otra notificación
///
/// Las acciones de una notificación normal se entregan a un **aislado
/// distinto** cuando la aplicación no está en primer plano. Ese aislado no
/// tiene acceso al estado de la app, así que un manejador allí no puede
/// detener nada: la persona pulsa "Detener", la notificación desaparece y la
/// sirena sigue sonando.
///
/// El servicio en primer plano sí tiene un canal de vuelta al aislado
/// principal (`sendDataToMain`). Por eso el control de detención vive en su
/// aviso y no en uno aparte, y por eso hay **un solo** aviso persistente: dos
/// avisos con dos botones "Detener" de los que sólo uno funciona es peor que
/// no tener ninguno.
class ForegroundKeepAlive implements KeepAliveService {
  ForegroundKeepAlive();

  bool _initialized = false;

  final StreamController<String> _commands =
      StreamController<String>.broadcast();

  @override
  Stream<String> get commands => _commands.stream;

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
        showNotification: true,
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

    // Canal de vuelta: lo que el aislado del servicio envía llega aquí.
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);

    _initialized = true;
  }

  void _onTaskData(Object data) {
    if (data is String && !_commands.isClosed) {
      _commands.add(data);
    }
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
    List<KeepAliveButton> buttons = const <KeepAliveButton>[],
  }) async {
    await initialize();

    final mapped = buttons
        .map((b) => NotificationButton(id: b.id, text: b.text))
        .toList(growable: false);

    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.updateService(
        notificationTitle: title,
        notificationText: body,
        notificationButtons: mapped,
      );
      return;
    }

    await FlutterForegroundTask.startService(
      serviceId: 4210,
      notificationTitle: title,
      notificationText: body,
      notificationButtons: mapped,
      callback: _startCallback,
    );
  }

  @override
  Future<void> update({
    required String title,
    required String body,
    List<KeepAliveButton>? buttons,
  }) async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.updateService(
      notificationTitle: title,
      notificationText: body,
      notificationButtons: buttons
          ?.map((b) => NotificationButton(id: b.id, text: b.text))
          .toList(growable: false),
    );
  }

  @override
  Future<void> stop() async {
    if (!await FlutterForegroundTask.isRunningService) return;
    await FlutterForegroundTask.stopService();
  }

  @override
  Future<void> dispose() async {
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    await _commands.close();
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

/// Manejador del aislado del servicio.
///
/// No hace trabajo de dominio: el anuncio BLE, el escaneo y los sensores viven
/// en el aislado principal. Su única función real es reenviar las pulsaciones
/// de los botones del aviso hacia allí.
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
  void onNotificationButtonPressed(String id) {
    debugPrint('[ForegroundKeepAlive] botón pulsado: $id');
    // Cruza al aislado principal, que es el único que puede detener la radio,
    // la sirena y la vibración.
    FlutterForegroundTask.sendDataToMain(id);
  }

  @override
  void onNotificationPressed() {
    // Al tocar el cuerpo del aviso se abre la app, para que la persona vea el
    // estado completo y el botón grande de detención.
    FlutterForegroundTask.launchApp();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    debugPrint('[ForegroundKeepAlive] servicio detenido (timeout: $isTimeout)');
  }
}

/// Implementación nula, para escritorio y web.
class NoopKeepAlive implements KeepAliveService {
  NoopKeepAlive();

  final StreamController<String> _commands =
      StreamController<String>.broadcast();

  @override
  Stream<String> get commands => _commands.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<void> requestPermissions() async {}

  @override
  Future<bool> get isRunning async => false;

  @override
  Future<void> start({
    required String title,
    required String body,
    List<KeepAliveButton> buttons = const <KeepAliveButton>[],
  }) async =>
      debugPrint('[NoopKeepAlive] servicio ON: $title');

  @override
  Future<void> update({
    required String title,
    required String body,
    List<KeepAliveButton>? buttons,
  }) async {}

  @override
  Future<void> stop() async => debugPrint('[NoopKeepAlive] servicio OFF');

  @override
  Future<void> dispose() async {
    await _commands.close();
  }
}
