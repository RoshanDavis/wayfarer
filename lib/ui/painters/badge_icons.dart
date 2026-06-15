/// Badge icons: minimal monochrome line glyphs in the current accent ink.
///
/// Each badge resolves to a distinct glyph (see [glyphForBadge]) so the marker
/// wall reads with variety — footprints and wheels for the speeds outrun,
/// peaks and waves for the maps reached, waymarkers and globes for the
/// distances run.
library;

import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../core/badges.dart';
import '../../core/maps.dart';
import '../../app/theme.dart';

/// The distinct marker glyphs, grouped by badge family.
enum BadgeGlyph {
  // Pace tier.
  chevron,
  // Maps, by terrain family.
  peaks,
  waves,
  dunes,
  grove,
  plains,
  // Speed comparisons, by what was outrun.
  foot,
  wheel,
  gallop,
  wing,
  jet,
  orbit,
  // Odometer milestones, by scale.
  flag,
  waymarker,
  wall,
  globe,
  moon,
}

/// Maps a resolved [Badge] to the glyph that best depicts it.
BadgeGlyph glyphForBadge(Badge badge) {
  switch (badge.category) {
    case BadgeCategory.tier:
      return BadgeGlyph.chevron;
    case BadgeCategory.map:
      return _mapGlyph(badge.id);
    case BadgeCategory.comparison:
      return _comparisonGlyph(badge.id);
    case BadgeCategory.odometer:
      return _odometerGlyph(badge.id);
  }
}

BadgeGlyph _mapGlyph(String id) {
  final index = int.tryParse(id.substring(4));
  if (index == null || index < 0 || index >= kMaps.length) {
    return BadgeGlyph.peaks;
  }
  final map = kMaps[index];
  if (map.decor == MapDecor.loneTrees || map.decor == MapDecor.orchardTrees) {
    return BadgeGlyph.grove;
  }
  switch (map.terrain) {
    case Terrain.cliffsSea:
      return BadgeGlyph.waves;
    case Terrain.dunes:
      return BadgeGlyph.dunes;
    case Terrain.verticalGrove:
      return BadgeGlyph.grove;
    case Terrain.flatPlains:
    case Terrain.cloudLayers:
      return BadgeGlyph.plains;
    case Terrain.softHills:
    case Terrain.jaggedTreeline:
    case Terrain.layeredMesas:
    case Terrain.steppedHills:
    case Terrain.jaggedRidges:
      return BadgeGlyph.peaks;
  }
}

BadgeGlyph _comparisonGlyph(String id) {
  switch (id.substring(4)) {
    case 'walking-human':
    case 'sprinting-human':
      return BadgeGlyph.foot;
    case 'bicycle':
    case 'highway-car':
    case 'bullet-train':
      return BadgeGlyph.wheel;
    case 'galloping-horse':
    case 'ostrich':
    case 'cheetah':
      return BadgeGlyph.gallop;
    case 'peregrine-falcon':
      return BadgeGlyph.wing;
    case 'jet-airliner':
    case 'blackbird':
      return BadgeGlyph.jet;
    case 'speed-of-sound':
      return BadgeGlyph.waves;
    case 'orbital-velocity':
    case 'escape-velocity':
    case 'voyager-1':
    case 'parker-probe':
      return BadgeGlyph.orbit;
    default:
      return BadgeGlyph.chevron;
  }
}

BadgeGlyph _odometerGlyph(String id) {
  if (id == 'odo-21196') return BadgeGlyph.wall; // the Great Wall
  double? km;
  for (final m in kOdometerMilestones) {
    if (m.id == id) {
      km = m.km;
      break;
    }
  }
  if (km == null) return BadgeGlyph.waymarker;
  if (km < 50) return BadgeGlyph.flag; // first runs
  if (km < 10000) return BadgeGlyph.waymarker; // ultras, trails, long roads
  if (km < 100000) return BadgeGlyph.globe; // round-the-world scale
  return BadgeGlyph.moon; // lunar and beyond
}

class BadgeIcon extends StatelessWidget {
  final BadgeGlyph glyph;
  final double size;
  final bool earned;

  const BadgeIcon(
      {super.key, required this.glyph, this.size = 44, this.earned = true});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return CustomPaint(
      size: Size.square(size),
      painter: _BadgeIconPainter(
        glyph: glyph,
        color: earned
            ? p.ink.withValues(alpha: 0.85)
            : p.ink.withValues(alpha: 0.22),
      ),
    );
  }
}

