import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class OnboardingPage extends StatefulWidget {
  final VoidCallback onDone;
  const OnboardingPage({super.key, required this.onDone});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final _ctrl = PageController();
  int _page = 0;

  static const _pages = [
    _PageData(
      emoji: '__logo__',
      title: 'Bienvenue dans OrignalScan',
      subtitle: 'Algorithmes IA + données écoforestières officielles du MRNF — l\'outil de chasse à l\'orignal le plus avancé au Québec.',
      items: [],
    ),
    _PageData(
      emoji: '🔥',
      title: 'Détecte l\'habitat',
      subtitle: 'Algorithmes IA qui analysent le terrain pour toi.',
      items: [
        ('🔥', 'Points chauds', 'Les meilleurs habitats orignal dans la zone visible'),
        ('🗺', 'Parcours optimisé', 'Itinéraire calculé selon le vent et le terrain'),
      ],
    ),
    _PageData(
      emoji: '__tower__',
      title: 'Trouve les meilleurs spots',
      subtitle: 'Détection par algorithme IA — basé sur les données écoforestières du MRNF.',
      items: [
        ('__tower__', 'Postes d\'affût — IA', 'Corridors naturels où l\'orignal est forcé de passer'),
        ('__cube__', 'Salines — IA', 'Zones humides idéales pour installer une saline'),
      ],
    ),
    _PageData(
      emoji: '__map__',
      title: 'Maîtrise le territoire',
      subtitle: 'Toutes les données officielles dans ta poche.',
      items: [
        ('__map__', 'Carte écoforestière', 'Peuplement, âge et drainage par secteur'),
        ('📐', 'Terres privées', 'Limites de lots cadastraux en temps réel'),
      ],
    ),
    _PageData(
      emoji: '👥',
      title: 'Chasse en équipe',
      subtitle: 'Reste connecté avec ton équipe en temps réel.',
      items: [
        ('__compass__', 'Positions GPS en direct', 'Vois où est chaque chasseur sur la carte'),
        ('💬', 'Clavardage & photos', 'Échange messages et photos avec ton équipe'),
        ('__pin__', 'Traces & observations', 'Partage automatique en temps réel'),
      ],
    ),
  ];

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('onboarding_done', true);
    widget.onDone();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _ctrl.nextPage(
          duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finish();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _page == _pages.length - 1;
    return Scaffold(
      backgroundColor: const Color(0xFF111111),
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 48,
              child: !isLast
                  ? Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: _finish,
                        child: const Text('Passer',
                            style: TextStyle(color: Colors.white38, fontSize: 13)),
                      ),
                    )
                  : null,
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                onPageChanged: (i) => setState(() => _page = i),
                itemCount: _pages.length,
                itemBuilder: (_, i) => _PageContent(data: _pages[i]),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_pages.length, (i) {
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: _page == i ? 20 : 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: _page == i
                        ? const Color(0xFFFF6B35)
                        : Colors.white24,
                    borderRadius: BorderRadius.circular(4),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6B35),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 4,
                  ),
                  onPressed: _next,
                  child: Text(
                    isLast ? 'Commencer' : 'Suivant',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}

class _PageData {
  final String emoji;
  final String title;
  final String subtitle;
  final List<(String, String, String)> items;
  const _PageData(
      {required this.emoji,
      required this.title,
      required this.subtitle,
      required this.items});
}

class _PageContent extends StatelessWidget {
  final _PageData data;
  const _PageContent({super.key, required this.data});

  Widget _emojiWidget(String emoji, double size, {double? logoSize}) {
    if (emoji == '__tower__') return _TowerIcon(size: size);
    if (emoji == '__cube__') return _CubeIcon(size: size);
    if (emoji == '__map__') return _MapIcon(size: size);
    if (emoji == '__pin__') return _PinIcon(size: size);
    if (emoji == '__compass__') return _CompassIcon(size: size);
    if (emoji == '__logo__') {
      final s = logoSize ?? size * 3.0;
      return ColorFiltered(
        colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        child: Image.asset('assets/logo.png', width: s, height: s),
      );
    }
    return Text(emoji, style: TextStyle(fontSize: size));
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final logoSize = (constraints.maxHeight * 0.38).clamp(140.0, 260.0);
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _emojiWidget(data.emoji, 72, logoSize: logoSize),
          const SizedBox(height: 24),
          Text(data.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Text(data.subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white60, fontSize: 14, height: 1.5)),
              if (data.items.isNotEmpty) ...[
                const SizedBox(height: 32),
                ...data.items.map((item) => Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Row(children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF6B35).withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: const Color(0xFFFF6B35).withOpacity(0.3)),
                          ),
                          child: Center(child: _emojiWidget(item.$1, 24)),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.$2,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15)),
                                const SizedBox(height: 2),
                                Text(item.$3,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 12)),
                              ]),
                        ),
                      ]),
                    )),
              ],
            ],
          ),
        ),
      ),
    );
    });
  }
}

