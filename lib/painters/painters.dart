import 'dart:math';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';

class CrosshairPainter extends CustomPainter {
  const CrosshairPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFFF6B35)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = const Color(0xFFFF6B35).withOpacity(0.3)
      ..style = PaintingStyle.fill;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 3.5;
    final gap = radius + 4;
    final len = size.width / 2 - 2;

    canvas.drawCircle(center, radius, fillPaint);
    canvas.drawCircle(center, radius, paint);
    canvas.drawLine(Offset(center.dx, center.dy - gap), Offset(center.dx, center.dy - len), paint);
    canvas.drawLine(Offset(center.dx, center.dy + gap), Offset(center.dx, center.dy + len), paint);
    canvas.drawLine(Offset(center.dx - gap, center.dy), Offset(center.dx - len, center.dy), paint);
    canvas.drawLine(Offset(center.dx + gap, center.dy), Offset(center.dx + len, center.dy), paint);
    canvas.drawCircle(center, 3, Paint()..color = const Color(0xFFFF6B35));
  }

  @override
  bool shouldRepaint(CrosshairPainter oldDelegate) => false;
}

class CompassPainter extends CustomPainter {
  final double rotation;
  final double targetBearing;
  final double? windDeg;

  const CompassPainter({required this.rotation, required this.targetBearing, this.windDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 10;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(rotation);

    canvas.drawCircle(Offset.zero, radius,
        Paint()..color = const Color(0xFF2D2D2D)..style = PaintingStyle.fill);
    canvas.drawCircle(Offset.zero, radius,
        Paint()..color = const Color(0xFFFF6B35)..strokeWidth = 3..style = PaintingStyle.stroke);

    // Zone verte ±60° autour de la source du vent — pointe de tarte depuis le centre
    if (windDeg != null) {
      const span = 120.0 * pi / 180;
      final windCenter = windDeg! * pi / 180 - pi / 2;
      final arcStart = windCenter - span / 2;
      final piePath = ui.Path()
        ..moveTo(0, 0)
        ..arcTo(Rect.fromCircle(center: Offset.zero, radius: radius - 2), arcStart, span, false)
        ..close();
      canvas.drawPath(piePath, Paint()..color = const Color(0xFF4CAF50).withOpacity(0.30)..style = PaintingStyle.fill);
      canvas.drawPath(piePath, Paint()
        ..color = const Color(0xFF4CAF50).withOpacity(0.70)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2);

      // Flèches pointant de l'arc vers le centre (vent qui vient vers nous)
      canvas.save();
      canvas.rotate(windDeg! * pi / 180);
      final arrowFill = Paint()..color = const Color(0xFF4CAF50).withOpacity(0.90)..style = PaintingStyle.fill;
      final arrowStroke = Paint()
        ..color = const Color(0xFF4CAF50).withOpacity(0.90)
        ..strokeWidth = 1.5..strokeCap = StrokeCap.round..style = PaintingStyle.stroke;
      for (final p in [radius * 0.75, radius * 0.48, radius * 0.22]) {
        canvas.drawLine(Offset(0, -(p + 10)), Offset(0, -(p - 10) + 9), arrowStroke);
        final head = ui.Path()
          ..moveTo(0, -(p - 10))
          ..lineTo(-5.0, -(p - 10) + 9)
          ..lineTo(5.0, -(p - 10) + 9)
          ..close();
        canvas.drawPath(head, arrowFill);
      }
      canvas.restore();
    }

    final textPainter = TextPainter(textAlign: TextAlign.center, textDirection: TextDirection.ltr);
    final directions = ['N', 'E', 'S', 'O'];
    final colors = [const Color(0xFFFF6B35), Colors.white70, Colors.white70, Colors.white70];
    for (int i = 0; i < 4; i++) {
      final angle = i * pi / 2;
      textPainter.text = TextSpan(
        text: directions[i],
        style: TextStyle(color: colors[i], fontSize: i == 0 ? 32 : 24, fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal),
      );
      textPainter.layout();
      final x = (radius - 25) * sin(angle);
      final y = -(radius - 25) * cos(angle);
      textPainter.paint(canvas, Offset(x - textPainter.width / 2, y - textPainter.height / 2));
    }

    final tickPaint = Paint()..color = Colors.white30..strokeWidth = 2;
    for (int i = 0; i < 12; i++) {
      final angle = i * pi / 6;
      if (i % 3 != 0) {
        canvas.drawLine(
          Offset((radius - 15) * sin(angle), -(radius - 15) * cos(angle)),
          Offset((radius - 5) * sin(angle), -(radius - 5) * cos(angle)),
          tickPaint,
        );
      }
    }
    canvas.restore();

    // Triangle fixe en haut — direction du téléphone (toujours à 12h sur l'écran)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final phoneMark = ui.Path()
      ..moveTo(0, -(radius - 2))
      ..lineTo(-14, -(radius - 28))
      ..lineTo(14, -(radius - 28))
      ..close();
    canvas.drawPath(phoneMark, Paint()..color = Colors.white..style = PaintingStyle.fill);
    canvas.drawPath(phoneMark, Paint()..color = const Color(0xFFFF6B35)..strokeWidth = 2.5..style = PaintingStyle.stroke);
    canvas.restore();

    // Flèche de navigation — pointe vers la destination (relèvement relatif)
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(targetBearing * pi / 180 + rotation);
    canvas.drawLine(
      const Offset(0, 18),
      Offset(0, -(radius - 35)),
      Paint()..color = const Color(0xFFFF6B35).withOpacity(0.5)..strokeWidth = 3..strokeCap = StrokeCap.round,
    );
    final arrowPaint = Paint()..color = const Color(0xFFFF6B35)..style = PaintingStyle.fill;
    final arrowPath = ui.Path()
      ..moveTo(0, -(radius - 20))
      ..lineTo(-14, -(radius - 48))
      ..lineTo(0, -(radius - 40))
      ..lineTo(14, -(radius - 48))
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.drawPath(arrowPath, Paint()..color = Colors.white..strokeWidth = 1.5..style = PaintingStyle.stroke);
    canvas.restore();

    canvas.drawCircle(center, 6, Paint()..color = const Color(0xFFFF6B35)..style = PaintingStyle.fill);
    canvas.drawCircle(center, 6, Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke);
  }

  @override
  bool shouldRepaint(CompassPainter oldDelegate) =>
      oldDelegate.rotation != rotation ||
      oldDelegate.targetBearing != targetBearing ||
      oldDelegate.windDeg != windDeg;
}

// ── ICÔNES OBSERVATIONS ───────────────────────────────────────────────────────

class MooseTrackPainter extends CustomPainter {
  const MooseTrackPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFFD4A76A)..style = PaintingStyle.fill;
    final w = size.width; final h = size.height;

