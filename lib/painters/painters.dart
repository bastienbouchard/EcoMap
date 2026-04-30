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
