import '../services/disaster_detector.dart';

/// Fuente de anomalías inerciales y barométricas.
///
/// El umbralizado ocurre en la infraestructura, no aquí: sólo suben eventos que
/// ya superaron el umbral. Así el dominio no tiene que ver pasar cientos de
/// muestras por segundo.
abstract interface class SensorSource {
  /// Anomalías detectadas, ya filtradas por umbral.
  Stream<SensorAnomaly> get anomalies;

  /// `true` si el equipo tiene barómetro. Condiciona la regla de decisión.
  bool get hasBarometer;

  bool get isListening;

  /// Empieza a muestrear con los umbrales indicados.
  Future<void> start(DetectionThresholds thresholds);

  /// Cambia los umbrales sin reiniciar el muestreo.
  Future<void> updateThresholds(DetectionThresholds thresholds);

  Future<void> stop();

  Future<void> dispose();
}

/// Sirena audible.
///
/// Es tan importante como el radio: el BLE lleva al rescatista a unos metros,
/// pero el último tramo bajo escombros se hace de oído.
abstract interface class SirenPlayer {
  bool get isPlaying;

  /// Emite el patrón de sirena en bucle, forzando el volumen al máximo.
  Future<void> start();

  Future<void> stop();

  Future<void> dispose();
}

/// Señalización física complementaria: vibración y linterna.
abstract interface class SignalingDevices {
  bool get hasTorch;

  Future<void> startVibrationPattern();

  Future<void> stopVibration();

  Future<void> startTorchPattern();

  Future<void> stopTorch();

  Future<void> dispose();
}

/// Estado de la batería. Viaja en la baliza y condiciona el modo de ahorro.
abstract interface class BatterySource {
  /// Carga actual 0..100, o `null` si no se pudo leer.
  Future<int?> level();

  Stream<int> get levelChanges;
}

/// Avisos al sistema operativo.
abstract interface class NotificationService {
  Future<bool> requestPermission();

  /// Muestra el aviso "¿estás bien?" con acciones directas, para que se pueda
  /// responder sin desbloquear el teléfono.
  Future<void> showAreYouOkay({required Duration countdown});

  Future<void> dismissAreYouOkay();

  /// Aviso persistente mientras se emite auxilio.
  Future<void> showTransmitting();

  /// Aviso persistente mientras se busca a otras personas.
  Future<void> showScanning({required int foundCount});

  Future<void> notifyNewSurvivor({required String shortCode});

  Future<void> clearAll();
}

/// Persistencia local de preferencias y ficha médica.
abstract interface class SettingsStore {
  Future<String?> readString(String key);
  Future<void> writeString(String key, String value);
  Future<bool?> readBool(String key);
  Future<void> writeBool(String key, bool value);
  Future<int?> readInt(String key);
  Future<void> writeInt(String key, int value);
  Future<void> remove(String key);
}

/// Permisos del sistema que la app necesita.
enum AppPermission {
  bluetooth('Bluetooth', 'Para emitir y detectar balizas sin red'),
  location('Ubicación', 'Android exige este permiso para buscar por Bluetooth'),
  notifications('Notificaciones', 'Para avisarte si detectamos un sismo'),
  batteryOptimization(
      'Ejecución en segundo plano', 'Para no dejar de emitir con la pantalla apagada');

  const AppPermission(this.label, this.rationale);
  final String label;
  final String rationale;
}

/// Consulta y solicitud de permisos.
abstract interface class PermissionService {
  Future<bool> isGranted(AppPermission permission);

  Future<bool> request(AppPermission permission);

  /// Permisos imprescindibles que aún faltan.
  Future<List<AppPermission>> missingCritical();

  Future<void> openSystemSettings();
}
