/// The app's controls: one big circular control, quiet text links, and the
/// set-progress dots. All custom-drawn — no stock Material widgets visible.
library;

import 'package:flutter/widgets.dart';

import '../../app/theme.dart';

enum BigControlGlyph { none, pause }

/// The single large central control. A thin ring, a quiet label (or pause
/// glyph), a gentle press scale. [subdued] renders it as a whisper — used
/// during breaks, where resting is the default.
class BigControl extends StatefulWidget {
  final String label;
  final BigControlGlyph glyph;
  final VoidCallback onTap;
  final bool subdued;

  const BigControl({
    super.key,
    required this.label,
    required this.onTap,
    this.glyph = BigControlGlyph.none,
    this.subdued = false,
  });

  @override
  State<BigControl> createState() => _BigControlState();
}

class _BigControlState extends State<BigControl> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final alpha = widget.subdued ? 0.45 : 1.0;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      child: AnimatedScale(
        scale: _pressed ? 0.955 : 1.0,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        child: SizedBox(
          width: 104,
          height: 104,
          child: CustomPaint(
            painter: _RingPainter(
              ring: p.ink.withValues(alpha: 0.8 * alpha),
              fill: p.ink.withValues(alpha: 0.05 * alpha),
              glyph: widget.glyph,
              glyphColor: p.ink.withValues(alpha: alpha),
            ),
            child: widget.glyph == BigControlGlyph.none
                ? Center(
                    child: Text(
                      widget.label.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: Type.label(p,
                          size: 13,
                          color: p.ink.withValues(alpha: 0.9 * alpha)),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final Color ring;
  final Color fill;
  final BigControlGlyph glyph;
  final Color glyphColor;

  _RingPainter({
    required this.ring,
    required this.fill,
    required this.glyph,
    required this.glyphColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final r = size.shortestSide / 2 - 1;
    canvas.drawCircle(center, r, Paint()..color = fill);
    canvas.drawCircle(
      center,
      r,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4,
    );
    if (glyph == BigControlGlyph.pause) {
      final paint = Paint()
        ..color = glyphColor
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round;
      final half = size.shortestSide * 0.10;
      canvas.drawLine(center + Offset(-6, -half), center + Offset(-6, half),
          paint);
      canvas.drawLine(
          center + Offset(6, -half), center + Offset(6, half), paint);
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.ring != ring ||
      old.fill != fill ||
      old.glyph != glyph ||
      old.glyphColor != glyphColor;
}

/// A quiet, small, letter-spaced text action.
class QuietLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final double alpha;

  const QuietLink(
      {super.key, required this.label, required this.onTap, this.alpha = 0.6});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Text(
          label.toUpperCase(),
          style:
              Type.label(p, size: 11, color: p.ink.withValues(alpha: alpha)),
        ),
      ),
    );
  }
}

/// Four tiny dots showing progress through the current set.
class SetDots extends StatelessWidget {
  final int completed; // 0..4

  const SetDots({super.key, required this.completed});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 4; i++)
          Container(
            width: 5,
            height: 5,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: i < completed
                  ? p.inkSoft.withValues(alpha: 0.9)
                  : p.ink.withValues(alpha: 0.15),
            ),
          ),
      ],
    );
  }
}
