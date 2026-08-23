import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';

import '../domain/ports/beacon_transport.dart';
import '../domain/ports/clock.dart';
import '../domain/ports/device_services.dart';
import '../domain/services/beacon_identity.dart';
import '../infrastructure/ble/ble_scanner.dart';
import '../infrastructure/ble/ble_transmitter.dart';
import '../infrastructure/platform/foreground_service.dart';
import '../infrastructure/platform/notifications.dart';
import '../infrastructure/platform/platform_services.dart';
import '../infrastructure/sensors/device_sensors.dart';
import '../infrastructure/simulation/scenarios.dart';
import '../infrastructure/simulation/simulated_radio.dart';
import 'app_settings.dart';
import 'detection_controller.dart';
import 'rescue_controller.dart';
import 'sos_controller.dart';

/// De dónde salen las señales que ve la app.
enum RuntimeMode {
  /// Radio Bluetooth real. Es el modo de producción.
  live('En vivo', 'Bluetooth real'),

  /// Bus en memoria. Permite recorrer la app entera sin hardware.
  simulated('Simulación', 'Sin Bluetooth, señales generadas');

  const RuntimeMode(this.label, this.description);
  final String label;
  final String description;
}

/// Raíz de composición: construye e interconecta todas las piezas.
///
/// Es el único punto del programa que sabe qué implementación concreta hay
/// detrás de cada puerto. Cambiar de Bluetooth real a simulación es cambiar
/// dos líneas aquí; ni el dominio ni la interfaz se enteran.
class BalizaRuntime {
  BalizaRuntime._({
    required this.mode,
    required this.settings,
    required this.sos,
    required this.rescue,
    required this.detection,
    required this.permissions,
    required this.clock,
    required this.identity,
    required this.keepAlive,
    required List<Future<void> Function()> disposers,
    this.simulationBus,
    this.simulatedSensors,
  }) : _disposers = disposers;

  final RuntimeMode mode;
  final AppSettings settings;
  final SosController sos;
  final RescueController rescue;
  final DetectionController detection;
  final PermissionService permissions;
  final Clock clock;
  final BeaconIdentity identity;

  /// Servicio que impide que el sistema mate el proceso mientras se emite.
  final KeepAliveService keepAlive;

  /// Bus de simulación, sólo presente en [RuntimeMode.simulated].
  final SimulatedRadioBus? simulationBus;

  /// Sensores controlables, sólo presentes en [RuntimeMode.simulated].
  final SimulatedSensorSource? simulatedSensors;

  final List<Future<void> Function()> _disposers;

  bool get isSimulated => mode == RuntimeMode.simulated;

