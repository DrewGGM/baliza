import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/ports/device_services.dart';
import '../app.dart';
import '../theme/tokens.dart';
import '../widgets/common.dart';

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
  final Set<AppPermission> _granted = <AppPermission>{};
  bool _requesting = false;

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

  Future<void> _requestAll() async {
    setState(() => _requesting = true);
    final permissions = RuntimeScope.of(context).permissions;

    for (final p in <AppPermission>[
      AppPermission.bluetooth,
      AppPermission.location,
      AppPermission.notifications,
    ]) {
      final ok = await permissions.request(p);
      if (ok) _granted.add(p);
    }

    if (mounted) setState(() => _requesting = false);
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
                  _PermissionsPage(
                    granted: _granted,
                    requesting: _requesting,
                    onRequest: _requestAll,
                  ),
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

class _PermissionsPage extends StatelessWidget {
  const _PermissionsPage({
    required this.granted,
    required this.requesting,
    required this.onRequest,
  });

  final Set<AppPermission> granted;
  final bool requesting;
  final Future<void> Function() onRequest;

  static const _explanations = <AppPermission, String>{
    AppPermission.bluetooth:
        'Es el canal por el que emites y detectas. Sin esto la app no puede '
            'hacer nada.',
    AppPermission.location:
        'Android lo exige para buscar por Bluetooth. Baliza no usa tu GPS ni '
            'guarda dónde estás.',
    AppPermission.notifications:
        'Para poder preguntarte si estás bien y que respondas sin desbloquear '
            'el teléfono.',
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.xl,
        vertical: Space.xl,
      ),
      children: <Widget>[
        Text('Permisos', style: BalizaText.display),
        const SizedBox(height: Space.sm),
        Text(
          'Baliza necesita tres cosas. Te explicamos para qué sirve cada una.',
          style: BalizaText.body.copyWith(color: BalizaColors.textSecondary),
        ),
        const SizedBox(height: Space.xl),
        ..._explanations.entries.map((entry) {
          final ok = granted.contains(entry.key);
          return Padding(
            padding: const EdgeInsets.only(bottom: Space.md),
            child: BalizaCard(
              padding: const EdgeInsets.all(Space.lg),
              borderColor:
                  ok ? BalizaColors.safe.withValues(alpha: 0.4) : null,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(
                    ok ? Icons.check_circle : Icons.radio_button_unchecked,
                    color:
                        ok ? BalizaColors.safe : BalizaColors.textTertiary,
                    size: 22,
                  ),
                  const SizedBox(width: Space.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(entry.key.label, style: BalizaText.bodyStrong),
                        const SizedBox(height: Space.xs),
                        Text(entry.value, style: BalizaText.caption),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
        const SizedBox(height: Space.lg),
        FilledButton.icon(
          onPressed: requesting ? null : () => unawaited(onRequest()),
          icon: requesting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.lock_open),
          label: Text(requesting ? 'Solicitando…' : 'Conceder permisos'),
        ),
        const SizedBox(height: Space.md),
        Text(
          'Puedes empezar sin concederlos y hacerlo más tarde, pero la app no '
          'podrá emitir ni detectar hasta que lo hagas.',
          style: BalizaText.caption,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
