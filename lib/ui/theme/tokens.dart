import 'package:flutter/widgets.dart';

/// Paleta de Baliza.
///
/// ## Por qué todo es oscuro
///
/// No es una preferencia estética. En un teléfono con pantalla OLED —la
/// mayoría de la gama media y alta— los píxeles negros no consumen energía.
/// Cuando alguien está atrapado, cada punto de batería es tiempo de emisión, y
/// la pantalla es el segundo mayor consumidor después del radio. Una interfaz
/// clara costaría minutos de baliza.
///
/// El efecto secundario también sirve: bajo escombros y de noche, una pantalla
/// blanca a máximo brillo deslumbra y arruina la visión nocturna de quien
/// busca. Una oscura, no.
///
/// ## Reparto 60 / 30 / 10
///
/// - **60 %** [base] y [surface]: el fondo, que casi siempre es lo que se ve.
/// - **30 %** [textPrimary] y [textSecondary]: el contenido.
/// - **10 %** un único acento por contexto: [amber] cuando se busca a alguien,
///   [danger] cuando se está emitiendo auxilio. Nunca los dos a la vez.
///
/// [danger] está reservado en exclusiva al estado "emitiendo SOS". No se usa
/// para errores, ni para botones de borrar, ni para avisos. Si el rojo apareciera
/// en cualquier otro sitio dejaría de significar lo único que tiene que
/// significar.
abstract final class BalizaColors {
  // -- Base ------------------------------------------------------------------
  static const base = Color(0xFF0A0E13);
  static const surface = Color(0xFF131A22);
  static const surfaceHigh = Color(0xFF1C2530);
  static const surfaceHighest = Color(0xFF26313E);
  static const outline = Color(0xFF2E3A47);

  // -- Texto -----------------------------------------------------------------
  static const textPrimary = Color(0xFFF2F5F8);
  static const textSecondary = Color(0xB3F2F5F8); // 70 %
  static const textTertiary = Color(0x73F2F5F8); // 45 %
  static const textDisabled = Color(0x40F2F5F8); // 25 %

  // -- Acentos ---------------------------------------------------------------

  /// Ámbar: modo rescate. Es el color de quien busca.
  static const amber = Color(0xFFFF9838);
  static const amberSoft = Color(0x1AFF9838);
  static const amberBorder = Color(0x40FF9838);

  /// Rojo: exclusivo del estado "emitiendo auxilio".
  static const danger = Color(0xFFFF4438);
  static const dangerSoft = Color(0x1AFF4438);
  static const dangerBorder = Color(0x40FF4438);

  /// Verde: a salvo, confirmado, correcto.
  static const safe = Color(0xFF35D07F);
  static const safeSoft = Color(0x1A35D07F);

  /// Azul: información neutra y equipos de rescate ajenos.
  static const info = Color(0xFF4DA3FF);
  static const infoSoft = Color(0x1A4DA3FF);

  /// Amarillo: advertencias que no son emergencia (batería baja, permisos).
  static const warning = Color(0xFFFFC048);
  static const warningSoft = Color(0x1AFFC048);

  /// Sombra tintada con el fondo, nunca gris ni negro puro.
  static const shadow = Color(0x8005080C);
}

/// Escala de espaciado sobre retícula de 8 puntos.
///
/// Sólo estos valores. Si un diseño necesita 13 px, el diseño está mal.
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 48;
  static const double huge = 64;
}

/// Radios de esquina.
abstract final class Radii {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double pill = 999;
}

/// Escala tipográfica: cuatro tamaños, dos pesos. Ni uno más.
///
/// Los números grandes —distancias, cuentas atrás, códigos de baliza— usan
/// cifras tabulares para que no bailen al actualizarse cada segundo.
abstract final class BalizaText {
  // Fuente del sistema: siempre disponible, sin descarga ni fallo de red.
  static const String? _family = null;

  static const display = TextStyle(
    fontFamily: _family,
    fontSize: 34,
    height: 1.15,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.5,
    color: BalizaColors.textPrimary,
  );

  static const title = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    height: 1.25,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.2,
    color: BalizaColors.textPrimary,
  );

  static const body = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w400,
    color: BalizaColors.textPrimary,
  );

  static const bodyStrong = TextStyle(
    fontFamily: _family,
    fontSize: 16,
    height: 1.4,
    fontWeight: FontWeight.w700,
    color: BalizaColors.textPrimary,
  );

  static const caption = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w400,
    color: BalizaColors.textSecondary,
  );

  static const captionStrong = TextStyle(
    fontFamily: _family,
    fontSize: 13,
    height: 1.35,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.4,
    color: BalizaColors.textSecondary,
  );

  /// Cifras que cambian en vivo, con ancho fijo por dígito.
  static const numeric = TextStyle(
    fontFamily: _family,
    fontSize: 34,
    height: 1.05,
    fontWeight: FontWeight.w700,
    letterSpacing: -1,
    fontFeatures: [FontFeature.tabularFigures()],
    color: BalizaColors.textPrimary,
  );

  static const numericSmall = TextStyle(
    fontFamily: _family,
    fontSize: 22,
    height: 1.1,
    fontWeight: FontWeight.w700,
    fontFeatures: [FontFeature.tabularFigures()],
    color: BalizaColors.textPrimary,
  );
}

/// Medidas mínimas de accesibilidad.
abstract final class Touch {
  /// Lado mínimo de cualquier elemento pulsable.
  ///
  /// Se sube de los 44 pt habituales a 56: quien usa esta app puede estar
  /// herido, a oscuras, con la pantalla rota o con las manos temblando.
  static const double minTarget = 56;

  /// Lado del botón principal de auxilio.
  static const double sosButton = 208;
}

/// Duraciones de animación.
///
/// Cortas a propósito. La animación aquí sirve para confirmar que el sistema
/// respondió, no para lucirse; una transición larga en una emergencia es una
/// espera.
abstract final class Motion {
  static const fast = Duration(milliseconds: 120);
  static const normal = Duration(milliseconds: 220);
  static const slow = Duration(milliseconds: 400);

  /// Latido de la baliza activa: un ciclo por segundo y medio, cercano al
  /// pulso en reposo. Comunica "esto sigue vivo" sin agitar.
  static const pulse = Duration(milliseconds: 1500);
}