    // Sabot gauche — large et arrondi en haut, effilé vers le bas
    final left = Path()
      ..moveTo(w * .42, h * .06)
      ..cubicTo(w * .38, h * .01, w * .20, h * .00, w * .08, h * .11)
      ..cubicTo(w * .01, h * .20, w * .02, h * .42, w * .07, h * .58)
      ..cubicTo(w * .13, h * .74, w * .24, h * .80, w * .31, h * .79)
      ..cubicTo(w * .39, h * .79, w * .44, h * .68, w * .44, h * .54)
      ..cubicTo(w * .44, h * .35, w * .44, h * .13, w * .42, h * .06)
      ..close();

    // Sabot droit — miroir
    final right = Path()
      ..moveTo(w * .58, h * .06)
      ..cubicTo(w * .62, h * .01, w * .80, h * .00, w * .92, h * .11)
      ..cubicTo(w * .99, h * .20, w * .98, h * .42, w * .93, h * .58)
      ..cubicTo(w * .87, h * .74, w * .76, h * .80, w * .69, h * .79)
      ..cubicTo(w * .61, h * .79, w * .56, h * .68, w * .56, h * .54)
      ..cubicTo(w * .56, h * .35, w * .56, h * .13, w * .58, h * .06)
      ..close();

    canvas.drawPath(left, p);
    canvas.drawPath(right, p);

    // Ergots (dew claws) — deux petits triangles arrondis sous les sabots
    final dewR = Rect.fromCenter(center: Offset(w * .19, h * .90), width: w * .18, height: h * .12);
    final dewL = Rect.fromCenter(center: Offset(w * .81, h * .90), width: w * .18, height: h * .12);
    canvas.drawOval(dewR, p);
    canvas.drawOval(dewL, p);
  }
  @override bool shouldRepaint(_) => false;
}

