/// Home — the whole app on one calm, scrollable surface.
///
/// A fixed landscape sits behind a transparent scroll view. The timer header
/// is pinned at the top (always visible, sticky during breaks). The first
/// screenful is the "Horizon" (sky, mountains, the single control); scrolling
/// down lifts the "Journey" — odometer, progress, stats — up over the world,
/// the ground dissolving into the background. Settings live behind a gear.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../../app/app_controller.dart';
import '../../app/theme.dart';
import '../../core/badges.dart' as b;
import '../../core/comparisons.dart' as cmp;
import '../../core/game_math.dart' as gm;
import '../../core/maps.dart';
import '../../core/models.dart';
import '../../core/session_engine.dart' show dateKey, activeDaysInWindow;
import '../../core/tiers.dart';
import '../app_scope.dart';
import '../format.dart';
import '../layout.dart';
import '../painters/badge_icons.dart';
import '../painters/landscape.dart';
import '../widgets/controls.dart';
import 'settings.dart';

/// How fast the world drifts up relative to the Journey content as you
/// scroll. Less than 1 → the mountains lag behind, receding with depth.
const double _kWorldParallax = 0.34;

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ScrollController _scroll = ScrollController();
  Phase? _prevPhase;
  double _panelHeight = 0;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Auto-scrolls a little into the Journey when a break begins (header stays
  /// pinned, mountain tops stay visible); returns to the Horizon on focus.
  void _maybeAutoScroll(Phase phase) {
    if (phase == _prevPhase) return;
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final wasIdleish = _prevPhase != null;
    if (phase == Phase.breakRunning && _panelHeight > 0) {
      final target = _panelHeight * 0.46;
      if (reduceMotion || !wasIdleish) {
        if (_scroll.hasClients) _scroll.jumpTo(target);
      } else if (_scroll.hasClients) {
        _scroll.animateTo(
          target,
          duration: const Duration(milliseconds: 750),
          curve: Curves.easeInOut,
        );
      }
    } else if (phase == Phase.focusRunning && _prevPhase != null) {
      if (_scroll.hasClients && _scroll.offset > 1) {
        reduceMotion
            ? _scroll.jumpTo(0)
            : _scroll.animateTo(
                0,
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeInOut,
              );
      }
    }
    _prevPhase = phase;
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final s = controller.state;
    final p = PaletteScope.of(context);
    final phase = s.timer.phase;
    final tier = tierForLevel(s.level);

    // Read only the MediaQuery aspects we use, so HomeScreen doesn't rebuild on
    // unrelated metric changes (it rebuilds often via the controller already).
    final topInset = MediaQuery.viewPaddingOf(context).top;
    final screenH = MediaQuery.sizeOf(context).height;
    // The scene, scroll surface and chrome fill the window; each readable block
    // (timer, journey, control) is scaled up modestly and centred (see
    // [ContentBox]). `scale` sizes the header and positions the control so they
    // line up with that scaled-and-centred content.
    final scale = contentScaleFor(MediaQuery.sizeOf(context));
    // 240 (not 232) gives the header enough slack for the countdown numeral at
    // its max size; ×scale keeps that slack once the content is scaled up.
    final headerHeight = topInset + 240 * scale;
    // Floor at 0: on the first web frame MediaQuery height is momentarily 0 (and
    // a very short window could be < headerHeight), which would make the panel
    // negative and blow up the clamp bounds and SizedBox heights derived from it.
    _panelHeight = (screenH - headerHeight).clamp(0.0, double.infinity);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    // Only schedule the post-frame auto-scroll when the phase actually changed —
    // _maybeAutoScroll is a no-op otherwise, so registering a closure on every
    // (frequent) rebuild is wasted work.
    if (phase != _prevPhase) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _maybeAutoScroll(phase),
      );
    }

    // The interactive scroll surface fills the window so its backgrounds are
    // full-width; each readable block is scaled and centred (see [ContentBox]).
    // No scrollbar: the surface scrolls by wheel, drag and trackpad, and the
    // Journey rising over the world is the affordance (the app-wide
    // scrollBehavior in main.dart suppresses Material's desktop scrollbar).
    final scrollSurface = CustomScrollView(
      controller: _scroll,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _HeaderDelegate(
            height: headerHeight,
            topInset: topInset,
            panelHeight: _panelHeight,
            scale: scale,
            state: s,
            controller: controller,
            palette: p,
            scroll: _scroll,
            displayMs: _displayMs(controller, s),
          ),
        ),
        // First-screen spacer: an empty pane that lets the fixed world show
        // through. The control floats above it (see the overlay).
        SliverToBoxAdapter(child: SizedBox(height: _panelHeight)),
        // The Journey rises over the world; its top fades the ground into the
        // background colour.
        SliverToBoxAdapter(
          child: _JourneyBody(
            state: s,
            stamina: controller.displayStamina(),
            controller: controller,
          ),
        ),
      ],
    );
    return Stack(
      fit: StackFit.expand,
      children: [
        // Base colour, so nothing is ever bare.
        ColoredBox(color: p.sky),
        // The world behind the scroll surface. It drifts gently upward as the
        // Journey rises — slower than the content, so the mountains recede
        // with depth rather than scrolling clean away.
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _scroll,
            builder: (context, child) {
              if (reduceMotion) return child!;
              final offset = _scroll.hasClients ? _scroll.position.pixels : 0.0;
              final dy = -(offset * _kWorldParallax).clamp(0.0, _panelHeight);
              return Transform.translate(offset: Offset(0, dy), child: child);
            },
            child: LandscapeView(
              mapIndex: mapIndexForLevel(s.level),
              cycle: mapCycleForLevel(s.level),
              paceKmh: s.paceKmh,
              tierIndex: tier.index,
              motion: phase == Phase.focusRunning
                  ? SceneMotion.drifting
                  : SceneMotion.still,
            ),
          ),
        ),
        // The interactive UI fills the window; its backgrounds are full-width
        // and each readable block is centred (see [ContentBox]).
        scrollSurface,
        // Floating control: rises with the scroll, then pins under the header. A
        // sky cushion fades in so rising Journey content reads cleanly beneath it.
        AnimatedBuilder(
          animation: _scroll,
          builder: (context, child) {
            final offset = _scroll.hasClients ? _scroll.position.pixels : 0.0;
            final blockH = 146.0 * scale;
            // The band stays solid across the whole control, fading just below the
            // link so the rising Journey disappears cleanly beneath it.
            final topPad = 4.0 * scale;
            final bottomPad = 22.0 * scale;
            // Sticks under the timer numeral, so the ring rises well into the scroll.
            final stickTop = headerHeight - 28 * scale;
            final restingTop = screenH - screenH * 0.085 - blockH;
            final ringTop = math.max(stickTop, restingTop - offset);
            // How much solid Journey content has climbed behind the stuck control
            // (0 over open landscape, 1 once it meets the ring): drives the backing.
            final solidTop = headerHeight + _panelHeight + 140 * scale - offset;
            final cushion = (1 - (solidTop - stickTop) / (140 * scale)).clamp(
              0.0,
              1.0,
            );
            return Positioned(
              top: ringTop - topPad,
              left: 0,
              right: 0,
              child: Stack(
                children: [
                  // The cushion is purely decorative: ignore pointers so scroll
                  // (drag and wheel) reaches the surface behind across the full
                  // width. A plain DecoratedBox hit-tests true edge to edge and
                  // would otherwise swallow input over the whole strip.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              p.sky.withValues(alpha: 0),
                              p.sky.withValues(alpha: cushion),
                              p.sky.withValues(alpha: cushion),
                              p.sky.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.18, 0.82, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.only(top: topPad, bottom: bottomPad),
                    child: child,
                  ),
                ],
              ),
            );
          },
          // The control floats over the scroll surface but never captures
          // scrolling: the cushion ignores pointers and the buttons are
          // translucent (see BigControl/QuietLink), so drags and the wheel pass
          // straight through to the surface — only taps land on the buttons.
          // Every input type then scrolls uniformly across the full width, with
          // the native Scrollable doing the work (no manual forwarding).
          child: ContentBox(
            child: _ControlArea(state: s, controller: controller),
          ),
        ),
        // Settings gear, pinned to the window's top-right corner.
        Positioned(
          top: topInset + 6,
          right: 6,
          child: _GearButton(
            onTap: () =>
                Navigator.of(context).push(_fadeRoute(const SettingsScreen())),
          ),
        ),
      ],
    );
  }
}

