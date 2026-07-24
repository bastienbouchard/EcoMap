import 'package:flutter/material.dart';
import '../painters/painters.dart';

Widget mapActionBtn({
  required IconData icon,
  required String label,
  required Color color,
  required bool active,
  required VoidCallback onTap,
  VoidCallback? onLongPress,
  bool loading = false,
  Widget? customIcon,
}) {
  return GestureDetector(
    onTap: onTap,
    onLongPress: onLongPress,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: active ? color.withOpacity(0.25) : const Color(0xFF2D2D2D),
            borderRadius: BorderRadius.circular(21),
            border: Border.all(
              color: active ? color : color.withOpacity(0.4),
              width: active ? 2 : 1,
            ),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 6)],
          ),
          child: loading
              ? Center(child: SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.5, color: color)))
              : customIcon != null
                  ? Center(child: customIcon)
                  : Icon(icon, color: active ? color : color.withOpacity(0.8), size: 20),
        ),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: active ? color : Colors.white54, fontSize: 10)),
      ],
    ),
  );
}

Widget mapIconBtn(
  IconData icon,
  VoidCallback onTap, {
  bool active = false,
  bool loading = false,
  Color activeColor = const Color(0xFF4A90E2),
}) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      width: 42, height: 36,
      color: Colors.transparent,
      child: Center(
        child: loading
            ? const SizedBox(width: 18, height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
            : Icon(icon, color: active ? activeColor : Colors.white70, size: 20),
      ),
    ),
  );
}

Widget mapDividerV() => Container(width: 1, height: 20, color: Colors.white24);

Widget obsIcon(String note, {double size = 26}) {
  Widget cp(CustomPainter p) => SizedBox(width: size, height: size, child: CustomPaint(painter: p));
  if (note.contains('Frottage')) return cp(const ShrubPainter());
  if (note.contains('Traces')) return cp(const MooseTrackPainter());
  if (note.contains('Souille')) return cp(const MudHolePainter());
  if (note.contains('Cache')) return cp(const HuntingTowerPainter());
  if (note.contains('Broutage')) return cp(const BranchPainter());
  if (note.contains('Orignal')) return cp(const MoosePainter());
  if (note.contains('Camion')) return cp(const TruckPainter());
  final emoji = note.split(' ').first;
  return Text(emoji, style: TextStyle(fontSize: size * 0.76, height: 1));
}
