import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:torch_light/torch_light.dart';
import 'package:vibration/vibration.dart';

import '../../domain/ports/device_services.dart';

/// Sirena audible en bucle.
///
/// Suena aunque el teléfono esté en silencio: se declara el contexto de audio
/// como alarma, que es la categoría que el sistema operativo exceptúa del modo
/// silencioso. Una sirena que respeta el modo silencioso no sirve para nada.
class AudioSirenPlayer implements SirenPlayer {
  AudioSirenPlayer();

  static const _asset = 'audio/siren.wav';

  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> start() async {
    if (_playing) return;
    await _player.setReleaseMode(ReleaseMode.loop);
    await _player.setVolume(1);
    await _player.setAudioContext(
      AudioContext(
        android: const AudioContextAndroid(
          isSpeakerphoneOn: true,
          stayAwake: true,
          contentType: AndroidContentType.sonification,
          usageType: AndroidUsageType.alarm,
          audioFocus: AndroidAudioFocus.gainTransientMayDuck,
        ),
        iOS: AudioContextIOS(
          category: AVAudioSessionCategory.playback,
          options: const {AVAudioSessionOptions.mixWithOthers},
        ),
      ),
    );
    await _player.play(AssetSource(_asset));
    _playing = true;
  }

  @override
  Future<void> stop() async {
    if (!_playing) return;
    await _player.stop();
    _playing = false;
  }

  @override
  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}

/// Vibración y linterna como señales complementarias.
///
/// El patrón de vibración y el de linterna reproducen **· · · — — — · · ·**,
/// el SOS en código morse. Es el único código que un rescatista reconoce sin
/// haber leído nunca la documentación de esta app.
class DeviceSignaling implements SignalingDevices {
  DeviceSignaling();

  /// SOS en morse, en milisegundos: pausa inicial y luego pares
  /// espera/duración. Punto 200 ms, raya 600 ms, hueco 200 ms entre símbolos y
  /// 600 ms entre letras.
  static const List<int> morsePattern = <int>[
    0,
    200, 200, 200, 200, 200, 600, // S
    600, 200, 600, 200, 600, 600, // O
    200, 200, 200, 200, 200, 1400, // S y pausa larga
  ];

  bool _hasTorch = false;
  bool _torchOn = false;
  Timer? _torchTimer;
  bool _probed = false;

  @override
  bool get hasTorch => _hasTorch;

  /// Comprueba una sola vez si el equipo tiene linterna.
  Future<void> probe() async {
    if (_probed) return;
    _probed = true;
    try {
      _hasTorch = await TorchLight.isTorchAvailable();
    } catch (_) {
      _hasTorch = false;
    }
  }

  @override
  Future<void> startVibrationPattern() async {
    final can = await Vibration.hasVibrator();
    if (!can) return;
    await Vibration.vibrate(pattern: morsePattern, repeat: 0);
  }

  @override
  Future<void> stopVibration() async {
    try {
      await Vibration.cancel();
    } catch (_) {
      // Nada que hacer si el motor háptico no responde.
    }
  }

  @override
  Future<void> startTorchPattern() async {
    await probe();
    if (!_hasTorch) return;
    _torchTimer?.cancel();

    var index = 0;
    // Se recorre el mismo patrón morse alternando encendido y apagado.
    void step() {
      if (index >= morsePattern.length) index = 1;
      final duration = morsePattern[index];
      final shouldLight = index.isEven;
      unawaited(_setTorch(shouldLight));
      index++;
      _torchTimer = Timer(Duration(milliseconds: duration), step);
    }

    index = 1;
    step();
  }

  Future<void> _setTorch(bool on) async {
    if (on == _torchOn) return;
    try {
      if (on) {
        await TorchLight.enableTorch();
      } else {
        await TorchLight.disableTorch();
      }
      _torchOn = on;
    } catch (_) {
      _hasTorch = false;
      _torchTimer?.cancel();
      _torchTimer = null;
    }
  }

  @override
  Future<void> stopTorch() async {
    _torchTimer?.cancel();
    _torchTimer = null;
    await _setTorch(false);
  }

  @override
  Future<void> dispose() async {
    await stopTorch();
    await stopVibration();
  }
}

/// Nivel de batería del dispositivo.
class DeviceBattery implements BatterySource {
  DeviceBattery();

  final Battery _battery = Battery();