PageRoute<void> _fadeRoute(Widget screen) {
  return PageRouteBuilder(
    pageBuilder: (_, _, _) => screen,
    transitionDuration: const Duration(milliseconds: 420),
    reverseTransitionDuration: const Duration(milliseconds: 320),
    transitionsBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
      child: child,
    ),
  );
}

// ---------------------------------------------------------------------------
// Pinned timer header
// ---------------------------------------------------------------------------

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  final double height;
  final double topInset;
  final double panelHeight;
  final double scale;
  final GameState state;
  final AppController controller;
  final Palette palette;
  final ScrollController scroll;

  /// The countdown ms to show this build. Carried as a field (not just computed
  /// in [build]) so [shouldRebuild] can detect the per-second change: the state
  /// object is unchanged while a phase runs, so without this the pinned header
  /// would cache its first frame and the countdown would freeze.
  final int displayMs;

  _HeaderDelegate({
    required this.height,
    required this.topInset,
    required this.panelHeight,
    required this.scale,
    required this.state,
    required this.controller,
    required this.palette,
    required this.scroll,
    required this.displayMs,
  });

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final p = palette;
    final s = state;
    final phase = s.timer.phase;
    final reveal = s.pendingReveal;

    final body = Padding(
      padding: EdgeInsets.only(top: topInset + 26, left: 24, right: 24),
      child: Column(
        children: [
          Text(_phaseLabel(s), style: Type.label(p)),
          const SizedBox(height: 12),
          SetDots(completed: s.sessionIndexInSet),
          const SizedBox(height: 18),
          _Countdown(ms: displayMs, dimmed: phase == Phase.focusPaused),
          const SizedBox(height: 10),
          SizedBox(
            height: 38,
            child: reveal != null && reveal.distanceKm > 0
                ? _DistanceReveal(reveal: reveal)
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );

    // The header's lower edge is see-through at rest (timer floats over the
    // mountains); as the Journey scrolls up into it, the edge fills to solid sky
    // so the content disappears cleanly beneath the timer.
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final offset = scroll.hasClients ? scroll.position.pixels : 0.0;
        final solidTop = height + panelHeight + 140 * scale - offset;
        final merge = (1 - (solidTop - height) / (140 * scale)).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                p.sky,
                p.sky.withValues(alpha: merge),
              ],
              stops: const [0.62, 1.0],
            ),
          ),
          child: child,
        );
      },
      // The gradient fills the window width; the body is scaled and centred.
      child: ContentBox(child: body),
    );
  }

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.state != state ||
      old.displayMs != displayMs ||
      old.palette != palette ||
      old.height != height ||
      old.panelHeight != panelHeight ||
      old.scale != scale;
}

