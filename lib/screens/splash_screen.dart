import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'login_page.dart';
import 'map_page.dart';

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

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 2000));

    // Zoom in from tiny to huge — 3 phases
    _scale = TweenSequence([
      // Phase 1 : minuscule → taille normale
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.04, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 50,
      ),
      // Phase 2 : pause brève
      TweenSequenceItem(
        tween: ConstantTween<double>(1.0),
        weight: 10,
      ),
      // Phase 3 : continue à zoomer et remplit l'écran
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 8.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_ctrl);

    // Fade in rapide, puis disparaît lors du grand zoom
    _fade = TweenSequence([
      TweenSequenceItem(
        tween: Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 25,
      ),
      TweenSequenceItem(tween: ConstantTween<double>(1.0), weight: 35),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 40,
      ),
    ]).animate(_ctrl);

    _ctrl.forward();

    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      final isLoggedIn = AuthService.isLoggedIn;
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (_, __, ___) =>
              isLoggedIn ? const MapPage() : const LoginPage(),
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
          builder: (_, __) => Opacity(
            opacity: _fade.value,
            child: Transform.scale(
              scale: _scale.value,
              child: Image.asset('assets/logo.png', height: 260),
            ),
          ),
        ),
      ),
    );
  }
}
