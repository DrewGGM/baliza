/// Qué señales auxiliares se mantienen encendidas según la batería que queda.
///
/// ## Por qué esto es una decisión de vida
///
/// Bajo escombros la batería es el reloj de arena. Todo lo que consume acorta
/// el tiempo durante el cual alguien puede encontrarte, y no todo consume
/// igual:
///
/// | Elemento   | Consumo aproximado | Alcance útil |
/// |------------|--------------------|--------------|
/// | Linterna   | Muy alto           | Sólo con línea de vista |
/// | Pantalla   | Alto               | Ninguno para el rescate |
/// | Sirena     | Medio              | Decenas de metros, atraviesa escombros |
/// | Baliza BLE | Muy bajo           | 10–30 m, atraviesa paredes |
///
/// La conclusión es clara: **la baliza de radio nunca se apaga**. Es lo que
/// menos cuesta y lo único que funciona sin línea de vista. Lo demás se va
/// retirando conforme baja la carga, empezando por lo más caro.
///
/// ## Por qué no lo decide la persona
///
/// Estos umbrales no son un ajuste. Alguien atrapado, con dolor y con miedo no
/// está en condiciones de calcular cuánta batería le queda ni de razonar qué
/// apagar. La app lo hace por su cuenta y **se lo dice**, que es distinto de
/// hacerlo a escondidas.
enum PowerTier {
  /// Batería holgada: todas las señales activas.
  full(
    label: 'Todas las señales',
    minBattery: 50,
    siren: true,
    sirenDutyCycle: 1.0,
    vibration: true,
    torch: true,
  ),

  /// Se retira la linterna, con diferencia lo que más consume y lo que menos
  /// aporta bajo escombros, donde no hay línea de vista.
  saving(
    label: 'Sin linterna',
    minBattery: 25,
    siren: true,
    sirenDutyCycle: 1.0,
    vibration: true,
    torch: false,
  ),

  /// Sirena intermitente y sin vibración. La sirena sigue porque el último
  /// tramo del rescate se hace de oído, pero suena la mitad del tiempo.
  low(
    label: 'Sirena intermitente',
    minBattery: 10,
    siren: true,
    sirenDutyCycle: 0.5,
    vibration: false,
    torch: false,
  ),

  /// Sólo la baliza de radio. A esta altura cada minuto de emisión cuenta más
  /// que cualquier otra señal.
  critical(
    label: 'Sólo baliza de radio',
    minBattery: 0,
    siren: false,
    sirenDutyCycle: 0,
    vibration: false,
    torch: false,
  );

  const PowerTier({
    required this.label,
    required this.minBattery,
    required this.siren,
    required this.sirenDutyCycle,
    required this.vibration,
    required this.torch,
  });

  /// Texto corto para mostrar en la interfaz.
  final String label;

  /// Carga mínima, en porcentaje, a la que aplica este nivel.
  final int minBattery;

  final bool siren;

  /// Fracción del tiempo que suena la sirena, de 0 a 1.
  final double sirenDutyCycle;

  final bool vibration;
  final bool torch;

  /// `true` si alguna señal está desactivada respecto al nivel máximo.
  bool get isDegraded => this != PowerTier.full;
}

/// Decide el nivel de ahorro y explica el porqué.
class PowerPolicy {
  const PowerPolicy();

  /// Histéresis para no oscilar entre niveles al rondar un umbral.
  ///
  /// Sin ella, una batería que fluctúa entre 24 % y 25 % encendería y apagaría
  /// la linterna cada pocos segundos, lo que consume más que dejarla fija y
  /// además desconcierta a quien mira el teléfono.
  static const int hysteresis = 3;

  /// Nivel que corresponde a una carga dada.
  ///
  /// [current] permite aplicar la histéresis: sólo se sube de nivel si la
  /// batería supera el umbral por [hysteresis] puntos.
  PowerTier tierFor(int? batteryPercent, {PowerTier? current}) {
    // Sin lectura de batería se asume lo mejor: apagar señales por un dato que
    // no tenemos sería peor que gastarlas de más.
    if (batteryPercent == null) return current ?? PowerTier.full;

    final battery = batteryPercent.clamp(0, 100);

    PowerTier natural = PowerTier.critical;
    for (final tier in PowerTier.values) {
      if (battery >= tier.minBattery) {
        natural = tier;
        break;
      }
    }

    if (current == null) return natural;

    // Bajar de nivel es inmediato: si la batería cae, se ahorra ya. Esperar a
    // tener margen para empezar a ahorrar sería gastar justo cuando no sobra.
    if (natural.index > current.index) return natural;

    // Subir de nivel exige superar el umbral **del nivel al que se sube**, no
    // el del actual, y hacerlo con margen.
    //
    // Comparar contra el umbral del nivel actual era el error: estando en
    // "sin linterna" (umbral 25) bastaba con llegar a 28 para saltar a "todas
    // las señales", cuyo umbral real es 50. La linterna se reencendía con la
    // batería a la mitad de lo necesario.
    if (natural.index < current.index) {
      if (battery >= natural.minBattery + hysteresis) return natural;
      return current;
    }

    return current;
  }

  /// Explica en una frase qué se apagó y por qué.
  ///
  /// Se muestra a la persona: apagarle señales sin decírselo la dejaría
  /// pensando que la app falló.
  String? explain(PowerTier tier, int? batteryPercent) {
    if (!tier.isDegraded) return null;
    final battery = batteryPercent == null ? '' : ' ($batteryPercent%)';

    return switch (tier) {
      PowerTier.full => null,
      PowerTier.saving => 'Batería media$battery: apagamos la linterna para '
          'que la señal dure más.',
      PowerTier.low => 'Batería baja$battery: la sirena suena a intervalos y '
          'la vibración está apagada.',
      PowerTier.critical => 'Batería crítica$battery: sólo queda la señal de '
          'radio, que es la que menos consume y la que llega más lejos.',
    };
  }

  /// Cuánto tiempo estimado de emisión queda, muy a grandes rasgos.
  ///
  /// No pretende ser exacto —depende del teléfono, de la temperatura y del
  /// estado de la batería— pero sí dar un orden de magnitud: no es lo mismo
  /// "quedan horas" que "quedan minutos".
  Duration? estimatedBeaconLife(int? batteryPercent, PowerTier tier) {
    if (batteryPercent == null) return null;

    // Consumo aproximado en puntos de batería por hora, medido sobre gama
    // media. Sólo la baliza BLE es prácticamente gratis.
    final drainPerHour = switch (tier) {
      PowerTier.full => 22.0,
      PowerTier.saving => 11.0,
      PowerTier.low => 6.0,
      PowerTier.critical => 2.5,
    };

    final hours = batteryPercent / drainPerHour;
    if (hours <= 0) return Duration.zero;
    return Duration(minutes: (hours * 60).round());
  }
}