class MudHolePainter extends CustomPainter {
  const MudHolePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;

    // Herbe verte (anneau extérieur)
    final grassPaint = Paint()..color = const Color(0xFF5A8A30)..style = PaintingStyle.fill;
    final grassPath = Path()
      ..addOval(Rect.fromCenter(center: Offset(w * .50, h * .52), width: w * .98, height: h * .82));
    canvas.drawPath(grassPath, grassPaint);

    // Bordure de terre brune
    final dirtPaint = Paint()..color = const Color(0xFF8B5E2A)..style = PaintingStyle.fill;
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .50, h * .54), width: w * .80, height: h * .64),
      dirtPaint,
    );

    // Boue noire centrale (irrégulière)
    final mudPath = Path()
      ..moveTo(w * .50, h * .16)
      ..cubicTo(w * .72, h * .16, w * .86, h * .28, w * .88, h * .46)
      ..cubicTo(w * .90, h * .62, w * .78, h * .78, w * .60, h * .82)
      ..cubicTo(w * .44, h * .86, w * .26, h * .80, w * .16, h * .66)
      ..cubicTo(w * .06, h * .52, w * .10, h * .30, w * .24, h * .20)
      ..cubicTo(w * .33, h * .14, w * .42, h * .14, w * .50, h * .16)
      ..close();
    canvas.drawPath(mudPath, Paint()..color = const Color(0xFF1A1200)..style = PaintingStyle.fill);

    // Reflet brillant sur la boue
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .38, h * .38), width: w * .22, height: h * .12),
      Paint()..color = const Color(0xFF2A2000).withOpacity(0.6)..style = PaintingStyle.fill,
    );

    // Touffes d'herbe (3 petits triangles verts sur le bord)
    final tufts = [
      Offset(w * .50, h * .10),
      Offset(w * .82, h * .28),
      Offset(w * .18, h * .32),
    ];
    final tuftPaint = Paint()..color = const Color(0xFF4A7A20)..style = PaintingStyle.fill;
    for (final t in tufts) {
      final blade = Path()
        ..moveTo(t.dx, t.dy + h * .07)
        ..lineTo(t.dx - w * .05, t.dy + h * .07)
        ..lineTo(t.dx - w * .02, t.dy)
        ..close();
      canvas.drawPath(blade, tuftPaint);
      final blade2 = Path()
        ..moveTo(t.dx, t.dy + h * .07)
        ..lineTo(t.dx + w * .05, t.dy + h * .07)
        ..lineTo(t.dx + w * .02, t.dy - h * .02)
        ..close();
      canvas.drawPath(blade2, Paint()..color = const Color(0xFF6AAA38)..style = PaintingStyle.fill);
    }
  }
  @override bool shouldRepaint(_) => false;
}

class HuntingTowerPainter extends CustomPainter {
  final Color color;
  const HuntingTowerPainter({this.color = Colors.white});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final fill   = Paint()..color = color..style = PaintingStyle.fill;
    final stroke = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round;
    canvas.drawRect(Rect.fromLTWH(w * .22, h * .04, w * .56, h * .36), fill);
    canvas.drawRect(Rect.fromLTWH(w * .22, h * .04, w * .56, h * .36),
        Paint()..color = color.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawRect(Rect.fromLTWH(w * .38, h * .11, w * .24, h * .20),
        Paint()..color = const Color(0xFFFFE082)..style = PaintingStyle.fill);
    canvas.drawLine(Offset(w * .20, h * .40), Offset(w * .80, h * .40), stroke);
    canvas.drawLine(Offset(w * .28, h * .40), Offset(w * .10, h * .96), stroke);
    canvas.drawLine(Offset(w * .72, h * .40), Offset(w * .90, h * .96), stroke);
    canvas.drawLine(Offset(w * .12, h * .72), Offset(w * .88, h * .72),
        Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round);
    final ladder = Paint()..color = color..style = PaintingStyle.stroke..strokeWidth = 1.2..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * .41, h * .40), Offset(w * .41, h * .96), ladder);
    canvas.drawLine(Offset(w * .59, h * .40), Offset(w * .59, h * .96), ladder);
    for (final y in [.52, .64, .76]) {
      canvas.drawLine(Offset(w * .41, h * y), Offset(w * .59, h * y), ladder);
    }
  }

  @override bool shouldRepaint(HuntingTowerPainter old) => old.color != color;
}

