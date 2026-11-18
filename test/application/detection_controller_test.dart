// Pruebas de la confirmación de 2 minutos.
//
// Es la regla que dispara la señal de auxilio sin intervención: tras detectar
// un sismo se pregunta si la persona está bien, y el silencio cuenta como
// emergencia. Se prueba con ManualClock y con el temporizador simulado de
// testWidgets, porque el controlador usa Timer.periodic.

import 'package:baliza/application/app_settings.dart';
import 'package:baliza/application/detection_controller.dart';
import 'package:baliza/application/sos_controller.dart';
import 'package:baliza/domain/ports/clock.dart';
import 'package:baliza/domain/ports/device_services.dart';
import 'package:flutter_test/flutter_test.dart';

class _Sensores extends Fake implements SensorSource {
  @override
  bool get hasBarometer => true;
}

class _Ajustes extends Fake implements AppSettings {}

class _Notificaciones extends Fake implements NotificationService {
  int preguntas = 0;
  int cierres = 0;

  @override
  Future<void> showAreYouOkay({required Duration countdown}) async =>
      preguntas++;

  @override
  Future<void> dismissAreYouOkay() async => cierres++;
}

class _Emision extends Fake implements SosController {
  final List<({bool autoDetected, bool trapped})> llamadas = [];

  @override
  bool get isTransmitting => llamadas.isNotEmpty;

  @override
  Future<void> startSos({
    bool autoDetected = false,
    bool trapped = false,
  }) async => llamadas.add((autoDetected: autoDetected, trapped: trapped));
}

void main() {
  late ManualClock clock;
  late _Notificaciones notificaciones;
  late _Emision emision;
  late DetectionController controller;

  setUp(() {
    clock = ManualClock(DateTime.utc(2026, 11, 19, 19, 50));
    notificaciones = _Notificaciones();
    emision = _Emision();
    controller = DetectionController(
      sensors: _Sensores(),
      notifications: notificaciones,
      sos: emision,
      settings: _Ajustes(),
      clock: clock,
    );
  });

  tearDown(() => controller.dispose());

  /// Avanza el reloj y deja correr un tic del temporizador de la cuenta atrás.
  Future<void> esperar(WidgetTester tester, Duration delta) async {
    clock.advance(delta);
    await tester.pump(const Duration(seconds: 1));
  }

  group('Positivo: sin respuesta se emite auxilio', () {
    testWidgets('al detectar un evento se pregunta y arranca la cuenta atrás', (
      tester,
    ) async {
      controller.simulateDetection();
      await tester.pump();

      expect(controller.phase, DetectionPhase.awaitingResponse);
      expect(controller.remaining, const Duration(minutes: 2));
      expect(notificaciones.preguntas, 1);
      expect(emision.llamadas, isEmpty);

      await controller.stop();
    });

    testWidgets('antes de los 2 minutos todavía no emite', (tester) async {
      controller.simulateDetection();
      await esperar(tester, const Duration(minutes: 1, seconds: 58));

      expect(controller.phase, DetectionPhase.awaitingResponse);
      expect(emision.llamadas, isEmpty);

      await controller.stop();
    });

    testWidgets('a los 2 minutos sin respuesta emite como automática', (
      tester,
    ) async {
      controller.simulateDetection();
      await esperar(tester, const Duration(minutes: 2));

      expect(emision.llamadas, hasLength(1));
      expect(emision.llamadas.single.autoDetected, isTrue);
      expect(controller.phase, DetectionPhase.monitoring);
      expect(notificaciones.cierres, 1);
    });
  });

  group('Negativo: si responde, no se emite por su cuenta', () {
    testWidgets('"Estoy bien" cancela la cuenta atrás', (tester) async {
      controller.simulateDetection();
      final respuesta = controller.reportOkay();
      await tester.pump();

      expect(controller.phase, DetectionPhase.dismissed);
      expect(controller.remaining, isNull);

      await esperar(tester, const Duration(minutes: 5));
      expect(emision.llamadas, isEmpty);

      await tester.pump(const Duration(seconds: 2));
      await respuesta;
      expect(controller.phase, DetectionPhase.monitoring);
    });

    testWidgets('"Necesito ayuda" emite de inmediato como manual', (
      tester,
    ) async {
      controller.simulateDetection();
      await controller.reportNeedHelp();

      expect(emision.llamadas, hasLength(1));
      expect(emision.llamadas.single.autoDetected, isFalse);
      expect(emision.llamadas.single.trapped, isTrue);
      expect(controller.remaining, isNull);
    });
  });

  test('responder sin un evento en curso no hace nada', () async {
    await controller.reportOkay();
    expect(controller.phase, DetectionPhase.off);
    expect(notificaciones.cierres, 0);
  });

  test('la ventana de respuesta por defecto es de 2 minutos', () {
    expect(controller.responseWindow, const Duration(minutes: 2));
  });
}