class _TowerIcon extends StatelessWidget {
  final double size;
  const _TowerIcon({this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _TowerPainter()),
      );
}

class _TowerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (size.width * 0.07).clamp(1.5, 3.5)
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final w = size.width;
    final h = size.height;

    // Cabane au sommet
    final cabin = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, h * 0.04, w * 0.56, h * 0.26),
      const Radius.circular(2),
    );
    canvas.drawRRect(cabin, p);

    // Toit (triangle)
    final roof = Path()
      ..moveTo(w * 0.15, h * 0.04)
      ..lineTo(w * 0.50, h * (-0.04).clamp(-h, 0))
      ..lineTo(w * 0.85, h * 0.04);
    canvas.drawPath(roof, p);

    // Plateforme horizontale
    canvas.drawLine(Offset(w * 0.06, h * 0.38), Offset(w * 0.94, h * 0.38), p);

    // Jambe gauche
    canvas.drawLine(Offset(w * 0.25, h * 0.38), Offset(w * 0.10, h * 0.97), p);
    // Jambe droite
    canvas.drawLine(Offset(w * 0.75, h * 0.38), Offset(w * 0.90, h * 0.97), p);

    // Croix de renfort
    canvas.drawLine(Offset(w * 0.25, h * 0.38), Offset(w * 0.90, h * 0.97), p);
    canvas.drawLine(Offset(w * 0.75, h * 0.38), Offset(w * 0.10, h * 0.97), p);

    // Échelle centrale
    canvas.drawLine(Offset(w * 0.44, h * 0.38), Offset(w * 0.44, h * 0.97), p);
    canvas.drawLine(Offset(w * 0.56, h * 0.38), Offset(w * 0.56, h * 0.97), p);
    for (double y = 0.50; y < 0.95; y += 0.14) {
      canvas.drawLine(Offset(w * 0.44, h * y), Offset(w * 0.56, h * y), p);
    }
  }

  @override
  bool shouldRepaint(_TowerPainter old) => false;
}

class _CubeIcon extends StatelessWidget {
  final double size;
  const _CubeIcon({this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CubePainter()),
      );
}

class _CubePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // 7 sommets du cube isométrique
    final topC  = Offset(w * 0.50, h * 0.06);
    final midL  = Offset(w * 0.05, h * 0.30);
    final midR  = Offset(w * 0.95, h * 0.30);
    final ctr   = Offset(w * 0.50, h * 0.54);
    final botL  = Offset(w * 0.05, h * 0.78);
    final botR  = Offset(w * 0.95, h * 0.78);
    final botC  = Offset(w * 0.50, h * 0.97);

    Path face(List<Offset> pts) {
      final p = Path()..moveTo(pts[0].dx, pts[0].dy);
      for (final pt in pts.skip(1)) { p.lineTo(pt.dx, pt.dy); }
      return p..close();
    }

    final top   = face([topC, midR, ctr, midL]);
    final left  = face([midL, ctr, botC, botL]);
    final right = face([ctr, midR, botR, botC]);

    // Faces remplies — dégradé de luminosité pour effet 3D
    canvas.drawPath(top,   Paint()..color = Colors.white.withOpacity(0.95)..style = PaintingStyle.fill);
    canvas.drawPath(left,  Paint()..color = Colors.white.withOpacity(0.50)..style = PaintingStyle.fill);
    canvas.drawPath(right, Paint()..color = Colors.white.withOpacity(0.28)..style = PaintingStyle.fill);

    // Contour
    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = (w * 0.06).clamp(1.0, 3.5)
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(top,   stroke);
    canvas.drawPath(left,  stroke);
    canvas.drawPath(right, stroke);
  }

  @override
  bool shouldRepaint(_CubePainter old) => false;
}

class _MapIcon extends StatelessWidget {
  final double size;
  const _MapIcon({this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _MapPainter()),
      );
}

