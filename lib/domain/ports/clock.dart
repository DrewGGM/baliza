/// Fuente de tiempo inyectable.
///
/// Existe por una única razón: que toda la lógica que depende del paso del
/// tiempo —detección sísmica, expiración de balizas, cuenta atrás del aviso
/// "¿estás bien?"— pueda ejercitarse sin esperar en tiempo real.
///
/// Ninguna clase de `domain/` debe llamar a `DateTime.now()` directamente.
abstract interface class Clock {
  DateTime now();
}

/// Reloj de producción: delega en el reloj del sistema.
class SystemClock implements Clock {
  const SystemClock();

  @override
  DateTime now() => DateTime.now();
}

/// Reloj controlable, para escenarios de simulación y verificación.
///
/// Permite comprimir una ventana de dos minutos en un salto instantáneo.
class ManualClock implements Clock {
  ManualClock(this._now);

  DateTime _now;

  @override
  DateTime now() => _now;

  /// Adelanta el reloj.
  void advance(Duration delta) => _now = _now.add(delta);

  /// Sitúa el reloj en un instante concreto.
  void setTo(DateTime instant) => _now = instant;
}
