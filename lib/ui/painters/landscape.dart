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

// A tiny tiled noise image used to dither the sky gradient. A smooth dark
// gradient otherwise shows visible 8-bit banding (the channels step in wide
// bars); overlaying faint per-pixel noise jitters those steps into a smooth
// blend. Generated once, shared across all scenes.
ui.Image? _ditherTile;
bool _ditherRequested = false;

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
    px[i * 4 + 3] = 255;
  }
  ui.decodeImageFromPixels(px, n, n, ui.PixelFormat.rgba8888, (img) {
    _ditherTile = img;
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
    super.dispose();
  }

  // Geometry cache, held per view so coexisting scenes never thrash it.
  _Geometry? _geo;
  int _geoKey = 0;

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
  final List<_Particle> particles; // ambient effect for the map (see kind)
  final List<_Particle> bgStars; // stationary night-sky stars (dark mode only)
  final List<Rect> speedLines;
  _Geometry(this.layerPaths, this.parallax, this.particles, this.bgStars,
      this.speedLines);
}

/// One ambient particle: a fixed spawn point plus a phase. How it actually
/// moves and reads is decided per [MapParticle] kind at paint time.
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

    // Sky — the one permitted subtle vertical gradient.
    final skyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [palette.sky, palette.skyLow],
        stops: const [0.0, 0.78],
      ).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, skyPaint);

    // Dither the sky to smooth the gradient's 8-bit banding. Drawn before the
    // mountains, so only the open sky carries it; the silhouettes paint over.
    final dither = _ditherTile;
    if (dither != null) {
      final identity = Float64List.fromList(const <double>[
        1, 0, 0, 0, //
        0, 1, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]);
      canvas.drawRect(
        Offset.zero & size,
        Paint()
          ..blendMode = BlendMode.overlay
          ..shader = ui.ImageShader(
              dither, TileMode.repeated, TileMode.repeated, identity),
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

    // Sky-borne particles (high drift) sit behind the mountains.
    _paintSkyParticles(canvas, size, geo);

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

    // Air- and ground-borne particles (pollen, sand, petals, snow, embers,
    // fireflies, mist…) sit in front of the mountains.
    _paintAirParticles(canvas, size, geo);
  }

  // -------------------------------------------------------------------------
  // Ambient particles — every map carries a subtle effect. All particles are
  // tonal steps of the accent ink (so they read in both themes) and only move
  // while the scene drifts (focus); at rest they hold their last position.
  // -------------------------------------------------------------------------

  static double _wrap(double v, double span) {
    var r = v % span;
    if (r < 0) r += span;
    return r;
  }

  void _paintSkyParticles(Canvas canvas, Size size, _Geometry geo) {
    if (geo.particles.isEmpty) return;
    final clk = state._scrollPx;
    switch (map.particle) {
      case MapParticle.drift:
        final w = size.width;
        final paint = Paint()..color = palette.ink.withValues(alpha: 0.12);
        for (final p in geo.particles) {
          final x = _wrap(p.x - clk * 0.06, w);
          final bob = math.sin(clk * 0.01 + p.phase) * size.height * 0.006;
          canvas.drawCircle(Offset(x, p.y + bob), p.size * 0.9, paint);
        }
      default:
        break;
    }
  }

  void _paintAirParticles(Canvas canvas, Size size, _Geometry geo) {
    if (geo.particles.isEmpty) return;
    final w = size.width;
    final h = size.height;
    final clk = state._scrollPx;
    final ink = palette.ink;
    final inkSoft = palette.inkSoft;
    const tau = 2 * math.pi;

    switch (map.particle) {
      case MapParticle.embers:
        final paint = Paint()..color = inkSoft.withValues(alpha: 0.4);
        final span = h * 0.25;
        for (final p in geo.particles) {
          final up = (clk * 0.05 + p.phase / tau * span) % span;
          final x = _wrap(p.x + math.sin(clk * 0.02 + p.phase) * 5, w);
          canvas.drawCircle(Offset(x, p.y - up), p.size * 0.85, paint);
        }
      case MapParticle.pollen:
        // Drifts sideways with a tiny bob, holding its (spread-out) height
        // rather than rising — so it stays scattered across the pane.
        final paint = Paint()..color = ink.withValues(alpha: 0.16);
        for (final p in geo.particles) {
          final x = _wrap(p.x - clk * 0.04 + math.sin(clk * 0.015 + p.phase) * 8, w);
          final bob = math.sin(clk * 0.02 + p.phase) * h * 0.006;
          canvas.drawCircle(Offset(x, p.y + bob), p.size * 0.8, paint);
        }
      case MapParticle.dust:
        final paint = Paint()..color = inkSoft.withValues(alpha: 0.2);
        for (final p in geo.particles) {
          final x = _wrap(p.x - clk * 0.14, w);
          final bob = math.sin(clk * 0.02 + p.phase) * h * 0.004;
          canvas.drawCircle(Offset(x, p.y + bob), p.size * 0.8, paint);
        }
      case MapParticle.sand:
        final paint = Paint()
          ..color = inkSoft.withValues(alpha: 0.16)
          ..strokeWidth = 1.0
          ..strokeCap = StrokeCap.round;
        for (final p in geo.particles) {
          final x = _wrap(p.x - clk * 0.5, w);
          final len = w * (0.02 + p.size * 0.015);
          canvas.drawLine(Offset(x, p.y), Offset(x + len, p.y), paint);
        }
      case MapParticle.spray:
        final paint = Paint()..color = ink.withValues(alpha: 0.18);
        final span = h * 0.06;
        for (final p in geo.particles) {
          final up = (clk * 0.04 + p.phase / tau * span) % span;
          final x = _wrap(p.x - clk * 0.2, w);
          canvas.drawCircle(Offset(x, p.y - up), p.size * 0.7, paint);
        }
      case MapParticle.mist:
        break;
      case MapParticle.fireflies:
        for (final p in geo.particles) {
          final blink = math.sin(clk * 0.03 + p.phase) * 0.5 + 0.5;
          final a = blink * blink * 0.6; // sharp on/off pulse
          if (a < 0.02) continue;
          final x = _wrap(p.x + math.sin(clk * 0.01 + p.phase) * 10, w);
          final y = p.y + math.sin(clk * 0.012 + p.phase * 1.7) * h * 0.01;
          canvas.drawCircle(
              Offset(x, y), p.size * 1.7, Paint()..color = ink.withValues(alpha: a * 0.22));
          canvas.drawCircle(
              Offset(x, y), p.size * 0.7, Paint()..color = ink.withValues(alpha: a));
        }
      default:
        break;
    }
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

      // Decor that belongs to (and scrolls with) a layer. (Tree canopies were
      // removed — the round/oval blobs read as floating balls; each map's
      // character now comes from its palette and ambient particles instead.)
      if (map.terrain == Terrain.verticalGrove && (layer == 1 || layer == 2)) {
        _addStalks(path, layerRng, w, h, specs[layer], dense: layer == 2);
      }
      paths.add(path);
    }


    final particles = _buildParticles(map.particle, rng, w, h);

    // The night-sky starfield (drawn only in dark mode): a stationary scatter
    // of pale dots across the upper sky. Generated always, cheap, drawn never
    // in light mode.
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

    return _Geometry(paths, [for (final s in specs) s.parallax], particles,
        bgStars, speedLines);
  }

  /// Spawns the ambient particles for [kind] within a band suited to it
  /// (counts kept low — these are a whisper, not weather).
  List<_Particle> _buildParticles(
      MapParticle kind, math.Random rng, double w, double h) {
    int count;
    double yLo;
    double yHi;
    switch (kind) {
      case MapParticle.none:
        return const [];
      // The horizontally-drifting ambients fill the whole front pane — from
      // just below the timer down to just above the foremost ground — scattered
      // evenly across both sky and land.
      case MapParticle.drift:
        count = 22;
        yLo = 0.18;
        yHi = 0.64;
      case MapParticle.pollen:
        count = 26;
        yLo = 0.18;
        yHi = 0.66;
      case MapParticle.dust:
        count = 26;
        yLo = 0.18;
        yHi = 0.66;
      case MapParticle.sand:
        count = 24;
        yLo = 0.22;
        yHi = 0.66;
      case MapParticle.mist:
        count = 7;
        yLo = 0.18;
        yHi = 0.60;
      // These belong to a place (the sea, the dusk ground) and keep their home.
      case MapParticle.spray:
        count = 18;
        yLo = 0.58;
        yHi = 0.70;
      case MapParticle.fireflies:
        count = 16;
        yLo = 0.55;
        yHi = 0.82;
      case MapParticle.embers:
        count = 14;
        yLo = 0.50;
        yHi = 0.74;
    }
    // Scatter on a jittered low-discrepancy grid: stratify x by index, and step
    // y by the golden ratio (mod 1) so heights spread evenly across the band in
    // any count — never bunched into a column or a horizontal strip.
    const golden = 0.61803398875;
    return [
      for (var i = 0; i < count; i++)
        _Particle(
          (i + 0.15 + rng.nextDouble() * 0.7) / count * w,
          h *
              (yLo +
                  ((i * golden + rng.nextDouble() * 0.06) % 1.0) *
                      (yHi - yLo)),
          0.8 + rng.nextDouble() * 0.9,
          rng.nextDouble() * 2 * math.pi,
        ),
    ];
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

  /// A high coastal plateau dropping to the sea.
  List<double> _plateau(math.Random rng, int n) {
    final top = _smoothNoise(rng, n, maxF: 3);
    final edge = 0.42 + rng.nextDouble() * 0.1;
    return List.generate(n, (i) {
      final u = i / n;
      // Smooth, slightly eroded cliff face between plateau and sea.
      final mask = 1 - _smoothstep(edge - 0.025, edge + 0.025, u);
      final rise = _smoothstep(0.93, 0.99, u); // wraps back up for tiling
      final m = math.max(mask, rise);
      return (0.55 + top[i] * 0.45) * m;
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
    for (var rep = 0; rep < 2; rep++) {
      for (var i = 0; i < count; i++) {
        final x = (i + 0.2 + rng.nextDouble() * 0.6) / count * w + rep * w;
        final stalkW = h * (0.006 + rng.nextDouble() * 0.007);
        final stalkH = h * (0.10 + rng.nextDouble() * 0.13);
        final baseY = h * (spec.baseline + 0.01);
        path.addRRect(RRect.fromRectAndRadius(
          Rect.fromLTWH(x, baseY - stalkH, stalkW, stalkH),
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
