/// The token system: one accent hue + a fixed lightness ramp. Every color in
/// the app — sky, landscape layers, text, controls — is a tonal step of the
/// current map's hue over a neutral base. Light theme = light ramp; dark
/// theme = inverted ramp, same hue. Map change = animate the hue.
library;

import 'package:flutter/widgets.dart';

import '../core/maps.dart';

/// The seven tonal steps, named by role.
class Palette {
  /// Sky at the top of the screen (lightest in light theme, darkest in dark).
  final Color sky;

  /// Sky near the horizon — the single permitted subtle vertical gradient.
  final Color skyLow;

  /// Landscape layers, back to front.
  final Color far;
  final Color midFar;
  final Color mid;
  final Color near;

  /// Secondary text and quiet UI.
  final Color inkSoft;

  /// Primary text, numerals, the runner silhouette.
  final Color ink;

  final Brightness brightness;

  const Palette({
    required this.sky,
    required this.skyLow,
    required this.far,
    required this.midFar,
    required this.mid,
    required this.near,
    required this.inkSoft,
    required this.ink,
    required this.brightness,
  });

  static Palette lerp(Palette a, Palette b, double t) => Palette(
        sky: Color.lerp(a.sky, b.sky, t)!,
        skyLow: Color.lerp(a.skyLow, b.skyLow, t)!,
        far: Color.lerp(a.far, b.far, t)!,
        midFar: Color.lerp(a.midFar, b.midFar, t)!,
        mid: Color.lerp(a.mid, b.mid, t)!,
        near: Color.lerp(a.near, b.near, t)!,
        inkSoft: Color.lerp(a.inkSoft, b.inkSoft, t)!,
        ink: Color.lerp(a.ink, b.ink, t)!,
        brightness: t < 0.5 ? a.brightness : b.brightness,
      );
}

/// Builds the palette for a map. [cycle] is the number of completed 25-map
/// loops — later cycles shift the ramp slightly so revisited maps feel like a
/// different time of day. [soften] (0..1) quiets the palette during breaks.
Palette buildPalette({
  required WorldMap map,
  required Brightness brightness,
  int cycle = 0,
  double soften = 0,
}) {
  final hue = map.hue;
  final isLight = brightness == Brightness.light;
  // Dark theme keeps the light theme's landscape colours verbatim, so the
  // hills read the same in both — only the sky and ink change.
  final baseSat = map.saturation;
  final sat = baseSat * (1 - 0.30 * soften);
  // Cycle variation: 0, slightly lifted, slightly sunk — same hue family.
  final shift = const [0.0, 0.035, -0.03][cycle % 3];

  Color step(double lightness, double satScale) {
    final softenShift = (isLight ? 0.02 : -0.015) * soften;
    final l = (lightness + shift + softenShift).clamp(0.0, 1.0);
    return HSLColor.fromAHSL(1, hue, (sat * satScale).clamp(0.0, 1.0), l)
        .toColor();
  }

  if (isLight) {
    return Palette(
      sky: step(0.95, 0.45),
      skyLow: step(0.89, 0.55),
      far: step(0.78, 0.65),
      midFar: step(0.66, 0.75),
      mid: step(0.54, 0.85),
      near: step(0.40, 0.90),
      inkSoft: step(0.44, 0.45),
      ink: step(0.19, 0.50),
      brightness: brightness,
    );
  }
  // Dark theme — the light theme's landscape, set under a night sky. The
  // hills keep their light-theme tones (same colours, same depth); only the
  // background swaps to a deep, accent-tinted vertical gradient and the ink
  // flips light so text reads over it.
  return Palette(
    sky: step(0.085, 0.85),
    skyLow: step(0.165, 1.0),
    far: step(0.71, 0.65),
    midFar: step(0.585, 0.75),
    mid: step(0.465, 0.85),
    near: step(0.335, 0.90),
    inkSoft: step(0.72, 0.32),
    ink: step(0.95, 0.18),
    brightness: brightness,
  );
}

/// The single deliberate break from the monochrome palette: the destructive
/// "reset all data" action. A muted terracotta red that reads in both themes.
const Color kDangerRed = Color(0xFFC2553F);

// ---------------------------------------------------------------------------
// Typography — one typeface (system Roboto), light weights, generous spacing.
// ---------------------------------------------------------------------------

class Type {
  Type._();

  /// The countdown numeral — the largest element in the app.
  static TextStyle countdown(Palette p, double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w200,
        letterSpacing: size * 0.04,
        color: p.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.0,
      );

  /// Small uppercase labels ("FOCUS · 2 OF 4").
  static TextStyle label(Palette p, {double size = 12, Color? color}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w400,
        letterSpacing: size * 0.28,
        color: color ?? p.inkSoft,
        height: 1.0,
      );

  /// Large reveal numbers ("+ 4.4 km").
  static TextStyle reveal(Palette p, double size) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w200,
        letterSpacing: size * 0.02,
        color: p.ink,
        fontFeatures: const [FontFeature.tabularFigures()],
        height: 1.1,
      );

  /// Titles (tier names, screen headers).
  static TextStyle title(Palette p, {double size = 26}) => TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w300,
        letterSpacing: size * 0.06,
        color: p.ink,
        height: 1.2,
      );

  static TextStyle body(Palette p, {double size = 15, Color? color}) =>
      TextStyle(
        fontSize: size,
        fontWeight: FontWeight.w300,
        letterSpacing: 0.4,
        color: color ?? p.ink,
        height: 1.45,
      );
}

// ---------------------------------------------------------------------------
// PaletteScope — provides the current (possibly mid-crossfade) palette.
// ---------------------------------------------------------------------------

class PaletteScope extends InheritedWidget {
  final Palette palette;
  const PaletteScope({super.key, required this.palette, required super.child});

  static Palette of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<PaletteScope>()!
      .palette;

  @override
  bool updateShouldNotify(PaletteScope oldWidget) =>
      oldWidget.palette != palette;
}

/// Animates palette changes (map transitions, theme flips, break softening)
/// with a slow, calm crossfade. Honors reduce-motion by jumping instantly.
class PaletteTransition extends StatefulWidget {
  final Palette target;
  final Duration duration;
  final Widget child;

  const PaletteTransition({
    super.key,
    required this.target,
    this.duration = const Duration(milliseconds: 2400),
    required this.child,
  });

  @override
  State<PaletteTransition> createState() => _PaletteTransitionState();
}

class _PaletteTransitionState extends State<PaletteTransition>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Palette _from;
  late Palette _to;

  @override
  void initState() {
    super.initState();
    _from = widget.target;
    _to = widget.target;
    _controller = AnimationController(vsync: this, duration: widget.duration)
      ..value = 1;
  }

  @override
  void didUpdateWidget(PaletteTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.target != _to) {
      final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
      final isThemeFlip = widget.target.brightness != _to.brightness;
      // A theme flip is instant — no crossfade. Map changes keep the slow,
      // calm fade.
      if (reduceMotion || isThemeFlip) {
        _from = widget.target;
        _to = widget.target;
        _controller.value = 1;
      } else {
        _from = Palette.lerp(
            _from, _to, Curves.easeInOut.transform(_controller.value));
        _to = widget.target;
        _controller
          ..duration = widget.duration
          ..forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => PaletteScope(
        palette: Palette.lerp(
            _from, _to, Curves.easeInOut.transform(_controller.value)),
        child: child!,
      ),
      child: widget.child,
    );
  }
}