  /// Construye el grafo completo de objetos.
  static Future<BalizaRuntime> boot({RuntimeMode? forceMode}) async {
    const clock = SystemClock();
    final store = await PrefsSettingsStore.open();
    final settings = AppSettings(store);
    await settings.load();

    final mode = forceMode ??
        (settings.simulation ? RuntimeMode.simulated : RuntimeMode.live);

    final identity = BeaconIdentity(clock: clock);

    final disposers = <Future<void> Function()>[];

    BeaconTransmitter transmitter;
    BeaconScanner scanner;
    SensorSource sensors;
    SirenPlayer siren;
    SignalingDevices signaling;
    BatterySource battery;
    PermissionService permissions;
    SimulatedRadioBus? bus;
    SimulatedSensorSource? simSensors;
    KeepAliveService keepAlive;

    if (mode == RuntimeMode.simulated) {
      bus = SimulatedRadioBus();
      for (final peer in SimulationScenario.collapse.build()) {
        bus.addPeer(peer);
      }
      final simTx = SimulatedTransmitter(bus);
      final simRx = SimulatedScanner(bus);
      simSensors = SimulatedSensorSource();

      transmitter = simTx;
      scanner = simRx;
      sensors = simSensors;
      siren = NoopSiren();
      signaling = NoopSignaling();
      battery = SimulatedBattery();
      permissions = const AlwaysGrantedPermissions();

      // El servicio en primer plano NO se simula. El modo simulación sustituye
      // el radio, no el sistema operativo: si alguien prueba la app en un
      // teléfono real, el aviso persistente y la supervivencia del proceso
      // deben comportarse igual que en producción. De lo contrario estaríamos
      // dejando sin ejercitar justo la pieza que sostiene la emisión con la
      // pantalla apagada.
      keepAlive = _buildKeepAlive();

      disposers
        ..add(simTx.dispose)
        ..add(simRx.dispose)
        ..add(bus.dispose)
        ..add(simSensors.dispose);
    } else {
      final tx = BleTransmitter();
      final rx = BleScanner();
      final deviceSensors = DeviceSensorSource();
      final audioSiren = AudioSirenPlayer();
      final deviceSignaling = DeviceSignaling();
      await deviceSignaling.probe();

      transmitter = tx;
      scanner = rx;
      sensors = deviceSensors;
      siren = audioSiren;
      signaling = deviceSignaling;
      battery = DeviceBattery();
      permissions = const SystemPermissions();

      keepAlive = _buildKeepAlive();

      disposers
        ..add(tx.dispose)
        ..add(rx.dispose)
        ..add(deviceSensors.dispose)
        ..add(audioSiren.dispose)
        ..add(deviceSignaling.dispose);
    }

    await keepAlive.initialize();

    // Las notificaciones necesitan poder llamar de vuelta a los controladores,
    // que todavía no existen. Se resuelve con indirección diferida.
    late final SosController sosController;
    late final DetectionController detectionController;

    final NotificationService notifications = mode == RuntimeMode.simulated
        ? DebugNotifications()
        : LocalNotifications(
            onImOkay: () => unawaited(detectionController.reportOkay()),
            onNeedHelp: () => unawaited(detectionController.reportNeedHelp()),
            onStopSos: () => unawaited(sosController.stopSos()),
          );

    if (notifications is LocalNotifications) {
      try {
        await notifications.initialize();
      } catch (e) {
        debugPrint('[BalizaRuntime] notificaciones no disponibles: $e');
      }
    }

    sosController = SosController(
      transmitter: transmitter,
      siren: siren,
      signaling: signaling,
      battery: battery,
      notifications: notifications,
      identity: identity,
      settings: settings,
      clock: clock,
      keepAlive: keepAlive,
    );

    final rescueController = RescueController(
      scanner: scanner,
      notifications: notifications,
      settings: settings,
      clock: clock,
      keepAlive: keepAlive,
    );

    detectionController = DetectionController(
      sensors: sensors,
      notifications: notifications,
      sos: sosController,
      settings: settings,
      clock: clock,
    );

    disposers
      ..add(() async => sosController.dispose())
      ..add(() async => rescueController.dispose())
      ..add(() async => detectionController.dispose());

    final runtime = BalizaRuntime._(
      mode: mode,
      settings: settings,
      sos: sosController,
      rescue: rescueController,
      detection: detectionController,
      permissions: permissions,
      clock: clock,
      identity: identity,
      keepAlive: keepAlive,
      disposers: disposers,
      simulationBus: bus,
      simulatedSensors: simSensors,
    );

    // Los botones del aviso persistente son el único control disponible con
    // la pantalla bloqueada. Aquí se encaminan a quien corresponde.
    final commandSub = keepAlive.commands.listen((command) {
      switch (command) {
        case KeepAliveCommand.stopSos:
          unawaited(sosController.stopSos());
        case KeepAliveCommand.stopScan:
          unawaited(rescueController.stopScanning());
      }
    });
    disposers.add(commandSub.cancel);
    disposers.add(keepAlive.dispose);

    // La vigilancia arranca sola si la persona la dejó activada.
    if (settings.autoDetection) {
      unawaited(detectionController.start());
    }

    return runtime;
  }

  /// Elige la implementación del servicio según la plataforma.
  ///
  /// `flutter_foreground_task` sólo existe en Android e iOS. En escritorio y
  /// web no hay nada que mantener vivo, así que se usa la versión nula.
  static KeepAliveService _buildKeepAlive() {
    if (kIsWeb) return NoopKeepAlive();
    if (Platform.isAndroid || Platform.isIOS) return ForegroundKeepAlive();
    return NoopKeepAlive();
  }

  /// Cambia el escenario de simulación en caliente.
  void loadScenario(SimulationScenario scenario) {
    final bus = simulationBus;
    if (bus == null) return;
    rescue.clearAll();
    bus.clearPeers();
    for (final peer in scenario.build()) {
      bus.addPeer(peer);
    }
  }

  Future<void> dispose() async {
    for (final d in _disposers.reversed) {
      try {
        await d();
      } catch (e) {
        debugPrint('[BalizaRuntime] error al liberar: $e');
      }
    }
  }
}
