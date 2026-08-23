import 'dart:math';

import '../ports/clock.dart';

/// Gestiona el identificador seudónimo de 32 bits que viaja en cada baliza.
///
/// ## El dilema
///
/// Un identificador **fijo** convierte la app en un rastreador: cualquiera con
/// un escáner podría seguir a una persona por la ciudad durante meses. Un
/// identificador **siempre cambiante** rompe el rescate: el equipo perdería la
/// pista de la señal justo mientras se acerca a ella.
///
/// ## La regla
///
/// El identificador rota cada [rotationPeriod] **mientras no haya emergencia**.
/// En cuanto se activa una emisión de auxilio queda **congelado** hasta que la
/// emisión termina. Durante el rescate la continuidad vale más que el
/// anonimato; fuera de él, al revés.
///
/// El valor se sortea con un generador pseudoaleatorio y no se deriva de
/// ningún dato del dispositivo ni de la persona: no hay forma de remontar
/// desde el identificador hasta un IMEI, una MAC o un nombre.
class BeaconIdentity {
  BeaconIdentity({
    required this.clock,
    Random? random,
    this.rotationPeriod = const Duration(minutes: 15),
  }) : _random = random ?? Random.secure() {
    _current = _generate();
    _rotatedAt = clock.now();
  }

  final Clock clock;
  final Random _random;

  /// Cada cuánto se sortea un identificador nuevo en reposo.
  final Duration rotationPeriod;

  late int _current;
  late DateTime _rotatedAt;
  bool _frozen = false;

  /// Identificador vigente, rotándolo si ya venció y no está congelado.
  int get current {
    _rotateIfDue();
    return _current;
  }

  /// `true` si la rotación está suspendida por emergencia activa.
  bool get isFrozen => _frozen;

  DateTime get rotatedAt => _rotatedAt;

  /// Cuánto falta para la próxima rotación. `null` si está congelado.
  Duration? get timeUntilRotation {
    if (_frozen) return null;
    final elapsed = clock.now().difference(_rotatedAt);
    final remaining = rotationPeriod - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  /// Congela el identificador. Se invoca al iniciar una emisión de auxilio.
  ///
  /// Es idempotente: llamarlo dos veces no altera el estado.
  void freeze() => _frozen = true;

  /// Reanuda la rotación al terminar la emergencia.
  ///
  /// Fuerza un identificador nuevo de inmediato: si se conservara el mismo que
  /// se usó durante la emergencia, quien lo hubiera anotado podría seguir a esa
  /// persona después, que es justo lo que la rotación evita.
  void unfreeze() {
    if (!_frozen) return;
    _frozen = false;
    _forceRotate();
  }

  void _rotateIfDue() {
    if (_frozen) return;
    if (clock.now().difference(_rotatedAt) >= rotationPeriod) {
      _forceRotate();
    }
  }

  void _forceRotate() {
    var next = _generate();
    // Evita repetir el identificador anterior: una rotación que no cambia nada
    // sería indistinguible de no haber rotado.
    var guard = 0;
    while (next == _current && guard++ < 8) {
      next = _generate();
    }
    _current = next;
    _rotatedAt = clock.now();
  }

  /// Sortea un entero de 32 bits, descartando 0 y 0xFFFFFFFF, que se reservan
  /// como valores centinela del protocolo.
  int _generate() {
    while (true) {
      final value = (_random.nextInt(1 << 16) << 16) | _random.nextInt(1 << 16);
      if (value != 0 && value != 0xFFFFFFFF) return value;
    }
  }
}