int _displayMs(AppController controller, GameState s) {
  final t = s.timer;
  switch (t.phase) {
    case Phase.focusRunning:
    case Phase.focusPaused:
    case Phase.breakRunning:
      return t.remainingMs(controller.nowMs);
    case Phase.focusComplete:
      return t.breakKind == BreakKind.long
          ? s.settings.longBreakMs
          : s.settings.shortBreakMs;
    case Phase.idle:
    case Phase.breakComplete:
      return s.settings.focusMs;
  }
}

String _phaseLabel(GameState s) {
  switch (s.timer.phase) {
    case Phase.focusRunning:
      return 'FOCUS';
    case Phase.focusPaused:
      return 'PAUSED';
    case Phase.breakRunning:
      return s.timer.breakKind == BreakKind.long ? 'LONG BREAK' : 'BREAK';
    case Phase.breakComplete:
      return 'RESTED';
    case Phase.focusComplete:
      return s.timer.breakKind == BreakKind.long
          ? 'LONG BREAK NEXT'
          : 'BREAK NEXT';
    case Phase.idle:
      return 'FOCUS';
  }
}

class _Countdown extends StatelessWidget {
  final int ms;
  final bool dimmed;
  const _Countdown({required this.ms, required this.dimmed});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final w = MediaQuery.sizeOf(context).width;
    // Cap at 104 so the numeral can't overflow the fixed header on wide/tablet
    // widths; phones compute well under this, so their size is unchanged.
    final size = (w * 0.235).clamp(64.0, 104.0);
    return AnimatedOpacity(
      opacity: dimmed ? 0.45 : 1.0,
      duration: const Duration(milliseconds: 500),
      child: Text(formatCountdown(ms), style: Type.countdown(p, size)),
    );
  }
}

