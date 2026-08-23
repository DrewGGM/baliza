import 'package:flutter/material.dart';

import '../application/baliza_runtime.dart';
import 'screens/home_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/rescue_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/app_theme.dart';
import 'theme/tokens.dart';

/// Inyecta el runtime en el árbol de widgets.
///
/// Se usa un [InheritedWidget] a mano en lugar de un paquete de inyección: la
/// app tiene un único grafo de objetos que vive toda la sesión, y añadir una
/// dependencia externa para eso sería complicar sin ganar nada.
class RuntimeScope extends InheritedWidget {
  const RuntimeScope({
    required this.runtime,
    required super.child,
    super.key,
  });

  final BalizaRuntime runtime;

  static BalizaRuntime of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<RuntimeScope>();
    assert(scope != null, 'No hay RuntimeScope por encima de este widget');
    return scope!.runtime;
  }

  @override
  bool updateShouldNotify(RuntimeScope oldWidget) =>
      oldWidget.runtime != runtime;
}

class BalizaApp extends StatelessWidget {
  const BalizaApp({required this.runtime, super.key});

  final BalizaRuntime runtime;

  @override
  Widget build(BuildContext context) {
    return RuntimeScope(
      runtime: runtime,
      child: MaterialApp(
        title: 'Baliza',
        debugShowCheckedModeBanner: false,
        theme: BalizaTheme.build(),
        home: AnimatedBuilder(
          animation: runtime.settings,
          builder: (context, _) {
            return runtime.settings.onboarded
                ? const AppShell()
                : const OnboardingScreen();
          },
        ),
      ),
    );
  }
}

/// Armazón con la navegación principal.
///
/// Sólo tres destinos. La tentación de añadir pestañas es fuerte —historial,
/// mapa, estadísticas— y hay que resistirla: cada destino de más es una
/// decisión que alguien tiene que tomar en el peor momento de su vida.
class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const _destinations = <NavigationDestination>[
    NavigationDestination(
      icon: Icon(Icons.emergency_share_outlined),
      selectedIcon: Icon(Icons.emergency_share),
      label: 'Auxilio',
    ),
    NavigationDestination(
      icon: Icon(Icons.travel_explore_outlined),
      selectedIcon: Icon(Icons.travel_explore),
      label: 'Buscar',
    ),
    NavigationDestination(
      icon: Icon(Icons.tune_outlined),
      selectedIcon: Icon(Icons.tune),
      label: 'Ajustes',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final runtime = RuntimeScope.of(context);

    return AnimatedBuilder(
      animation: runtime.sos,
      builder: (context, _) {
        // Mientras se emite auxilio, la barra de navegación se tiñe de rojo:
        // el estado tiene que ser evidente desde cualquier pantalla.
        final transmitting = runtime.sos.isTransmitting;

        return Scaffold(
          body: IndexedStack(
            index: _index,
            children: const <Widget>[
              HomeScreen(),
              RescueScreen(),
              SettingsScreen(),
            ],
          ),
          bottomNavigationBar: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                  color: transmitting
                      ? BalizaColors.dangerBorder
                      : BalizaColors.outline,
                ),
              ),
            ),
            child: NavigationBar(
              selectedIndex: _index,
              onDestinationSelected: (i) => setState(() => _index = i),
              destinations: _destinations,
              indicatorColor: transmitting
                  ? BalizaColors.dangerSoft
                  : BalizaColors.amberSoft,
            ),
          ),
        );
      },
    );
  }
}