class _MapPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sw = (w * 0.07).clamp(1.5, 4.0);

    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Cadre de la carte
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.05, h * 0.05, w * 0.90, h * 0.90),
        Radius.circular(w * 0.10),
      ),
      p,
    );

    // Ligne de frontière 1 (ondulée)
    final l1 = Path()
      ..moveTo(w * 0.05, h * 0.37)
      ..cubicTo(w * 0.28, h * 0.25, w * 0.45, h * 0.50, w * 0.65, h * 0.33)
      ..cubicTo(w * 0.80, h * 0.22, w * 0.90, h * 0.37, w * 0.95, h * 0.37);
    canvas.drawPath(l1, p);

    // Ligne de frontière 2 (ondulée)
    final l2 = Path()
      ..moveTo(w * 0.05, h * 0.63)
      ..cubicTo(w * 0.22, h * 0.72, w * 0.42, h * 0.55, w * 0.60, h * 0.65)
      ..cubicTo(w * 0.76, h * 0.73, w * 0.88, h * 0.60, w * 0.95, h * 0.63);
    canvas.drawPath(l2, p);

    // Marqueur de position (cercle + point central)
    final pin = Offset(w * 0.71, h * 0.49);
    canvas.drawCircle(pin, w * 0.11, p);
    canvas.drawCircle(pin, w * 0.035,
        Paint()..color = Colors.white..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_MapPainter old) => false;
}

class _PinIcon extends StatelessWidget {
  final double size;
  const _PinIcon({this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _PinPainter()),
      );
}

class _PinPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final sw = (w * 0.07).clamp(1.5, 4.0);

    // Tête de la punaise (cercle rempli)
    final headR = w * 0.32;
    final headC = Offset(w * 0.50, h * 0.36);
    canvas.drawCircle(headC, headR,
        Paint()..color = Colors.white..style = PaintingStyle.fill);
    // Contour de la tête
    canvas.drawCircle(headC, headR,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = sw);

    // Pointe (triangle vers le bas)
    final tip = Path()
      ..moveTo(w * 0.28, h * 0.58)
      ..lineTo(w * 0.72, h * 0.58)
      ..lineTo(w * 0.50, h * 0.94)
      ..close();
    canvas.drawPath(tip,
        Paint()..color = Colors.white..style = PaintingStyle.fill);

    // Point central noir pour effet punaise
    canvas.drawCircle(headC, w * 0.12,
        Paint()..color = const Color(0xFFFF6B35)..style = PaintingStyle.fill);
  }

  @override
  bool shouldRepaint(_PinPainter old) => false;
}

class _CompassIcon extends StatelessWidget {
  final double size;
  const _CompassIcon({this.size = 24});

  @override
  Widget build(BuildContext context) => SizedBox(
        width: size,
        height: size,
        child: CustomPaint(painter: _CompassPainter()),
      );
}

class _CompassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final cy = h / 2;
    final r = w * 0.44;
    final sw = (w * 0.07).clamp(1.5, 4.0);

    final stroke = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw
      ..strokeCap = StrokeCap.round;

    // Cercle extérieur
    canvas.drawCircle(Offset(cx, cy), r, stroke);

    // Aiguille Nord (blanche — pointe vers le haut)
    final north = Path()
      ..moveTo(cx, cy - r * 0.72)
      ..lineTo(cx - r * 0.18, cy + r * 0.10)
      ..lineTo(cx, cy)
      ..close();
    canvas.drawPath(north,
        Paint()..color = Colors.white..style = PaintingStyle.fill);

    // Aiguille Sud (orange — pointe vers le bas)
    final south = Path()
      ..moveTo(cx, cy + r * 0.72)
      ..lineTo(cx + r * 0.18, cy - r * 0.10)
      ..lineTo(cx, cy)
      ..close();
    canvas.drawPath(south,
        Paint()..color = const Color(0xFFFF6B35)..style = PaintingStyle.fill);

    // Point central
    canvas.drawCircle(Offset(cx, cy), w * 0.06,
        Paint()..color = Colors.white..style = PaintingStyle.fill);

    // Marqueurs cardinaux N / S / E / O
    final tick = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = sw * 0.8
      ..strokeCap = StrokeCap.round;
    for (int i = 0; i < 4; i++) {
      final angle = i * 3.14159 / 2;
      final x1 = cx + (r - w * 0.10) * sin(angle);
      final y1 = cy - (r - w * 0.10) * cos(angle);
      final x2 = cx + r * sin(angle);
      final y2 = cy - r * cos(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), tick);
    }
  }

  @override
  bool shouldRepaint(_CompassPainter old) => false;
}