/// The distance just travelled + one quiet milestone line, under the timer.
/// It lingers a few seconds after appearing, then fades on its own.
class _DistanceReveal extends StatefulWidget {
  final RevealSequence reveal;
  const _DistanceReveal({required this.reveal});

  @override
  State<_DistanceReveal> createState() => _DistanceRevealState();
}

class _DistanceRevealState extends State<_DistanceReveal> {
  static const _hold = Duration(seconds: 4);
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _scheduleFade();
  }

  @override
  void didUpdateWidget(_DistanceReveal old) {
    super.didUpdateWidget(old);
    // A fresh reveal (a new completed session) shows again, then re-fades.
    if (!identical(widget.reveal, old.reveal)) {
      setState(() => _visible = true);
      _scheduleFade();
    }
  }

  void _scheduleFade() {
    _timer?.cancel();
    _timer = Timer(_hold, () {
      if (mounted) setState(() => _visible = false);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final line = _milestoneLine(widget.reveal);
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '+ ${formatKm(widget.reveal.distanceKm)}',
            style: Type.label(p, size: 14, color: p.ink),
          ),
          if (line != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                line.toUpperCase(),
                style: Type.label(
                  p,
                  size: 10,
                  color: p.inkSoft.withValues(alpha: 0.9),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The single most notable thing that happened: tier > map > level-up > badge.
String? _milestoneLine(RevealSequence r) {
  if (r.tierLevelsReached.isNotEmpty) {
    return tierForLevel(r.tierLevelsReached.last).name;
  }
  if (r.newMapIndex != null) {
    return 'Reached ${kMaps[r.newMapIndex! % kMaps.length].name}';
  }
  if (r.leveledUp) {
    return 'Level ${r.levelAfter} · ${formatPace(gm.paceKmh(r.levelAfter))}';
  }
  for (final id in r.badgeIds.reversed) {
    final badge = b.resolveBadge(id);
    if (badge != null &&
        (badge.category == b.BadgeCategory.comparison ||
            badge.category == b.BadgeCategory.odometer)) {
      return badge.name;
    }
  }
  return null;
}

// ---------------------------------------------------------------------------
// Control area (lower first screen)
// ---------------------------------------------------------------------------

class _ControlArea extends StatelessWidget {
  final GameState state;
  final AppController controller;
  const _ControlArea({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    // Compact 146px block, centred by the overlay's ContentBox. It floats over
    // the CustomScrollView and stays pointer-transparent except on the controls
    // themselves, so the scroll view handles wheel/drag across the full width.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlFor(state: state, controller: controller),
        SizedBox(
          height: 42,
          child: Center(
            child: _LinkFor(state: state, controller: controller),
          ),
        ),
      ],
    );
  }
}

class _ControlFor extends StatelessWidget {
  final GameState state;
  final AppController controller;
  const _ControlFor({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    switch (state.timer.phase) {
      case Phase.idle:
      case Phase.breakComplete:
        return BigControl(label: 'Begin', onTap: controller.startFocus);
      case Phase.focusRunning:
        return BigControl(
          label: '',
          glyph: BigControlGlyph.pause,
          onTap: controller.pauseFocus,
        );
      case Phase.focusPaused:
        return BigControl(label: 'Resume', onTap: controller.resumeFocus);
      case Phase.focusComplete:
        return BigControl(
          label: state.timer.breakKind == BreakKind.long
              ? 'Begin\nlong break'
              : 'Begin\nbreak',
          onTap: controller.startBreak,
        );
      case Phase.breakRunning:
        return BigControl(
          label: 'Begin\nearly',
          subdued: true,
          onTap: controller.startFocusDuringBreak,
        );
    }
  }
}

class _LinkFor extends StatelessWidget {
  final GameState state;
  final AppController controller;
  const _LinkFor({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    switch (state.timer.phase) {
      case Phase.focusRunning:
      case Phase.focusPaused:
        return QuietLink(label: 'End early', onTap: controller.endFocusEarly);
      case Phase.focusComplete:
        return QuietLink(label: 'Skip break', onTap: controller.skipBreak);
      case Phase.idle:
      case Phase.breakRunning:
      case Phase.breakComplete:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// Journey body (revealed by scrolling)
// ---------------------------------------------------------------------------

class _JourneyBody extends StatelessWidget {
  final GameState state;
  final double stamina;
  final AppController controller;
  const _JourneyBody({
    required this.state,
    required this.stamina,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final scale = contentScaleFor(MediaQuery.sizeOf(context));
    return Column(
      children: [
        // The ground dissolves into the background colour. The fade and the sky
        // fill the window width; only the reading content is scaled and centred.
        SizedBox(
          height: 140 * scale,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [p.sky.withValues(alpha: 0), p.sky],
                stops: const [0.0, 0.82],
              ),
            ),
          ),
        ),
        ColoredBox(
          color: p.sky,
          child: ContentBox(
            child: Padding(
              // A breath of sky above 'The road so far' before the odometer,
              // so the section clears the floating control as it scrolls up.
              padding: EdgeInsets.fromLTRB(
                32,
                44,
                32,
                MediaQuery.viewPaddingOf(context).bottom + 56,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DistanceSection(state: state),
                  const SizedBox(height: 48),
                  _ProgressSection(state: state, stamina: stamina),
                  const SizedBox(height: 48),
                  _StatsSection(state: state, controller: controller),
                  const SizedBox(height: 48),
                  // Markers close the Journey — the collection earned along it.
                  _MarkersSection(badgeIds: state.badgeIds),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _DistanceSection extends StatelessWidget {
  final GameState state;
  const _DistanceSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final passed = b.milestonePassed(state.lifetimeKm);
    final upcoming = b.nextMilestone(state.lifetimeKm);
    return Column(
      children: [
        Text('THE ROAD SO FAR', style: Type.label(p, size: 10)),
        const SizedBox(height: 16),
        Text(
          formatKm(state.lifetimeKm),
          style: Type.reveal(p, 50),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 14),
        if (passed != null)
          Text(
            'Farther than the ${passed.name}.',
            textAlign: TextAlign.center,
            style: Type.body(p, color: p.inkSoft),
          ),
        if (upcoming != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'Ahead: ${upcoming.name} · ${formatKm(upcoming.km)}',
              textAlign: TextAlign.center,
              style: Type.body(
                p,
                size: 13,
                color: p.inkSoft.withValues(alpha: 0.65),
              ),
            ),
          ),
      ],
    );
  }
}

class _ProgressSection extends StatelessWidget {
  final GameState state;

  /// Live stamina (projects passive idle recovery), so the bar climbs as you
  /// rest rather than sitting at the last banked value.
  final double stamina;
  const _ProgressSection({required this.state, required this.stamina});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final tier = tierForLevel(state.level);
    final next = nextTierAfter(state.level);
    final xpNeeded = gm.xpToNext(state.level);
    final xpFrac = (state.xpIntoLevel / xpNeeded).clamp(0.0, 1.0);
    final staminaFrac = (stamina / 100).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('PACE', style: Type.label(p, size: 10)),
        const SizedBox(height: 16),
        Text(tier.name, style: Type.title(p, size: 27)),
        const SizedBox(height: 6),
        Text(
          'LEVEL ${state.level} · ${formatPace(state.paceKmh).toUpperCase()}',
          style: Type.label(p, size: 11),
        ),
        const SizedBox(height: 30),
        _Meter(
          label: 'EXPERIENCE',
          value: '${state.xpIntoLevel} / $xpNeeded',
          caption: 'to level ${state.level + 1}',
          fraction: xpFrac,
        ),
        const SizedBox(height: 22),
        _Meter(
          label: 'STAMINA',
          value: '${stamina.round()}%',
          caption: stamina <= 0
              ? 'need rest'
              : state.timer.phase == Phase.focusRunning
              ? 'full pace'
              : stamina.round() >= 100
              ? 'rested'
              : 'recovering',
          fraction: staminaFrac,
        ),
        const SizedBox(height: 36),
        _TierPath(currentLevel: state.level, next: next),
      ],
    );
  }
}

/// The markers wall — every badge earned, four to a row, closing the Journey.
class _MarkersSection extends StatelessWidget {
  final Set<String> badgeIds;
  const _MarkersSection({required this.badgeIds});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('MARKERS', style: Type.label(p, size: 10)),
        const SizedBox(height: 20),
        _BadgeGrid(badgeIds: badgeIds),
      ],
    );
  }
}

class _StatsSection extends StatelessWidget {
  final GameState state;
  final AppController controller;
  const _StatsSection({required this.state, required this.controller});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('JOURNAL', style: Type.label(p, size: 10)),
        const SizedBox(height: 18),
        Row(
          children: [
            _Stat(
              label: 'FOCUS',
              value: formatFocusTime(state.totalFocusSeconds),
            ),
            _Stat(label: 'SESSIONS', value: thousands(state.sessionsCompleted)),
            _Stat(label: 'SETS', value: thousands(state.setsCompleted)),
          ],
        ),
        const SizedBox(height: 36),
        Text('LAST 14 DAYS', style: Type.label(p, size: 10)),
        const SizedBox(height: 18),
        _History(dailyMinutes: state.dailyFocusMinutes),
        Builder(
          builder: (context) {
            // +5% XP gain per active day in the window — shown only when earned,
            // so an empty chart stays quiet. Same window the chart draws.
            final pct =
                (gm.consistencyBonusFraction(
                          activeDaysInWindow(
                            state.dailyFocusMinutes,
                            controller.nowMs,
                          ),
                        ) *
                        100)
                    .round();
            if (pct <= 0) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(
                '+$pct% EXP GAIN',
                style: Type.label(
                  p,
                  size: 10,
                  color: p.inkSoft.withValues(alpha: 0.9),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Small reusable pieces
// ---------------------------------------------------------------------------

/// A labelled progress meter: a caption + value over a rounded bar. Used for
/// experience and stamina, so both read at a glance.
class _Meter extends StatelessWidget {
  final String label;
  final String value;
  final String caption;
  final double fraction;
  const _Meter({
    required this.label,
    required this.value,
    required this.caption,
    required this.fraction,
  });

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Type.label(p, size: 10)),
            Text(value, style: Type.label(p, size: 12, color: p.ink)),
          ],
        ),
        const SizedBox(height: 12),
        _Bar(fraction: fraction),
        const SizedBox(height: 8),
        Text(
          caption.toUpperCase(),
          style: Type.label(
            p,
            size: 9,
            color: p.inkSoft.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  final double fraction;
  const _Bar({required this.fraction});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return SizedBox(
      height: 6,
      child: CustomPaint(
        painter: _BarPainter(
          fraction: fraction,
          track: p.ink.withValues(alpha: 0.12),
          fill: p.ink.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}

class _BarPainter extends CustomPainter {
  final double fraction;
  final Color track;
  final Color fill;
  _BarPainter({
    required this.fraction,
    required this.track,
    required this.fill,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(Offset.zero & size, r),
      Paint()..color = track,
    );
    if (fraction > 0) {
      final w = math.max(size.height, size.width * fraction);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, size.height), r),
        Paint()..color = fill,
      );
    }
  }

  @override
  bool shouldRepaint(_BarPainter old) =>
      old.fraction != fraction || old.track != track || old.fill != fill;
}

class _Stat extends StatelessWidget {
  final String label;
  final String value;
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value, style: Type.title(p, size: 21)),
          const SizedBox(height: 6),
          Text(label, style: Type.label(p, size: 9.5)),
        ],
      ),
    );
  }
}

class _TierPath extends StatelessWidget {
  final int currentLevel;
  final PaceTier next;
  const _TierPath({required this.currentLevel, required this.next});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final current = tierForLevel(currentLevel);
    final entries = <(PaceTier, double)>[];
    if (current.index > 0) {
      final prevIdx = current.index - 1;
      final prevTier = prevIdx < kBaseTiers.length
          ? kBaseTiers[prevIdx]
          : tierForLevel(
              kEternalLevel +
                  (prevIdx - kBaseTiers.length + 1) * kProceduralTierInterval,
            );
      entries.add((prevTier, 0.45));
    }
    entries.add((current, 1.0));
    entries.add((next, 0.3));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (tier, alpha) in entries)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: p.ink.withValues(alpha: alpha),
                  ),
                ),
                const SizedBox(width: 14),
                Text(
                  '${tier.name} · level ${tier.level}',
                  style: Type.body(
                    p,
                    size: 13,
                    color: p.ink.withValues(alpha: alpha),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _BadgeGrid extends StatelessWidget {
  final Set<String> badgeIds;
  const _BadgeGrid({required this.badgeIds});

  /// Sort within each category by the real-world order of the catalog (tiers by
  /// level, maps by index, speeds by km/h, distances by km) rather than by raw
  /// id string, so the wall reads small-to-large.
  int _orderKey(b.Badge badge) {
    switch (badge.category) {
      case b.BadgeCategory.tier:
        return int.tryParse(badge.id.substring(5)) ?? 0;
      case b.BadgeCategory.map:
        return int.tryParse(badge.id.substring(4)) ?? 0;
      case b.BadgeCategory.comparison:
        return cmp.kComparisons.indexWhere((c) => 'cmp-${c.id}' == badge.id);
      case b.BadgeCategory.odometer:
        return b.kOdometerMilestones.indexWhere((m) => m.id == badge.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final earned = badgeIds.map(b.resolveBadge).whereType<b.Badge>().toList()
      ..sort((x, y) {
        final c = x.category.index.compareTo(y.category.index);
        return c != 0 ? c : _orderKey(x).compareTo(_orderKey(y));
      });
    if (earned.isEmpty) {
      return Text(
        'The road ahead holds its markers.',
        style: Type.body(p, color: p.inkSoft),
      );
    }
    // A fixed four-column grid: rows of four, the last row left-aligned.
    return Column(
      children: [
        for (var i = 0; i < earned.length; i += 4)
          Padding(
            padding: EdgeInsets.only(bottom: i + 4 < earned.length ? 26 : 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var j = 0; j < 4; j++)
                  Expanded(
                    child: i + j < earned.length
                        ? _Marker(badge: earned[i + j])
                        : const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Marker extends StatelessWidget {
  final b.Badge badge;
  const _Marker({required this.badge});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        children: [
          BadgeIcon(glyph: glyphForBadge(badge), size: 40),
          const SizedBox(height: 9),
          Text(
            badge.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            style: Type.body(p, size: 10, color: p.inkSoft),
          ),
        ],
      ),
    );
  }
}

class _History extends StatelessWidget {
  final Map<String, int> dailyMinutes;
  const _History({required this.dailyMinutes});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final today = DateTime.now();
    final days = [
      for (var i = 13; i >= 0; i--)
        dateKey(today.subtract(Duration(days: i)).millisecondsSinceEpoch),
    ];
    const maxBar = 46.0;
    return SizedBox(
      height: maxBar + 10,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Builder(
                builder: (context) {
                  final minutes = dailyMinutes[day] ?? 0;
                  final h = minutes <= 0
                      ? 4.0
                      : (4 + (minutes / 150).clamp(0.0, 1.0) * (maxBar - 4));
                  return Align(
                    alignment: Alignment.bottomCenter,
                    child: Container(
                      width: 5,
                      height: h,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: minutes <= 0
                            ? p.ink.withValues(alpha: 0.12)
                            : p.inkSoft.withValues(alpha: 0.85),
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Settings gear
// ---------------------------------------------------------------------------

class _GearButton extends StatelessWidget {
  final VoidCallback onTap;
  const _GearButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: CustomPaint(
          size: const Size(22, 22),
          painter: _GearPainter(color: p.ink.withValues(alpha: 0.8)),
        ),
      ),
    );
  }
}

class _GearPainter extends CustomPainter {
  final Color color;
  _GearPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.30;
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.085
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, stroke);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4;
      final d = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(
        c + d * (r + size.shortestSide * 0.04),
        c + d * (r + size.shortestSide * 0.16),
        stroke,
      );
    }
    canvas.drawCircle(c, size.shortestSide * 0.07, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GearPainter old) => old.color != color;
}