class _BadgeIconPainter extends CustomPainter {
  final BadgeGlyph glyph;
  final Color color;

  _BadgeIconPainter({required this.glyph, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    final c = size.center(Offset.zero);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.035
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()..color = color;

    // A point at (dx, dy) as fractions of the icon's side, from the centre.
    Offset at(double dx, double dy) => Offset(c.dx + s * dx, c.dy + s * dy);
    void poly(List<Offset> pts) {
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final pt in pts.skip(1)) {
        path.lineTo(pt.dx, pt.dy);
      }
      canvas.drawPath(path, stroke);
    }

    // The shared marker ring (skipped where the glyph supplies its own circle).
    if (glyph != BadgeGlyph.globe) {
      canvas.drawCircle(c, s * 0.46, stroke);
    }

    switch (glyph) {
      case BadgeGlyph.chevron:
        // A double stride chevron — pace.
        poly([at(-0.20, -0.13), at(0.0, 0.0), at(-0.20, 0.13)]);
        poly([at(0.02, -0.13), at(0.22, 0.0), at(0.02, 0.13)]);
      case BadgeGlyph.peaks:
        // Two quiet peaks above a horizon.
        poly([at(-0.24, 0.12), at(-0.08, -0.13), at(0.02, 0.01)]);
        poly([at(-0.04, 0.12), at(0.10, -0.06), at(0.24, 0.12)]);
        canvas.drawLine(at(-0.26, 0.18), at(0.26, 0.18), stroke);
      case BadgeGlyph.waves:
        // Two gentle swells.
        for (final yy in [-0.06, 0.10]) {
          final path = Path();
          const n = 18;
          for (var i = 0; i <= n; i++) {
            final t = i / n;
            final o = at(-0.26 + 0.52 * t, yy + 0.05 * math.sin(t * math.pi * 2));
            i == 0 ? path.moveTo(o.dx, o.dy) : path.lineTo(o.dx, o.dy);
          }
          canvas.drawPath(path, stroke);
        }
      case BadgeGlyph.dunes:
        // Two sand humps on a baseline.
        canvas.drawLine(at(-0.26, 0.16), at(0.26, 0.16), stroke);
        canvas.drawArc(Rect.fromCircle(center: at(-0.09, 0.16), radius: s * 0.17),
            math.pi, math.pi, false, stroke);
        canvas.drawArc(Rect.fromCircle(center: at(0.13, 0.16), radius: s * 0.12),
            math.pi, math.pi, false, stroke);
      case BadgeGlyph.grove:
        // A little stand of trees.
        for (final (dx, h, r) in [
          (-0.16, 0.20, 0.07),
          (0.0, 0.26, 0.085),
          (0.16, 0.18, 0.065)
        ]) {
          canvas.drawLine(at(dx, 0.18), at(dx, 0.18 - h), stroke);
          canvas.drawCircle(at(dx, 0.18 - h), s * r, stroke);
        }
        canvas.drawLine(at(-0.26, 0.20), at(0.26, 0.20), stroke);
      case BadgeGlyph.plains:
        // Flat horizon, a low rise, a low sun.
        canvas.drawLine(at(-0.27, 0.08), at(0.27, 0.08), stroke);
        final rise = Path()..moveTo(at(-0.20, 0.08).dx, at(-0.20, 0.08).dy);
        rise.quadraticBezierTo(at(-0.02, -0.02).dx, at(-0.02, -0.02).dy,
            at(0.18, 0.08).dx, at(0.18, 0.08).dy);
        canvas.drawPath(rise, stroke);
        canvas.drawCircle(at(0.14, -0.14), s * 0.05, stroke);
      case BadgeGlyph.foot:
        // A footprint — sole and toes.
        canvas.drawOval(
            Rect.fromCenter(center: at(0.0, 0.06), width: s * 0.22, height: s * 0.34),
            stroke);
        for (final dx in [-0.075, -0.025, 0.025, 0.075]) {
          canvas.drawCircle(at(dx, -0.18), s * 0.022, fill);
        }
      case BadgeGlyph.wheel:
        // A spoked wheel.
        canvas.drawCircle(c, s * 0.20, stroke);
        canvas.drawCircle(c, s * 0.05, fill);
        for (var i = 0; i < 6; i++) {
          final a = i * math.pi / 3;
          final d = Offset(math.cos(a), math.sin(a));
          canvas.drawLine(c + d * (s * 0.07), c + d * (s * 0.18), stroke);
        }
      case BadgeGlyph.gallop:
        // A paw print — animals outrun.
        canvas.drawOval(
            Rect.fromCenter(
                center: at(0.0, 0.11), width: s * 0.28, height: s * 0.22),
            fill);
        for (final (dx, dy) in [
          (-0.15, -0.07),
          (-0.05, -0.16),
          (0.05, -0.16),
          (0.15, -0.07)
        ]) {
          canvas.drawCircle(at(dx, dy), s * 0.055, fill);
        }
      case BadgeGlyph.wing:
        // A bird in flight.
        final path = Path()..moveTo(at(-0.24, 0.02).dx, at(-0.24, 0.02).dy);
        path.quadraticBezierTo(at(-0.12, -0.14).dx, at(-0.12, -0.14).dy,
            at(0.0, 0.03).dx, at(0.0, 0.03).dy);
        path.quadraticBezierTo(at(0.12, -0.14).dx, at(0.12, -0.14).dy,
            at(0.24, 0.02).dx, at(0.24, 0.02).dy);
        canvas.drawPath(path, stroke);
      case BadgeGlyph.jet:
        // A swept delta — fastest things that fly.
        poly([
          at(0.0, -0.22),
          at(0.16, 0.14),
          at(0.0, 0.05),
          at(-0.16, 0.14),
          at(0.0, -0.22),
        ]);
      case BadgeGlyph.orbit:
        // A planet, its orbit, and a satellite riding it.
        canvas.drawCircle(c, s * 0.06, fill);
        canvas.drawOval(
            Rect.fromCenter(center: c, width: s * 0.66, height: s * 0.30),
            stroke);
        canvas.drawCircle(at(0.33, 0.0), s * 0.04, fill);
      case BadgeGlyph.flag:
        // A pennant on a pole — a first distance.
        canvas.drawLine(at(-0.10, -0.20), at(-0.10, 0.20), stroke);
        poly([at(-0.10, -0.20), at(0.16, -0.11), at(-0.10, -0.02)]);
      case BadgeGlyph.waymarker:
        // A waymarker stone beside the road.
        canvas.drawLine(at(0.0, -0.16), at(0.0, 0.16), stroke);
        canvas.drawCircle(at(0.0, -0.16), s * 0.045, fill);
        canvas.drawLine(at(-0.10, 0.16), at(0.10, 0.16), stroke);
      case BadgeGlyph.wall:
        // A crenellated wall.
        poly([
          at(-0.24, 0.14), at(-0.24, -0.02), at(-0.15, -0.02), at(-0.15, -0.12),
          at(-0.05, -0.12), at(-0.05, -0.02), at(0.05, -0.02), at(0.05, -0.12),
          at(0.15, -0.12), at(0.15, -0.02), at(0.24, -0.02), at(0.24, 0.14),
        ]);
        canvas.drawLine(at(-0.24, 0.14), at(0.24, 0.14), stroke);
      case BadgeGlyph.globe:
        // The ring is the globe; an equator and a meridian wrap it.
        canvas.drawCircle(c, s * 0.46, stroke);
        canvas.drawLine(at(-0.46, 0.0), at(0.46, 0.0), stroke);
        canvas.drawOval(
            Rect.fromCenter(center: c, width: s * 0.42, height: s * 0.92),
            stroke);
      case BadgeGlyph.moon:
        // A crescent and a twinkle.
        canvas.drawArc(Rect.fromCircle(center: at(-0.02, 0.0), radius: s * 0.26),
            math.pi * 0.36, math.pi * 1.28, false, stroke);
        final star = at(0.20, -0.16);
        canvas.drawLine(Offset(star.dx - s * 0.05, star.dy),
            Offset(star.dx + s * 0.05, star.dy), stroke);
        canvas.drawLine(Offset(star.dx, star.dy - s * 0.05),
            Offset(star.dx, star.dy + s * 0.05), stroke);
    }
  }

  @override
  bool shouldRepaint(_BadgeIconPainter old) =>
      old.glyph != glyph || old.color != color;
}
