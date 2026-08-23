import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/entities/survivor.dart';
import '../domain/ports/beacon_transport.dart';
import '../domain/ports/clock.dart';
import '../domain/ports/device_services.dart';
import '../domain/services/triage.dart';
import 'app_settings.dart';

/// Qué se muestra en la lista de rescate.
enum RescueFilter {
  sos('Auxilio', 'Solo quien pide ayuda'),
  all('Todo', 'Auxilios, personas a salvo y rescatistas');

  const RescueFilter(this.label, this.description);
  final String label;
  final String description;
}

/// Gestiona la búsqueda de personas: escaneo, registro y ordenamiento.
class RescueController extends ChangeNotifier {
  RescueController({
    required BeaconScanner scanner,
    required NotificationService notifications,
    required AppSettings settings,
    required Clock clock,
    this.refreshInterval = const Duration(seconds: 1),
  })  : _scanner = scanner,
        _notifications = notifications,
        _settings = settings,
        _clock = clock {
    _radioSub = _scanner.radioState.listen((s) {
      _radio = s;
      notifyListeners();
    });
  }

  final BeaconScanner _scanner;
  final NotificationService _notifications;
  final AppSettings _settings;
  final Clock _clock;

  /// Cada cuánto se recalcula el orden y se refresca la interfaz. Un segundo
  /// es suficiente: más rápido sólo produce parpadeo, más lento hace que la
  /// tendencia de proximidad se sienta muerta al caminar.
  final Duration refreshInterval;

  final SurvivorRegistry _registry = SurvivorRegistry();

  StreamSubscription<BeaconReception>? _receptionSub;
  StreamSubscription<RadioState>? _radioSub;
  Timer? _refreshTimer;

  bool _scanning = false;
  RadioState _radio = RadioState.unknown;
  RescueFilter _filter = RescueFilter.sos;
  int? _focusedBeaconId;
  String? _lastError;

  bool get isScanning => _scanning;
  RadioState get radioState => _radio;
  RescueFilter get filter => _filter;
  String? get lastError => _lastError;
  SurvivorRegistry get registry => _registry;

  /// Baliza que el rescatista está siguiendo en detalle.
  int? get focusedBeaconId => _focusedBeaconId;

  Survivor? get focused =>
      _focusedBeaconId == null ? null : _registry[_focusedBeaconId!];

  int get sosCount => _registry.sosOnly.length;
  int get totalCount => _registry.length;

  /// Balizas visibles, ya ordenadas por prioridad.
  List<Survivor> get visible {
    final source = switch (_filter) {
      RescueFilter.sos => _registry.sosOnly,
      RescueFilter.all => _registry.all,
    };
    return _settings.ranker.rank(source, _clock.now());
  }

  TriageRanker get ranker => _settings.ranker;

  DateTime get now => _clock.now();

  Future<void> startScanning() async {
    if (_scanning) return;
    _lastError = null;
    try {
      await _scanner.start();
    } catch (e) {
      _lastError = 'No se pudo iniciar la búsqueda: $e';
      notifyListeners();
      return;
    }

    _scanning = true;
    _receptionSub = _scanner.receptions.listen(_onReception, onError: (Object e) {
      _lastError = 'Error de recepción: $e';
      notifyListeners();
    });

    _refreshTimer?.cancel();
    _refreshTimer = Timer.periodic(refreshInterval, (_) => notifyListeners());

    unawaited(_notifyScanning());
    notifyListeners();
  }

  Future<void> stopScanning() async {
    if (!_scanning) return;
    _scanning = false;
    await _receptionSub?.cancel();
    _receptionSub = null;
    _refreshTimer?.cancel();
    _refreshTimer = null;
    try {
      await _scanner.stop();
    } catch (_) {
      // Detener nunca debe fallar de cara al usuario.
    }
    unawaited(_notifications.clearAll());
    notifyListeners();
  }

  void _onReception(BeaconReception reception) {
    final isNew = _registry.observe(
      signal: reception.signal,
      rssi: reception.rssi,
      at: reception.at,
    );

    if (isNew && reception.signal.isSos) {
      final survivor = _registry[reception.signal.beaconId];
      if (survivor != null) {
        unawaited(
          _notifications.notifyNewSurvivor(shortCode: survivor.shortCode),
        );
      }
      unawaited(_notifyScanning());
    }

    notifyListeners();
  }

  Future<void> _notifyScanning() async {
    try {
      await _notifications.showScanning(foundCount: sosCount);
    } catch (_) {
      // El aviso persistente es una comodidad, no un requisito.
    }
  }

  void setFilter(RescueFilter value) {
    _filter = value;
    notifyListeners();
  }

  void focus(int? beaconId) {
    _focusedBeaconId = beaconId;
    notifyListeners();
  }

  /// Marca una baliza como atendida y la retira de la lista.
  ///
  /// Es una decisión local del equipo que la retira; no viaja a ningún lado y
  /// no afecta a lo que ven otros rescatistas. Se puede deshacer volviendo a
  /// detectar la baliza, que reaparece sola en la siguiente recepción.
  void markAsAttended(int beaconId) {
    _registry.remove(beaconId);
    if (_focusedBeaconId == beaconId) _focusedBeaconId = null;
    notifyListeners();
  }

  void clearAll() {
    _registry.clear();
    _focusedBeaconId = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _receptionSub?.cancel();
    _radioSub?.cancel();
    super.dispose();
  }
}
