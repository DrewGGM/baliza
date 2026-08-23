import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../domain/ports/device_services.dart';

/// Acciones que la persona puede pulsar directamente sobre la notificación.
abstract final class NotificationActions {
  static const imOkay = 'baliza_im_okay';
  static const needHelp = 'baliza_need_help';
  static const stopSos = 'baliza_stop_sos';
}

/// Avisos del sistema operativo.
///
/// ## Por qué las acciones van en la notificación
///
/// Tras un sismo, quien queda atrapado puede tener el teléfono a medio metro,
/// boca abajo, con la pantalla rota y sin poder desbloquearlo. La pregunta
/// "¿estás bien?" lleva sus dos respuestas como botones de la propia
/// notificación, en la pantalla de bloqueo, para que responder no exija
/// desbloquear ni abrir nada.
class LocalNotifications implements NotificationService {
  LocalNotifications({
    this.onImOkay,
    this.onNeedHelp,
    this.onStopSos,
  });

  /// Callbacks que la capa de aplicación conecta al arrancar.
  final VoidCallback? onImOkay;
  final VoidCallback? onNeedHelp;
  final VoidCallback? onStopSos;

  static const _channelAlert = 'baliza_alert';
  static const _channelOngoing = 'baliza_ongoing';
  static const _channelFound = 'baliza_found';

  static const _idAreYouOkay = 1001;
  static const _idTransmitting = 1002;
  static const _idScanning = 1003;
  static const _idFound = 1004;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: androidInit,
        iOS: darwinInit,
      ),
      onDidReceiveNotificationResponse: _onResponse,
      onDidReceiveBackgroundNotificationResponse: _onBackgroundResponse,
    );

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    // Canal de alerta: máxima prioridad, salta sobre la pantalla de bloqueo.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelAlert,
        'Alertas de sismo',
        description: 'Pregunta si estás bien tras detectar un evento sísmico.',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      ),
    );

    // Canal persistente: sin sonido, porque acompaña a la sirena y no debe
    // competir con ella.
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelOngoing,
        'Emisión y búsqueda',
        description: 'Aviso permanente mientras emites o buscas.',
        importance: Importance.low,
        playSound: false,
        enableVibration: false,
      ),
    );

    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _channelFound,
        'Personas detectadas',
        description: 'Avisa cuando aparece una baliza nueva.',
        importance: Importance.high,
      ),
    );

    _initialized = true;
  }

  void _onResponse(NotificationResponse response) {
    switch (response.actionId) {
      case NotificationActions.imOkay:
        onImOkay?.call();
      case NotificationActions.needHelp:
        onNeedHelp?.call();
      case NotificationActions.stopSos:
        onStopSos?.call();
    }
  }

  /// Manejador en segundo plano. Debe ser una función de nivel superior o
  /// estática: el sistema la invoca en un aislado distinto, sin acceso al
  /// estado de la app.
  @pragma('vm:entry-point')
  static void _onBackgroundResponse(NotificationResponse response) {
    debugPrint('[LocalNotifications] acción en segundo plano: '
        '${response.actionId}');
  }

  @override
  Future<bool> requestPermission() async {
    await initialize();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    return await ios?.requestPermissions(alert: true, sound: true, badge: true) ??
        false;
  }

  @override
  Future<void> showAreYouOkay({required Duration countdown}) async {
    await initialize();
    final seconds = countdown.inSeconds;

    await _plugin.show(
      id: _idAreYouOkay,
      title: '¿Estás bien?',
      body: 'Detectamos un movimiento fuerte. Si no respondes en '
          '${_humanize(seconds)}, emitiremos una señal de auxilio.',
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelAlert,
          'Alertas de sismo',
          importance: Importance.max,
          priority: Priority.max,
          category: AndroidNotificationCategory.alarm,
          fullScreenIntent: true,
          ongoing: true,
          autoCancel: false,
          timeoutAfter: countdown.inMilliseconds,
          actions: const <AndroidNotificationAction>[
            AndroidNotificationAction(
              NotificationActions.imOkay,
              'Estoy bien',
              showsUserInterface: false,
              cancelNotification: true,
            ),
            AndroidNotificationAction(
              NotificationActions.needHelp,
              'Necesito ayuda',
              showsUserInterface: true,
              cancelNotification: true,
            ),
          ],
        ),
        iOS: const DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.critical,
          categoryIdentifier: 'baliza_are_you_okay',
        ),
      ),
    );
  }

  static String _humanize(int seconds) {
    if (seconds < 60) return '$seconds segundos';
    final minutes = seconds ~/ 60;
    return minutes == 1 ? '1 minuto' : '$minutes minutos';
  }

  @override
  Future<void> dismissAreYouOkay() async => _plugin.cancel(id: _idAreYouOkay);

  @override
  Future<void> showTransmitting() async {
    await initialize();
    await _plugin.show(
      id: _idTransmitting,
      title: 'Emitiendo señal de auxilio',
      body: 'Tu teléfono está pidiendo ayuda. Mantenlo encendido.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelOngoing,
          'Emisión y búsqueda',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          showWhen: true,
          usesChronometer: true,
          category: AndroidNotificationCategory.service,
          actions: <AndroidNotificationAction>[
            AndroidNotificationAction(
              NotificationActions.stopSos,
              'Detener',
              showsUserInterface: true,
            ),
          ],
        ),
        iOS: DarwinNotificationDetails(presentBanner: false),
      ),
    );
  }

  @override
  Future<void> showScanning({required int foundCount}) async {
    await initialize();
    final body = foundCount == 0
        ? 'Buscando señales de auxilio alrededor.'
        : foundCount == 1
            ? '1 persona detectada pidiendo ayuda.'
            : '$foundCount personas detectadas pidiendo ayuda.';

    await _plugin.show(
      id: _idScanning,
      title: 'Buscando personas',
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelOngoing,
          'Emisión y búsqueda',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          autoCancel: false,
          category: AndroidNotificationCategory.service,
        ),
        iOS: DarwinNotificationDetails(presentBanner: false),
      ),
    );
  }

  @override
  Future<void> notifyNewSurvivor({required String shortCode}) async {
    await initialize();
    await _plugin.show(
      id: _idFound,
      title: 'Nueva señal detectada',
      body: 'Baliza $shortCode pide ayuda cerca de ti.',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelFound,
          'Personas detectadas',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }

  @override
  Future<void> clearAll() async => _plugin.cancelAll();
}

/// Notificaciones que sólo escriben en consola, para simulación y escritorio.
class DebugNotifications implements NotificationService {
  DebugNotifications({this.onImOkay, this.onNeedHelp, this.onStopSos});

  final VoidCallback? onImOkay;
  final VoidCallback? onNeedHelp;
  final VoidCallback? onStopSos;

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> showAreYouOkay({required Duration countdown}) async =>
      debugPrint('[Notif] ¿Estás bien? cuenta atrás ${countdown.inSeconds}s');

  @override
  Future<void> dismissAreYouOkay() async =>
      debugPrint('[Notif] pregunta descartada');

  @override
  Future<void> showTransmitting() async => debugPrint('[Notif] emitiendo');

  @override
  Future<void> showScanning({required int foundCount}) async =>
      debugPrint('[Notif] buscando, $foundCount encontradas');

  @override
  Future<void> notifyNewSurvivor({required String shortCode}) async =>
      debugPrint('[Notif] nueva baliza $shortCode');

  @override
  Future<void> clearAll() async => debugPrint('[Notif] limpiadas');
}