class TrackingPainter extends CustomPainter {
  const TrackingPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;

    // Flèche de navigation rouge
    final arrowFill = Paint()..color = const Color(0xFFFF6B35)..style = PaintingStyle.fill;
    final arrowStroke = Paint()..color = Colors.white..strokeWidth = 1.2..style = PaintingStyle.stroke;
    final arrow = ui.Path()
      ..moveTo(w * .18, h * .08)
      ..lineTo(w * .08, h * .60)
      ..lineTo(w * .28, h * .44)
      ..lineTo(w * .52, h * .58)
      ..close();
    canvas.drawPath(arrow, arrowFill);
    canvas.drawPath(arrow, arrowStroke);

    // Épingle bleue
    final pinFill = Paint()..color = const Color(0xFF4A90E2)..style = PaintingStyle.fill;
    final pinStroke = Paint()..color = Colors.white..strokeWidth = 1.2..style = PaintingStyle.stroke;
    canvas.drawCircle(Offset(w * .72, h * .34), w * .20, pinFill);
    canvas.drawCircle(Offset(w * .72, h * .34), w * .20, pinStroke);
    final pin = ui.Path()
      ..moveTo(w * .55, h * .47)
      ..lineTo(w * .72, h * .76)
      ..lineTo(w * .89, h * .47)
      ..close();
    canvas.drawPath(pin, pinFill);
    canvas.drawPath(pin, pinStroke);
    canvas.drawCircle(Offset(w * .72, h * .34), w * .09,
        Paint()..color = Colors.white..style = PaintingStyle.fill);
  }
  @override bool shouldRepaint(_) => false;
}

class SaltCubePainter extends CustomPainter {
  final Color color;
  const SaltCubePainter({this.color = const Color(0xFFFF6B35)});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final s = min(w / sqrt(3), h / 2) * 0.82;
    final cx = w / 2; final cy = h / 2;
    final top    = Offset(cx, cy - s);
    final right  = Offset(cx + s * sqrt(3) / 2, cy - s / 2);
    final left   = Offset(cx - s * sqrt(3) / 2, cy - s / 2);
    final center = Offset(cx, cy);
    final botR   = Offset(cx + s * sqrt(3) / 2, cy + s / 2);
    final botL   = Offset(cx - s * sqrt(3) / 2, cy + s / 2);
    final bottom = Offset(cx, cy + s);
    final topFace = Path()
      ..moveTo(top.dx, top.dy) ..lineTo(right.dx, right.dy)
      ..lineTo(center.dx, center.dy) ..lineTo(left.dx, left.dy) ..close();
    final rightFace = Path()
      ..moveTo(right.dx, right.dy) ..lineTo(botR.dx, botR.dy)
      ..lineTo(bottom.dx, bottom.dy) ..lineTo(center.dx, center.dy) ..close();
    final leftFace = Path()
      ..moveTo(left.dx, left.dy) ..lineTo(center.dx, center.dy)
      ..lineTo(bottom.dx, bottom.dy) ..lineTo(botL.dx, botL.dy) ..close();
    canvas.drawPath(topFace,   Paint()..color = color..style = PaintingStyle.fill);
    canvas.drawPath(rightFace, Paint()..color = color.withOpacity(0.7)..style = PaintingStyle.fill);
    canvas.drawPath(leftFace,  Paint()..color = color.withOpacity(0.45)..style = PaintingStyle.fill);
    final edge = Paint()..color = Colors.white.withOpacity(0.55)..strokeWidth = 1.2..style = PaintingStyle.stroke;
    canvas.drawPath(topFace, edge);
    canvas.drawPath(rightFace, edge);
    canvas.drawPath(leftFace, edge);
  }

  @override bool shouldRepaint(SaltCubePainter old) => old.color != color;
}

class BranchPainter extends CustomPainter {
  const BranchPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final branchPaint = Paint()
      ..color = const Color(0xFF8B5E30)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // Branche principale — bas-gauche vers droite
    branchPaint.strokeWidth = w * .13;
    final main = Path()
      ..moveTo(w * .04, h * .82)
      ..cubicTo(w * .25, h * .72, w * .55, h * .62, w * .96, h * .50);
    canvas.drawPath(main, branchPaint);

