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

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(targetBearing * pi / 180);

    final arrowPaint = Paint()..color = const Color(0xFFFF6B35)..style = PaintingStyle.fill;
    final arrowPath = ui.Path()
      ..moveTo(0, -radius + 30)
      ..lineTo(-15, -radius + 60)
      ..lineTo(0, -radius + 50)
      ..lineTo(15, -radius + 60)
      ..close();
    canvas.drawPath(arrowPath, arrowPaint);
    canvas.drawPath(arrowPath, Paint()..color = Colors.white..strokeWidth = 2..style = PaintingStyle.stroke);
    canvas.restore();

    // Flèche vent — entièrement à l'extérieur du cercle, tourne en espace absolu
    // +180° : la flèche pointe vers la SOURCE du vent (d'où il arrive)
    if (windDeg != null) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate((windDeg! + 180) * pi / 180);
      final windFill = Paint()
        ..color = const Color(0xFF87CEEB).withOpacity(0.92)
        ..style = PaintingStyle.fill;
      final windStroke = Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      // Flèche entièrement hors du cercle — pointe vers l'extérieur (source du vent)
      final windPath = ui.Path()
        ..moveTo(0, -(radius + 22))  // pointe (loin du cercle)
        ..lineTo(-10, -(radius + 6)) // aile gauche (près du cercle)
        ..lineTo(0, -(radius + 12))  // encoche
        ..lineTo(10, -(radius + 6))  // aile droite
        ..close();
      canvas.drawPath(windPath, windFill);
      canvas.drawPath(windPath, windStroke);
      canvas.restore();
    }

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
    // Orteil gauche — forme allongée effilée en bas
    final left = Path()
      ..moveTo(w * .50, h * .08)
      ..cubicTo(w * .30, h * .08, w * .12, h * .28, w * .14, h * .62)
      ..cubicTo(w * .15, h * .80, w * .28, h * .96, w * .38, h * .96)
      ..cubicTo(w * .48, h * .96, w * .50, h * .76, w * .50, h * .58)
      ..close();
    // Orteil droit
    final right = Path()
      ..moveTo(w * .50, h * .08)
      ..cubicTo(w * .70, h * .08, w * .88, h * .28, w * .86, h * .62)
      ..cubicTo(w * .85, h * .80, w * .72, h * .96, w * .62, h * .96)
      ..cubicTo(w * .52, h * .96, w * .50, h * .76, w * .50, h * .58)
      ..close();
    canvas.drawPath(left, p);
    canvas.drawPath(right, p);
  }
  @override bool shouldRepaint(_) => false;
}

class MudHolePainter extends CustomPainter {
  const MudHolePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    // Boue extérieure
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .50, h * .58), width: w * .90, height: h * .68),
      Paint()..color = const Color(0xFF8B5E2A)..style = PaintingStyle.fill,
    );
    // Centre plus sombre
    canvas.drawOval(
      Rect.fromCenter(center: Offset(w * .50, h * .60), width: w * .50, height: h * .36),
      Paint()..color = const Color(0xFF4A2800)..style = PaintingStyle.fill,
    );
    // Ondulations
    final rp = Paint()..color = const Color(0xFFB8864E)..style = PaintingStyle.stroke..strokeWidth = 1.2;
    canvas.drawOval(Rect.fromCenter(center: Offset(w * .50, h * .56), width: w * .70, height: h * .50), rp);
    // Bulles
    final bp = Paint()..color = const Color(0xFFD4A76A)..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(w * .33, h * .46), 2.5, bp);
    canvas.drawCircle(Offset(w * .65, h * .52), 2.0, bp);
    canvas.drawCircle(Offset(w * .48, h * .68), 1.8, bp);
  }
  @override bool shouldRepaint(_) => false;
}

class HuntingTowerPainter extends CustomPainter {
  final Color color;
  final double fillLevel;
  const HuntingTowerPainter({this.color = Colors.white, this.fillLevel = 1.0});

  void _draw(Canvas canvas, double w, double h, Color c) {
    final fill   = Paint()..color = c..style = PaintingStyle.fill;
    final stroke = Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 2.0..strokeCap = StrokeCap.round;
    canvas.drawRect(Rect.fromLTWH(w * .22, h * .04, w * .56, h * .36), fill);
    canvas.drawRect(Rect.fromLTWH(w * .22, h * .04, w * .56, h * .36),
        Paint()..color = c.withOpacity(0.5)..style = PaintingStyle.stroke..strokeWidth = 1.5);
    canvas.drawRect(Rect.fromLTWH(w * .38, h * .11, w * .24, h * .20),
        Paint()..color = const Color(0xFFFFE082)..style = PaintingStyle.fill);
    canvas.drawLine(Offset(w * .20, h * .40), Offset(w * .80, h * .40), stroke);
    canvas.drawLine(Offset(w * .28, h * .40), Offset(w * .10, h * .96), stroke);
    canvas.drawLine(Offset(w * .72, h * .40), Offset(w * .90, h * .96), stroke);
    canvas.drawLine(Offset(w * .12, h * .72), Offset(w * .88, h * .72),
        Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 1.5..strokeCap = StrokeCap.round);
    final ladder = Paint()..color = c..style = PaintingStyle.stroke..strokeWidth = 1.2..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(w * .41, h * .40), Offset(w * .41, h * .96), ladder);
    canvas.drawLine(Offset(w * .59, h * .40), Offset(w * .59, h * .96), ladder);
    for (final y in [.52, .64, .76]) {
      canvas.drawLine(Offset(w * .41, h * y), Offset(w * .59, h * y), ladder);
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    _draw(canvas, w, h, color.withOpacity(0.15));
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, h * (1.0 - fillLevel), w, h * fillLevel));
    _draw(canvas, w, h, color);
    canvas.restore();
  }

  @override bool shouldRepaint(HuntingTowerPainter old) => old.color != color || old.fillLevel != fillLevel;
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
  final double fillLevel;
  const SaltCubePainter({this.fillLevel = 1.0});

  void _drawCube(Canvas canvas, double w, double h, double opacity) {
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
    canvas.drawPath(topFace,   Paint()..color = Color(0xFFEF5350).withOpacity(opacity)..style = PaintingStyle.fill);
    canvas.drawPath(rightFace, Paint()..color = Color(0xFFC62828).withOpacity(opacity)..style = PaintingStyle.fill);
    canvas.drawPath(leftFace,  Paint()..color = Color(0xFF7F0000).withOpacity(opacity)..style = PaintingStyle.fill);
    final edge = Paint()..color = Colors.white.withOpacity(0.55 * opacity)..strokeWidth = 1.2..style = PaintingStyle.stroke;
    canvas.drawPath(topFace, edge);
    canvas.drawPath(rightFace, edge);
    canvas.drawPath(leftFace, edge);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width; final h = size.height;
    _drawCube(canvas, w, h, 0.18);
    canvas.save();
    canvas.clipRect(Rect.fromLTWH(0, h * (1.0 - fillLevel), w, h * fillLevel));
    _drawCube(canvas, w, h, 1.0);
    canvas.restore();
  }

  @override bool shouldRepaint(SaltCubePainter old) => old.fillLevel != fillLevel;
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
