/// The world: 3–4 flat parallax silhouette layers generated from a small
/// library of terrain profiles, tinted in tonal steps of the map's single
/// accent hue, scrolling slowly while focus runs. Alto's-Odyssey-grade
/// restraint: flat fills, no bitmaps, generous negative space.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../core/maps.dart';
import '../../app/theme.dart';

/// How the scene moves.
enum SceneMotion { still, drifting }

// A tiny tiled noise image used to dither the sky gradient: a smooth dark
// gradient shows 8-bit banding; faint per-pixel noise jitters the steps into a
// smooth blend. Generated once, shared across all scenes.
ui.Image? _ditherTile;
bool _ditherRequested = false;

// Identity colour matrix for the dither [ui.ImageShader]. It never changes, and
// paint() runs every frame while the scene drifts, so allocate it once and share.
final Float64List _ditherMatrix = Float64List.fromList(const <double>[
  1, 0, 0, 0, //
  0, 1, 0, 0,
  0, 0, 1, 0,
  0, 0, 0, 1,
]);

// The dither tile shader is size- and palette-independent (a repeated tile under
// the constant identity matrix), so build it once when the tile loads and reuse
// it everywhere rather than allocating a fresh ImageShader on every paint.
ui.ImageShader? _ditherShader;

void _ensureDitherTile(VoidCallback onReady) {
  if (_ditherTile != null || _ditherRequested) return;
  _ditherRequested = true;
  const n = 64;
  const spread = 4; // ± levels around mid-grey; overlay-blended, so subtle
  final rng = math.Random(7);
  final px = Uint8List(n * n * 4);
  for (var i = 0; i < n * n; i++) {
    final v = 128 + rng.nextInt(spread * 2 + 1) - spread;
    px[i * 4] = v;
    px[i * 4 + 1] = v;
    px[i * 4 + 2] = v;
    px[i * 4 + 3] = 225; // Lower opacity (alpha) to keep the dither extremely subtle
  }
  ui.decodeImageFromPixels(px, n, n, ui.PixelFormat.rgba8888, (img) {
    _ditherTile = img;
    _ditherShader =
        ui.ImageShader(img, TileMode.repeated, TileMode.repeated, _ditherMatrix);
    onReady();
  });
}

class LandscapeView extends StatefulWidget {
  final int mapIndex;
  final int cycle;
  final double paceKmh;
  final int tierIndex;
  final SceneMotion motion;

  /// Multiplies drift speed — a brief boost can punctuate a moment.
  final double driftBoost;

  const LandscapeView({
    super.key,
    required this.mapIndex,
    required this.cycle,
    required this.paceKmh,
    required this.tierIndex,
    required this.motion,
    this.driftBoost = 1.0,
  });

  WorldMap get map => kMaps[mapIndex % kMaps.length];

  @override
  State<LandscapeView> createState() => _LandscapeViewState();
}

