import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';
import 'permissions_screen.dart';

/// Introducción y solicitud de permisos.
///
/// ## Se explica antes de pedir
///
/// Cada permiso se justifica con la consecuencia concreta de negarlo, no con
/// la fórmula legal. "Android exige el permiso de ubicación para buscar por
/// Bluetooth; Baliza no usa tu GPS ni guarda dónde estás" resuelve la
/// desconfianza que genera pedir ubicación en una app que presume de
/// funcionar sin GPS.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  int _index = 0;

  static const _slides = <_Slide>[
    _Slide(
      icon: Icons.wifi_tethering,
      title: 'Tu señal cuando no hay red',
      body: 'Tras un sismo lo primero que cae es la señal celular. Baliza usa '
          'Bluetooth de baja energía para que tu teléfono siga diciendo '
          '"estoy aquí" aunque no haya internet, cobertura ni GPS.',
    ),
    _Slide(
      icon: Icons.hearing,
      title: 'Que te encuentren',
      body: 'Al pedir ayuda, tu teléfono emite una señal de radio, hace sonar '
          'una sirena y destella la linterna. Quien te busque verá qué tan '
          'cerca está y si se está acercando.',
    ),
    _Slide(
      icon: Icons.medical_information_outlined,
      title: 'Con lo que hace falta saber',
      body: 'Tu grupo sanguíneo, tus alergias y tus condiciones médicas viajan '
          'dentro de la señal, para que quien te atienda no tenga que '
          'adivinar. Sin tu nombre ni tu documento: nadie puede '
          'identificarte con eso.',
    ),
    _Slide(
      icon: Icons.crisis_alert,
      title: 'Aunque no puedas responder',
      body: 'Si activas la vigilancia, Baliza reconoce un sismo por los '
          'sensores del teléfono y te pregunta si estás bien. Si no '
          'contestas en dos minutos, pide ayuda por ti.',
    ),
  ];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await RuntimeScope.of(context).settings.setOnboarded(true);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _slides.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: <Widget>[
                  ..._slides.map((s) => _SlideView(slide: s)),
                  const PermissionsScreen(embedded: true),
                ],
              ),
            ),

            // Indicador de página.
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List<Widget>.generate(_slides.length + 1, (i) {
                final active = i == _index;
                return AnimatedContainer(
                  duration: Motion.normal,
                  margin: const EdgeInsets.symmetric(horizontal: Space.xs),
                  width: active ? 24 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: active
                        ? BalizaColors.amber
                        : BalizaColors.surfaceHighest,
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                );
              }),
            ),
            const SizedBox(height: Space.xl),

            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                0,
                Space.xl,
                Space.xl,
              ),
              child: Row(
                children: <Widget>[
                  if (!isLast)
                    Expanded(
                      child: TextButton(
                        onPressed: _finish,
                        child: const Text('Omitir'),
                      ),
                    ),
                  Expanded(
                    flex: 2,
                    child: FilledButton(
                      onPressed: isLast
                          ? _finish
                          : () => _pages.nextPage(
                                duration: Motion.normal,
                                curve: Curves.easeOut,
                              ),
                      child: Text(isLast ? 'Empezar' : 'Siguiente'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;
}

class _SlideView extends StatelessWidget {
  const _SlideView({required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Space.xxl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Stack(
            alignment: Alignment.center,
            children: <Widget>[
              const PulseRings(size: 220, color: BalizaColors.amber),
              Container(
                width: 108,
                height: 108,
                decoration: BoxDecoration(
                  color: BalizaColors.amberSoft,
                  shape: BoxShape.circle,
                  border: Border.all(color: BalizaColors.amberBorder),
                ),
                child: Icon(slide.icon, size: 46, color: BalizaColors.amber),
              ),
            ],
          ),
          const SizedBox(height: Space.xxl),
          Text(slide.title, style: BalizaText.display, textAlign: TextAlign.center),
          const SizedBox(height: Space.lg),
          Text(
            slide.body,
            style: BalizaText.body.copyWith(color: BalizaColors.textSecondary),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
