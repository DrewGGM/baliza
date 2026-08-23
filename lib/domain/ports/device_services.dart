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
///
/// Cada uno lleva no sólo su nombre, sino **para qué sirve** y **qué se pierde
/// si se deniega**. Esos dos textos se muestran juntos antes de pedirlo: una
/// persona que entiende la consecuencia concreta decide mejor que una a la que
/// se le suelta el diálogo del sistema sin contexto.
enum AppPermission {
  bluetooth(
    label: 'Bluetooth',
    purpose: 'Es el canal por el que tu teléfono emite la señal de auxilio y '
        'detecta a quien pide ayuda cerca.',
    ifDenied: 'Sin este permiso la app no puede hacer nada: ni emitir ni '
        'buscar.',
    essential: true,
  ),

  location(
    label: 'Ubicación',
    purpose: 'Android hasta la versión 11 exige este permiso para poder buscar '
        'dispositivos por Bluetooth.',
    ifDenied: 'En teléfonos con Android 11 o anterior no podrás detectar a '
        'nadie. Baliza no lee tu GPS ni guarda dónde estás.',
    essential: true,
  ),

  notifications(
    label: 'Notificaciones',
    purpose: 'Para preguntarte "¿estás bien?" tras un sismo y para mostrar el '
        'aviso desde el que puedes detener la emisión sin desbloquear.',
    ifDenied: 'No verás la pregunta tras un sismo y tendrás que abrir la app '
        'para detener la señal.',
    essential: false,
  ),

  batteryOptimization(
    label: 'Ejecución en segundo plano',
    purpose: 'Para que la baliza siga emitiendo cuando la pantalla se apaga.',
    ifDenied: 'El sistema puede detener la emisión a los pocos minutos de '
        'bloquear el teléfono, justo cuando más falta hace.',
    essential: false,
  );

  const AppPermission({
    required this.label,
    required this.purpose,
    required this.ifDenied,
    required this.essential,
  });

  final String label;

  /// Para qué se usa, en una frase.
  final String purpose;

  /// Qué deja de funcionar si se deniega.
  final String ifDenied;

  /// `true` si la app queda inservible sin él.
  final bool essential;
}

/// Estado de un permiso.
enum PermissionState {
  /// Concedido.
  granted,

  /// Denegado, pero se puede volver a pedir.
  denied,

  /// Denegado de forma permanente: sólo se resuelve en los ajustes del
  /// sistema. Pedirlo otra vez no muestra ningún diálogo.
  permanentlyDenied,

  /// La plataforma no tiene este permiso. En iOS varios de los de Android
  /// sencillamente no existen, y ausencia no debe leerse como denegación.
  unavailable;

  bool get isGranted => this == PermissionState.granted;

  /// `true` si conviene ofrecer un atajo a los ajustes del sistema en vez de
  /// volver a pedirlo.
  bool get needsSystemSettings => this == PermissionState.permanentlyDenied;

  /// `true` si el permiso no impide funcionar, sea porque está concedido o
  /// porque no aplica en esta plataforma.
  bool get isSatisfied =>
      this == PermissionState.granted || this == PermissionState.unavailable;
}

/// Consulta y solicitud de permisos.
abstract interface class PermissionService {
  /// Estado actual, sin mostrar ningún diálogo.
  Future<PermissionState> check(AppPermission permission);

  /// Solicita el permiso y devuelve el estado resultante.
  Future<PermissionState> request(AppPermission permission);

  /// Estado de todos los permisos de una sola pasada.
  Future<Map<AppPermission, PermissionState>> checkAll();

  /// Abre la pantalla de ajustes de la app en el sistema.
  Future<void> openSystemSettings();
}
