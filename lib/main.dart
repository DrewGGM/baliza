import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'application/baliza_runtime.dart';
import 'ui/app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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
