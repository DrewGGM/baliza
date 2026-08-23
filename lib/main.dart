import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'application/baliza_runtime.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Abre el canal de vuelta entre el aislado del servicio en primer plano y
  // este, el principal.
  //
  // Sin esta llamada el servicio arranca, la notificación se muestra y el
  // botón "Detener" responde al pulsarlo... pero el mensaje no llega a
  // ninguna parte, así que la sirena y la vibración siguen. Es un fallo
  // silencioso: no hay excepción, ni error en el registro, sólo un botón que
  // aparenta funcionar y no hace nada.
  FlutterForegroundTask.initCommunicationPort();

  // La orientación se fija en vertical a propósito. Quien usa esta app puede
  // estar tumbado, atrapado o con el teléfono de lado; una interfaz que rota
  // sola en ese contexto desorienta y obliga a recolocar el aparato.
  await SystemChrome.setPreferredOrientations(<DeviceOrientation>[
    DeviceOrientation.portraitUp,
  ]);

  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final runtime = await BalizaRuntime.boot();
  runApp(BalizaApp(runtime: runtime));
}