class _LandscapeViewState extends State<LandscapeView>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _frame = ValueNotifier<int>(0);

  double _scrollPx = 0; // near-layer scroll distance
  double _velocity = 0; // px/s, eased toward target
  Duration _lastTick = Duration.zero;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _ensureDitherTile(() {
      if (mounted) _frame.value++;
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncTicker();
  }

  @override
  void didUpdateWidget(LandscapeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    final wantsMotion = !_reduceMotion && widget.motion == SceneMotion.drifting;
    if (wantsMotion && !_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    } else if (!wantsMotion && _ticker.isActive) {
      _ticker.stop();
    }
  }

  double get _targetVelocity {
    if (widget.motion != SceneMotion.drifting) return 0;
    final pace = widget.paceKmh.clamp(1.0, double.maxFinite);
    final v = 20 + 13 * (math.log(1 + pace) / math.ln2);
    return v.clamp(20.0, 105.0) * widget.driftBoost;
  }

  void _onTick(Duration elapsed) {
    final dt = _lastTick == Duration.zero
        ? 0.0
        : (elapsed - _lastTick).inMicroseconds / 1e6;
    _lastTick = elapsed;
    if (dt <= 0 || dt > 0.5) {
      _frame.value++;
      return;
    }
    _velocity += (_targetVelocity - _velocity) * math.min(1, dt * 1.6);
    _scrollPx += _velocity * dt;
    _frame.value++;
  }

  @override
  void dispose() {
    _ticker.dispose();
    _frame.dispose();
    _bg?.dispose();
    super.dispose();
  }

  // Geometry cache, held per view so coexisting scenes never thrash it.
  _Geometry? _geo;
  int _geoKey = 0;

  // The static background (sky gradient + dither + night-sky stars) recorded as a
  // picture, so the drift ticker replays it each frame instead of re-rasterizing
  // a full-screen gradient and overlay blend 60 times a second. Rebuilt only when
  // the size or palette changes; the moving layers are drawn fresh on top.
  ui.Picture? _bg;
  int _bgKey = 0;

  @override
  Widget build(BuildContext context) {
    final palette = PaletteScope.of(context);
    return RepaintBoundary(
      child: CustomPaint(
        painter: _ScenePainter(
          state: this,
          palette: palette,
          map: widget.map,
          seed: widget.mapIndex * 1009 + widget.cycle * 7919,
          tierIndex: widget.tierIndex,
          animate: !_reduceMotion,
          repaint: _frame,
        ),
        size: Size.infinite,
        isComplex: true,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Scene painting
// ---------------------------------------------------------------------------

class _LayerSpec {
  final double baseline; // fraction of height where the silhouette sits
  final double amp; // amplitude as a fraction of height
  final double parallax;
  const _LayerSpec(this.baseline, this.amp, this.parallax);
}

const _farSpec = _LayerSpec(0.525, 0.16, 0.18);
const _midFarSpec = _LayerSpec(0.585, 0.115, 0.36);
const _midSpec = _LayerSpec(0.645, 0.08, 0.62);
const _nearSpec = _LayerSpec(0.70, 0.016, 1.0);

class _Geometry {
  final List<Path> layerPaths; // far → near, each spanning 2× width
  final List<double> parallax;
  final List<_Particle> bgStars; // stationary night-sky stars (dark mode only)
  final List<Rect> speedLines;
  _Geometry(this.layerPaths, this.parallax, this.bgStars, this.speedLines);
}

/// One scene dot: a fixed spawn point plus a phase. Used for the stationary
/// dark-mode night-sky starfield.
class _Particle {
  final double x;
  final double y;
  final double size;
  final double phase;
  const _Particle(this.x, this.y, this.size, this.phase);
}

class _ScenePainter extends CustomPainter {
  final _LandscapeViewState state;
  final Palette palette;
  final WorldMap map;
  final int seed;
  final int tierIndex;
  final bool animate;

  _ScenePainter({
    required this.state,
    required this.palette,
    required this.map,
    required this.seed,
    required this.tierIndex,
    required this.animate,
    required super.repaint,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final key = Object.hash(map.name, seed, w.round(), h.round());
    if (state._geo == null || state._geoKey != key) {
      state._geo = _buildGeometry(size);
      state._geoKey = key;
    }
    final geo = state._geo!;

    // The static background (sky gradient + dither + night-sky stars) never
    // changes between frames — only the parallax layers move — so record it once
    // and replay it, instead of re-rasterizing a full-screen gradient and an
    // overlay blend 60 times a second while the scene drifts. Rebuilt only when
    // the geometry (size/map/seed), palette/theme, or dither availability change.
    final bgKey = Object.hash(state._geoKey, palette, _ditherTile != null);
    if (state._bg == null || state._bgKey != bgKey) {
      state._bg?.dispose();
      state._bg = _recordBackground(size, geo);
      state._bgKey = bgKey;
    }
    canvas.drawPicture(state._bg!);

    // Speed-lines: at extreme tiers the world itself conveys velocity.
    if (tierIndex >= 7 && state._velocity > 1 && animate) {
      final alpha = (0.05 + 0.006 * (tierIndex - 7)).clamp(0.05, 0.11);
      final linePaint = Paint()
        ..color = palette.ink.withValues(alpha: alpha)
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round;
      final offset = (state._scrollPx * 1.9) % w;
      for (final r in geo.speedLines) {
        var x = r.left - offset;
        if (x < -r.width) x += w;
        canvas.drawLine(
            Offset(x, r.top), Offset(x + r.width, r.top), linePaint);
      }
    }

    // Landscape layers, far → near.
    final layerColors = [
      palette.far,
      palette.midFar,
      palette.mid,
      palette.near,
    ];
    for (var i = 0; i < geo.layerPaths.length; i++) {
      final offset = (state._scrollPx * geo.parallax[i]) % w;
      canvas.save();
      canvas.translate(-offset, 0);
      canvas.drawPath(geo.layerPaths[i], Paint()..color = layerColors[i]);
      canvas.restore();
    }
  }

  /// Records the unchanging background — sky gradient, dither overlay, and the
  /// stationary dark-mode starfield — into a [ui.Picture] for cheap replay each
  /// frame. The moving parallax layers are drawn separately on top.
  ui.Picture _recordBackground(Size size, _Geometry geo) {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder, Offset.zero & size);

    // Sky — the one permitted subtle vertical gradient.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.sky, palette.skyLow],
          stops: const [0.0, 0.78],
        ).createShader(Offset.zero & size),
    );

    // Dither the sky to smooth the gradient's 8-bit banding. Drawn before the
    // mountains, so only the open sky carries it; the silhouettes paint over.
    final ditherShader = _ditherShader;
    if (ditherShader != null) {
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.overlay
          ..shader = ditherShader,
      );
    }

    // Dark mode: a stationary scatter of stars across the night sky, sitting
    // behind the mountains. Tones of the (light-in-dark) ink, so they read as
    // pale stars over the deep background.
    if (palette.brightness == Brightness.dark) {
      for (final s in geo.bgStars) {
        canvas.drawCircle(Offset(s.x, s.y), s.size,
            Paint()..color = palette.ink.withValues(alpha: 0.3 + 0.45 * s.phase));
      }
    }

    return recorder.endRecording();
  }



  // -------------------------------------------------------------------------
  // Geometry generation
  // -------------------------------------------------------------------------

  _Geometry _buildGeometry(Size size) {
    final w = size.width;
    final h = size.height;
    final rng = math.Random(seed);

    final specs = [_farSpec, _midFarSpec, _midSpec, _nearSpec];
    final paths = <Path>[];

    for (var layer = 0; layer < specs.length; layer++) {
      final spec = specs[layer];
      final layerRng = math.Random(seed * 31 + layer * 101 + 7);
      List<double> samples;
      var amp = spec.amp;

      switch (map.terrain) {
        case Terrain.softHills:
          samples = _smoothNoise(layerRng, 128, maxF: 3);
        case Terrain.flatPlains:
          samples = _smoothNoise(layerRng, 128, maxF: 2);
          amp *= layer == 3 ? 0.8 : 0.22;
        case Terrain.dunes:
          samples = _smoothNoise(layerRng, 128, maxF: 2)
              .map((v) => math.pow(v, 1.7).toDouble())
              .toList();
        case Terrain.jaggedTreeline:
          samples = layer == 2
              ? _treeline(layerRng, 256)
              : _smoothNoise(layerRng, 128, maxF: 3);
        case Terrain.jaggedRidges:
          samples = layer == 3
              ? _smoothNoise(layerRng, 128, maxF: 2)
              : _ridges(layerRng, 192, teeth: 3 + layer * 2);
        case Terrain.cliffsSea:
          if (layer == 1) {
            samples = _plateau(layerRng, 256);
          } else {
            samples = _smoothNoise(layerRng, 128, maxF: 3);
          }
        case Terrain.layeredMesas:
          samples = layer == 3
              ? _smoothNoise(layerRng, 128, maxF: 2)
              : _mesas(layerRng, 256, levels: 3 + layer);
        case Terrain.verticalGrove:
          samples = _smoothNoise(layerRng, 128, maxF: 2);
          if (layer == 1 || layer == 2) amp *= 0.35;
        case Terrain.steppedHills:
          samples = layer == 3
              ? _smoothNoise(layerRng, 128, maxF: 2)
              : _terraces(layerRng, 256, steps: 9);
        case Terrain.cloudLayers:
          if (layer == 0) {
            samples = _ridges(layerRng, 192, teeth: 4); // distant peaks
            amp *= 0.8;
          } else if (layer == 3) {
            samples = _smoothNoise(layerRng, 128, maxF: 2); // the rocky pass
          } else {
            samples = _smoothNoise(layerRng, 96, maxF: 2)
                .map((v) => math.pow(v, 0.6).toDouble())
                .toList(); // puffy cloud banks
          }
      }

      final path = _layerPath(samples, w, h, spec.baseline, amp);

      // Decor that scrolls with a layer. (Tree canopies were removed — they read
      // as floating balls; map character now comes from the palette.)
      if (map.terrain == Terrain.verticalGrove && (layer == 1 || layer == 2)) {
        _addStalks(path, layerRng, w, h, specs[layer], dense: layer == 2);
      }
      paths.add(path);
    }

    // Dark-mode-only night-sky starfield: a stationary scatter of pale dots
    // across the upper sky. Always generated (cheap), drawn only in dark mode.
    final bgStars = <_Particle>[
      for (var i = 0; i < 40; i++)
        _Particle(
          rng.nextDouble() * w,
          rng.nextDouble() * h * 0.5,
          0.7 + rng.nextDouble() * 0.9,
          rng.nextDouble(),
        ),
    ];

    final speedLines = <Rect>[
      for (var i = 0; i < 9; i++)
        Rect.fromLTWH(
          rng.nextDouble() * w,
          h * (0.10 + rng.nextDouble() * 0.5),
          w * (0.05 + rng.nextDouble() * 0.12),
          1,
        ),
    ];

    return _Geometry(
        paths, [for (final s in specs) s.parallax], bgStars, speedLines);
  }

  /// Builds a closed silhouette path spanning 2× width (for seamless
  /// wraparound scrolling) from periodic height samples.
  Path _layerPath(
      List<double> samples, double w, double h, double baseline, double amp) {
    final n = samples.length;
    final path = Path()..moveTo(0, h * baseline - samples[0] * h * amp);
    for (var i = 1; i <= n * 2; i++) {
      final x = i / n * w;
      path.lineTo(x, h * baseline - samples[i % n] * h * amp);
    }
    path
      ..lineTo(2 * w, h * 1.05)
      ..lineTo(0, h * 1.05)
      ..close();
    return path;
  }

  // --- periodic profile generators (all tile seamlessly) -------------------

  /// Sum of integer-frequency sinusoids, normalized to 0..1.
  List<double> _smoothNoise(math.Random rng, int n,
      {int minF = 1, int maxF = 3}) {
    final comps = <(int, double, double)>[
      for (var f = minF; f <= maxF; f++)
        (f, (1.0 / f) * (0.6 + rng.nextDouble() * 0.8), rng.nextDouble()),
    ];
    final raw = List<double>.generate(n, (i) {
      final u = i / n;
      var v = 0.0;
      for (final (f, a, p) in comps) {
        v += a * math.sin(2 * math.pi * (f * u + p));
      }
      return v;
    });
    return _normalize(raw);
  }

  /// Conifer treeline: a soft ridge with sharp triangular teeth.
  List<double> _treeline(math.Random rng, int n) {
    final base = _smoothNoise(rng, n, maxF: 2);
    const teeth = 30;
    final toothAmp =
        List.generate(teeth, (_) => 0.35 + rng.nextDouble() * 0.65);
    return List.generate(n, (i) {
      final u = i / n * teeth;
      final tooth = toothAmp[u.floor() % teeth];
      final tri = 1 - 2 * (u - u.floorToDouble() - 0.5).abs();
      return (base[i] * 0.45 + tri * tooth * 0.55).clamp(0.0, 1.0);
    });
  }

  /// Sharp mountain ridges from layered triangle waves.
  List<double> _ridges(math.Random rng, int n, {int teeth = 4}) {
    final phases = [rng.nextDouble(), rng.nextDouble(), rng.nextDouble()];
    final raw = List<double>.generate(n, (i) {
      final u = i / n;
      double tri(double x) => 1 - 2 * (x - x.floorToDouble() - 0.5).abs();
      return tri(u * teeth + phases[0]) * 0.6 +
          tri(u * (teeth * 2 + 1) + phases[1]) * 0.27 +
          tri(u * 2 + phases[2]) * 0.4;
    });
    return _normalize(raw);
  }

  /// Flat-topped mesas: smooth noise quantized into bands.
  List<double> _mesas(math.Random rng, int n, {int levels = 4}) {
    final base = _smoothNoise(rng, n, maxF: 2);
    return [
      for (final v in base)
        ((v * levels).floor() / levels + 0.06 * v).clamp(0.0, 1.0)
    ];
  }

  /// Terraced hillsides: a large hill quantized into many small steps.
  List<double> _terraces(math.Random rng, int n, {int steps = 8}) {
    final base = _smoothNoise(rng, n, maxF: 2);
    return [for (final v in base) (v * steps).floor() / steps];
  }

  /// A coastal range of headlands and inlets dropping to the sea. Inlets vary in
  /// position/width/depth over finer upland relief, and stay in the interior so
  /// both ends remain upland and the profile tiles seamlessly (see [_layerPath]).
  List<double> _plateau(math.Random rng, int n) {
    final top = _smoothNoise(rng, n, maxF: 5); // finer upland relief
    final inletCount = 3 + rng.nextInt(2); // 3–4 inlets
    final inlets = [
      for (var k = 0; k < inletCount; k++)
        (
          // Interior centres only, so u≈0 and u≈1 stay upland → seamless tile.
          center: 0.18 + rng.nextDouble() * 0.64,
          halfWidth: 0.04 + rng.nextDouble() * 0.06,
          depth: 0.5 + rng.nextDouble() * 0.45,
        ),
    ];
    return List.generate(n, (i) {
      final u = i / n;
      var land = 0.55 + top[i] * 0.45; // undulating upland
      for (final inlet in inlets) {
        // A smooth notch dropping the shore toward the sea around the inlet.
        final d = (u - inlet.center).abs();
        final cut =
            1 - _smoothstep(inlet.halfWidth - 0.02, inlet.halfWidth + 0.02, d);
        land *= 1 - inlet.depth * cut;
      }
      return land.clamp(0.0, 1.0);
    });
  }

  static double _smoothstep(double a, double b, double x) {
    final t = ((x - a) / (b - a)).clamp(0.0, 1.0);
    return t * t * (3 - 2 * t);
  }

  List<double> _normalize(List<double> raw) {
    var lo = double.infinity, hi = -double.infinity;
    for (final v in raw) {
      if (v < lo) lo = v;
      if (v > hi) hi = v;
    }
    final range = hi - lo;
    if (range < 1e-9) return List.filled(raw.length, 0.5);
    return [for (final v in raw) (v - lo) / range];
  }

  // --- layer decor ----------------------------------------------------------

  void _addStalks(Path path, math.Random rng, double w, double h,
      _LayerSpec spec, {required bool dense}) {
    final count = dense ? 9 : 6;
    final baseY = h * (spec.baseline + 0.01);
    for (var i = 0; i < count; i++) {
      // Draw each stalk's randoms once and place an identical copy in both tiles
      // (x and x + w): the 2×-width path wraps at w, so the tiles must match or
      // the grove snaps to a new arrangement on each wrap.
      final x = (i + 0.2 + rng.nextDouble() * 0.6) / count * w;
      final stalkW = h * (0.006 + rng.nextDouble() * 0.007);
      final stalkH = h * (0.10 + rng.nextDouble() * 0.13);
      for (var rep = 0; rep < 2; rep++) {
        path.addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(x + rep * w, baseY - stalkH, stalkW, stalkH),
          Radius.circular(stalkW),
        ));
      }
    }
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) =>
      oldDelegate.palette != palette ||
      oldDelegate.map != map ||
      oldDelegate.seed != seed ||
      oldDelegate.tierIndex != tierIndex;
}