    // Sous-branche gauche
    branchPaint.strokeWidth = w * .07;
    final subL = Path()
      ..moveTo(w * .32, h * .70)
      ..cubicTo(w * .24, h * .52, w * .18, h * .38, w * .14, h * .18);
    canvas.drawPath(subL, branchPaint);

    // Sous-branche centre
    final subC = Path()
      ..moveTo(w * .55, h * .62)
      ..cubicTo(w * .50, h * .44, w * .46, h * .28, w * .44, h * .10);
    canvas.drawPath(subC, branchPaint);

    // Sous-branche droite
    final subR = Path()
      ..moveTo(w * .78, h * .54)
      ..cubicTo(w * .78, h * .40, w * .80, h * .26, w * .84, h * .12);
    canvas.drawPath(subR, branchPaint);

    // Feuilles — ovales verts avec nervure
    void leaf(double cx, double cy, double angle, double lw, double lh) {
      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);
      final darkG = Paint()..color = const Color(0xFF2E7D32)..style = PaintingStyle.fill;
      final lightG = Paint()..color = const Color(0xFF4CAF50)..style = PaintingStyle.fill;
      final vein = Paint()
        ..color = const Color(0xFF1B5E20)
        ..style = PaintingStyle.stroke
        ..strokeWidth = lw * .08
        ..strokeCap = StrokeCap.round;
      canvas.drawOval(Rect.fromCenter(center: Offset.zero, width: lw, height: lh), darkG);
      canvas.drawOval(Rect.fromCenter(center: Offset(-lw * .06, -lh * .04), width: lw * .80, height: lh * .78), lightG);
      canvas.drawLine(Offset(0, -lh * .42), Offset(0, lh * .42), vein);
      canvas.restore();
    }

    final lw = w * .38; final lh = h * .26;
    leaf(w * .16, h * .12, -0.6, lw, lh);
    leaf(w * .38, h * .06, 0.2, lw * .9, lh);
    leaf(w * .52, h * .04, 0.5, lw, lh);
    leaf(w * .72, h * .08, 0.8, lw * .85, lh);
    leaf(w * .88, h * .20, 1.1, lw, lh);
    leaf(w * .90, h * .44, 0.5, lw * .9, lh * .9);
    leaf(w * .60, h * .50, -0.2, lw * .8, lh * .85);
    leaf(w * .10, h * .38, -1.0, lw * .85, lh * .85);
  }
  @override bool shouldRepaint(_) => false;
}

class ShrubPainter extends CustomPainter {
  const ShrubPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final green = Paint()..color = const Color(0xFF4CAF50)..style = PaintingStyle.fill;
    final darkGreen = Paint()..color = const Color(0xFF2E7D32)..style = PaintingStyle.fill;
    final brown = Paint()..color = const Color(0xFF795548)..style = PaintingStyle.fill;

    // Tronc
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .42, h * .70, w * .16, h * .28),
        const Radius.circular(2),
      ),
      brown,
    );
    // Boule centrale
    canvas.drawCircle(Offset(w * .50, h * .48), w * .30, darkGreen);
    canvas.drawCircle(Offset(w * .50, h * .45), w * .28, green);
    // Boule gauche
    canvas.drawCircle(Offset(w * .28, h * .58), w * .22, darkGreen);
    canvas.drawCircle(Offset(w * .27, h * .56), w * .20, green);
    // Boule droite
    canvas.drawCircle(Offset(w * .72, h * .58), w * .22, darkGreen);
    canvas.drawCircle(Offset(w * .73, h * .56), w * .20, green);
  }
  @override bool shouldRepaint(_) => false;
}

class MoosePainter extends CustomPainter {
  const MoosePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final p = Paint()..color = const Color(0xFF6D4C1E)..style = PaintingStyle.fill;
    final dark = Paint()..color = const Color(0xFF4A3010)..style = PaintingStyle.fill;

