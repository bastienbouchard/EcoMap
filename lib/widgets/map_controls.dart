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
}) => _MapActionBtn(
  icon: icon, label: label, color: color, active: active,
  onTap: onTap, onLongPress: onLongPress, loading: loading, customIcon: customIcon,
);

class _MapActionBtn extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool active;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final bool loading;
  final Widget? customIcon;

  const _MapActionBtn({
    required this.icon, required this.label, required this.color,
    required this.active, required this.onTap,
    this.onLongPress, this.loading = false, this.customIcon,
  });

  @override
  State<_MapActionBtn> createState() => _MapActionBtnState();
}

class _MapActionBtnState extends State<_MapActionBtn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.color;
    final bgColor = widget.active
        ? c.withOpacity(_hovered ? 0.38 : 0.25)
        : _hovered ? c.withOpacity(0.12) : const Color(0xFF2D2D2D);
    final borderColor = widget.active
        ? c
        : _hovered ? c.withOpacity(0.7) : c.withOpacity(0.4);
    final borderWidth = (widget.active || _hovered) ? 2.0 : 1.0;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                curve: Curves.easeOut,
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(21),
                  border: Border.all(color: borderColor, width: borderWidth),
                  boxShadow: [
                    BoxShadow(
                      color: _hovered
                          ? c.withOpacity(0.35)
                          : Colors.black.withOpacity(0.4),
                      blurRadius: _hovered ? 10 : 6,
                      spreadRadius: _hovered ? 1 : 0,
                    ),
                  ],
                ),
                child: widget.loading
                    ? Center(child: SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: c)))
                    : widget.customIcon != null
                        ? Center(child: widget.customIcon)
                        : Icon(widget.icon,
                            color: widget.active ? c : c.withOpacity(_hovered ? 1.0 : 0.8),
                            size: 20),
              ),
              const SizedBox(height: 4),
              Text(widget.label,
                  style: TextStyle(
                    color: widget.active ? c : _hovered ? c.withOpacity(0.8) : Colors.white54,
                    fontSize: 10,
                  )),
            ],
          ),
        ),
      ),
    );
  }
}

Widget mapIconBtn(
  IconData icon,
  VoidCallback onTap, {
  bool active = false,
  bool loading = false,
  Color activeColor = const Color(0xFF4A90E2),
}) => _MapIconBtn(icon: icon, onTap: onTap, active: active, loading: loading, activeColor: activeColor);

class _MapIconBtn extends StatefulWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool active;
  final bool loading;
  final Color activeColor;
  const _MapIconBtn({required this.icon, required this.onTap, this.active = false,
    this.loading = false, this.activeColor = const Color(0xFF4A90E2)});
  @override
  State<_MapIconBtn> createState() => _MapIconBtnState();
}

class _MapIconBtnState extends State<_MapIconBtn> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final iconColor = widget.active
        ? widget.activeColor
        : _hovered ? Colors.white : Colors.white70;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 42, height: 36,
          decoration: BoxDecoration(
            color: _hovered ? Colors.white.withOpacity(0.08) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: widget.loading
                ? const SizedBox(width: 18, height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54))
                : Icon(widget.icon, color: iconColor, size: 20),
          ),
        ),
      ),
    );
  }
}

Widget mapDividerV() => Container(width: 1, height: 20, color: Colors.white24);

class HoverMarker extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  const HoverMarker({super.key, required this.child, this.onTap});
  @override
  State<HoverMarker> createState() => _HoverMarkerState();
}

class _HoverMarkerState extends State<HoverMarker> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.18 : 1.0,
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}

Widget obsIcon(String note, {double size = 26}) {
  Widget cp(CustomPainter p) => SizedBox(width: size, height: size, child: CustomPaint(painter: p));
  if (note.contains('Frottage')) return cp(const ShrubPainter());
  if (note.contains('Traces')) return cp(const MooseTrackPainter());
  if (note.contains('Souille')) return cp(const MudHolePainter());
  if (note.contains('Cache')) return cp(const HuntingTowerPainter());
  final emoji = note.split(' ').first;
  return Text(emoji, style: TextStyle(fontSize: size * 0.76, height: 1));
}