  @override
  Future<int?> level() async {
    try {
      return await _battery.batteryLevel;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<int> get levelChanges =>
      Stream<int>.periodic(const Duration(minutes: 1))
          .asyncMap((_) async => await level() ?? 0)
          .where((v) => v > 0);
}

/// Preferencias locales sobre `SharedPreferences`.
class PrefsSettingsStore implements SettingsStore {
  PrefsSettingsStore(this._prefs);

  final SharedPreferences _prefs;

  static Future<PrefsSettingsStore> open() async =>
      PrefsSettingsStore(await SharedPreferences.getInstance());

  @override
  Future<String?> readString(String key) async => _prefs.getString(key);

  @override
  Future<void> writeString(String key, String value) async =>
      _prefs.setString(key, value);

  @override
  Future<bool?> readBool(String key) async => _prefs.getBool(key);

  @override
  Future<void> writeBool(String key, bool value) async =>
      _prefs.setBool(key, value);

  @override
  Future<int?> readInt(String key) async => _prefs.getInt(key);

  @override
  Future<void> writeInt(String key, int value) async =>
      _prefs.setInt(key, value);

  @override
  Future<void> remove(String key) async => _prefs.remove(key);
}

/// Permisos del sistema.
class SystemPermissions implements PermissionService {
  const SystemPermissions();

  List<ph.Permission> _mapped(AppPermission permission) {
    return switch (permission) {
      AppPermission.bluetooth => <ph.Permission>[
          ph.Permission.bluetoothScan,
          ph.Permission.bluetoothAdvertise,
          ph.Permission.bluetoothConnect,
        ],
      AppPermission.location => <ph.Permission>[ph.Permission.locationWhenInUse],
      AppPermission.notifications => <ph.Permission>[ph.Permission.notification],
      AppPermission.batteryOptimization => <ph.Permission>[
          ph.Permission.ignoreBatteryOptimizations,
        ],
    };
  }

  @override
  Future<bool> isGranted(AppPermission permission) async {
    for (final p in _mapped(permission)) {
      final status = await p.status;
      // Un permiso no soportado por la plataforma no bloquea: en iOS varios de
      // los de Android sencillamente no existen.
      if (status.isPermanentlyDenied || status.isDenied) {
        if (await p.shouldShowRequestRationale || status.isPermanentlyDenied) {
          return false;
        }
        return false;
      }
    }
    return true;
  }

  @override
  Future<bool> request(AppPermission permission) async {
    final results = await _mapped(permission).request();
    return results.values.every((s) => s.isGranted || s.isLimited);
  }

  @override
  Future<List<AppPermission>> missingCritical() async {
    final missing = <AppPermission>[];
    for (final p in <AppPermission>[
      AppPermission.bluetooth,
      AppPermission.location,
      AppPermission.notifications,
    ]) {
      if (!await isGranted(p)) missing.add(p);
    }
    return missing;
  }

  @override
  Future<void> openSystemSettings() async {
    await ph.openAppSettings();
  }
}

/// Implementación nula de permisos, para el modo simulación y el escritorio.
class AlwaysGrantedPermissions implements PermissionService {
  const AlwaysGrantedPermissions();

  @override
  Future<bool> isGranted(AppPermission permission) async => true;

  @override
  Future<bool> request(AppPermission permission) async => true;

  @override
  Future<List<AppPermission>> missingCritical() async => const [];

  @override
  Future<void> openSystemSettings() async {}
}

/// Sirena silenciosa, para simulación y pruebas de escritorio.
class NoopSiren implements SirenPlayer {
  bool _playing = false;

  @override
  bool get isPlaying => _playing;

  @override
  Future<void> start() async {
    _playing = true;
    debugPrint('[NoopSiren] sirena ON');
  }

  @override
  Future<void> stop() async {
    _playing = false;
    debugPrint('[NoopSiren] sirena OFF');
  }

  @override
  Future<void> dispose() async {}
}

/// Señalización nula, para simulación.
class NoopSignaling implements SignalingDevices {
  @override
  bool get hasTorch => true;

  @override
  Future<void> startVibrationPattern() async {}

  @override
  Future<void> stopVibration() async {}

  @override
  Future<void> startTorchPattern() async {}

  @override
  Future<void> stopTorch() async {}

  @override
  Future<void> dispose() async {}
}

/// Batería simulada, que además decae para poder ver el indicador cambiar.
class SimulatedBattery implements BatterySource {
  SimulatedBattery({int initial = 82}) : _level = initial;

  int _level;

  @override
  Future<int?> level() async => _level;

  @override
  Stream<int> get levelChanges =>
      Stream<int>.periodic(const Duration(seconds: 30), (_) {
        _level = (_level - 1).clamp(1, 100);
        return _level;
      });
}