    // Jambes — dessinées en premier (derrière le corps)
    final legW = w * .08;
    for (final x in [w*.26, w*.36, w*.62, w*.72]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, h*.55, legW, h*.42), const Radius.circular(4)),
        dark,
      );
    }

    // Corps principal
    canvas.drawOval(Rect.fromCenter(center: Offset(w*.52, h*.50), width: w*.72, height: h*.30), p);

    // Bosse d'épaule (front-top, trait distinctif orignal)
    canvas.drawOval(Rect.fromCenter(center: Offset(w*.28, h*.40), width: w*.30, height: h*.24), p);

    // Encolure
    final neck = Path()
      ..moveTo(w*.18, h*.42)
      ..cubicTo(w*.14, h*.30, w*.14, h*.22, w*.16, h*.17)
      ..lineTo(w*.27, h*.15)
      ..cubicTo(w*.30, h*.24, w*.30, h*.36, w*.28, h*.44)
      ..close();
    canvas.drawPath(neck, p);

    // Tête
    canvas.drawOval(Rect.fromCenter(center: Offset(w*.13, h*.18), width: w*.22, height: h*.16), p);

    // Muffle (nez penduleux — trait le plus distinctif)
    canvas.drawOval(Rect.fromCenter(center: Offset(w*.07, h*.28), width: w*.15, height: h*.20), p);

    // Bois — deux poutres + quelques andouillers
    final antlerP = Paint()
      ..color = const Color(0xFF9C7A2A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * .055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final antler = Path()
      ..moveTo(w*.20, h*.10)         // base gauche
      ..lineTo(w*.18, h*.01)         // poutre principale
      ..moveTo(w*.19, h*.05)
      ..lineTo(w*.10, h*.03)         // andouiller brow
      ..moveTo(w*.18, h*.01)
      ..lineTo(w*.26, h*.00)         // andouiller top-droit
      ..moveTo(w*.26, h*.14)         // base droite (symétrique)
      ..lineTo(w*.30, h*.04)
      ..moveTo(w*.30, h*.08)
      ..lineTo(w*.38, h*.05)
      ..moveTo(w*.30, h*.04)
      ..lineTo(w*.34, h*.00);
    canvas.drawPath(antler, antlerP);
  }
  @override bool shouldRepaint(_) => false;
}

class TruckPainter extends CustomPainter {
  const TruckPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    final bodyP  = Paint()..color = const Color(0xFF546E7A)..style = PaintingStyle.fill;
    final darkP  = Paint()..color = const Color(0xFF37474F)..style = PaintingStyle.fill;
    final wheelP = Paint()..color = const Color(0xFF263238)..style = PaintingStyle.fill;
    final rimP   = Paint()..color = const Color(0xFF90A4AE)..style = PaintingStyle.fill;

    // Carrosserie (vue de côté, face gauche = avant)
    final truck = Path()
      ..moveTo(w*.04, h*.76)
      ..lineTo(w*.04, h*.50)
      ..cubicTo(w*.04, h*.44, w*.10, h*.42, w*.16, h*.42)
      ..lineTo(w*.34, h*.42)
      ..lineTo(w*.40, h*.26)
      ..lineTo(w*.60, h*.22)
      ..lineTo(w*.72, h*.22)
      ..lineTo(w*.74, h*.36)
      ..lineTo(w*.96, h*.36)
      ..lineTo(w*.96, h*.58)
      ..lineTo(w*.96, h*.76)
      ..close();
    canvas.drawPath(truck, bodyP);

    // Fenêtres
    final win = Path()
      ..moveTo(w*.41, h*.28)
      ..lineTo(w*.44, h*.24)
      ..lineTo(w*.60, h*.24)
      ..lineTo(w*.71, h*.24)
      ..lineTo(w*.72, h*.36)
      ..lineTo(w*.58, h*.36)
      ..lineTo(w*.56, h*.28)
      ..close();
    canvas.drawPath(win, darkP);

    // Ligne de caisse (séparation cabine / lit)
    canvas.drawLine(Offset(w*.74, h*.36), Offset(w*.74, h*.76),
        Paint()..color = const Color(0xFF263238)..strokeWidth = w*.03..style = PaintingStyle.stroke);

    // Roues
    canvas.drawCircle(Offset(w*.22, h*.76), w*.14, wheelP);
    canvas.drawCircle(Offset(w*.22, h*.76), w*.07, rimP);
    canvas.drawCircle(Offset(w*.80, h*.76), w*.14, wheelP);
    canvas.drawCircle(Offset(w*.80, h*.76), w*.07, rimP);
  }
  @override bool shouldRepaint(_) => false;
}
