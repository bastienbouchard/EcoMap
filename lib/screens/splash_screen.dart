import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import 'login_page.dart';
import 'map_page.dart';
import 'onboarding_page.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;
  late final Animation<double> _fade;
  late final Animation<double> _textFade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 3500));

    // Zoom in → pause 2s → exit zoom
    _scale = TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.04, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 29, // ~1000ms
      ),
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 57, // ~2000ms
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 8.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 14, // ~500ms
      ),
    ]).animate(_ctrl);

    // Logo fade in → hold → fade out with exit zoom
    _fade = TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 10,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 76),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 14,
      ),
    ]).animate(_ctrl);

    // Nom apparaît quand le logo est à ~50% du zoom (~t=500ms = 14% de 3500ms)
    _textFade = TweenSequence([
      TweenSequenceItem(tween: ConstantTween<double>(0.0), weight: 14),
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 9,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 63),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 14,
      ),
    ]).animate(_ctrl);

    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 3500), () async {
      if (!mounted) return;
      final prefs = await SharedPreferences.getInstance();
      final onboardingDone = prefs.getBool('onboarding_done') ?? false;
      final isLoggedIn = AuthService.isLoggedIn;
      if (!mounted) return;

      Widget next = isLoggedIn ? const MapPage() : const LoginPage();

      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (ctx, __, ___) => onboardingDone
              ? next
              : OnboardingPage(onDone: () => Navigator.pushReplacement(
                  ctx,
                  MaterialPageRoute(builder: (_) => next),
                )),
          transitionDuration: const Duration(milliseconds: 300),
          transitionsBuilder: (_, anim, __, child) =>
              FadeTransition(opacity: anim, child: child),
        ),
      );
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AnimatedBuilder(
          animation: _ctrl,
          builder: (_, __) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Opacity(
                opacity: _textFade.value,
                child: RichText(
                  text: const TextSpan(children: [
                    TextSpan(
                      text: 'Orignal',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 32,
                        fontWeight: FontWeight.w300,
                        letterSpacing: 4,
                      ),
                    ),
                    TextSpan(
                      text: ' SCAN',
                      style: TextStyle(
                        color: Color(0xFFFF6B35),
                        fontSize: 32,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 6,
                      ),
                    ),
                  ]),
                ),
              ),
              const SizedBox(height: 28),
              Opacity(
                opacity: _fade.value,
                child: Transform.scale(
                  scale: _scale.value,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix([
                      -1,  0,  0, 0, 255,
                       0, -1,  0, 0, 255,
                       0,  0, -1, 0, 255,
                       0,  0,  0, 1,   0,
                    ]),
                    child: Image.asset('assets/logo.png', height: 260),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
