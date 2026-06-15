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
import '../../core/session_engine.dart' show dateKey;
import '../../core/tiers.dart';
import '../app_scope.dart';
import '../format.dart';
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
        _scroll.animateTo(target,
            duration: const Duration(milliseconds: 750),
            curve: Curves.easeInOut);
      }
    } else if (phase == Phase.focusRunning && _prevPhase != null) {
      if (_scroll.hasClients && _scroll.offset > 1) {
        reduceMotion
            ? _scroll.jumpTo(0)
            : _scroll.animateTo(0,
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeInOut);
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

    final media = MediaQuery.of(context);
    final topInset = media.viewPadding.top;
    final screenH = media.size.height;
    final headerHeight = topInset + 232;
    _panelHeight = screenH - headerHeight;
    final reduceMotion = media.disableAnimations;

    WidgetsBinding.instance
        .addPostFrameCallback((_) => _maybeAutoScroll(phase));

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
              mapIndex: mapIndexForSets(s.setsCompleted),
              cycle: mapCycleForSets(s.setsCompleted),
              paceKmh: s.paceKmh,
              tierIndex: tier.index,
              motion: phase == Phase.focusRunning
                  ? SceneMotion.drifting
                  : SceneMotion.still,
            ),
          ),
        ),
        CustomScrollView(
          controller: _scroll,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: _HeaderDelegate(
                height: headerHeight,
                topInset: topInset,
                panelHeight: _panelHeight,
                state: s,
                controller: controller,
                palette: p,
                scroll: _scroll,
              ),
            ),
            // First-screen spacer: an empty pane that lets the fixed world
            // show through. The control floats above it (see the overlay).
            SliverToBoxAdapter(child: SizedBox(height: _panelHeight)),
            // The Journey rises over the world; its top fades the ground into
            // the background colour.
            SliverToBoxAdapter(
                child: _JourneyBody(
                    state: s, stamina: controller.displayStamina())),
          ],
        ),
        // The single control floats over the world. It rests near the ground,
        // and as you scroll up it sticks just beneath the timer/distance and
        // stays there. A sky cushion fades in behind it as the Journey climbs
        // up, so the rising content reads cleanly underneath the ring rather
        // than colliding with it — while over the open landscape the control
        // floats with no band at all.
        AnimatedBuilder(
          animation: _scroll,
          builder: (context, child) {
            final offset = _scroll.hasClients ? _scroll.position.pixels : 0.0;
            const blockH = 146.0;
            // The band tucks right under the header (which masks everything
            // above it) and stays solid across the whole control — ring and
            // 'End early' alike — fading out only just below the link, so the
            // rising Journey disappears cleanly beneath the button instead of
            // colliding with it.
            const topPad = 4.0;
            const bottomPad = 22.0;
            // Sticks up under the timer numeral (in the reserved distance-line
            // space), so the ring keeps rising well into the scroll before it
            // pins.
            final stickTop = headerHeight - 28;
            final restingTop = screenH - screenH * 0.085 - blockH;
            // Rises with the scroll, then sticks just below the header.
            final ringTop = math.max(stickTop, restingTop - offset);
            // How much solid Journey content (past its ~140px ground-fade) has
            // climbed in behind the stuck control: 0 over the open landscape,
            // 1 once the Journey meets the ring. Drives the sky backing.
            final solidTop = headerHeight + _panelHeight + 140 - offset;
            final cushion = (1 - (solidTop - stickTop) / 140).clamp(0.0, 1.0);
            return Positioned(
              top: ringTop - topPad,
              left: 0,
              right: 0,
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
                child: Padding(
                  padding:
                      const EdgeInsets.only(top: topPad, bottom: bottomPad),
                  child: child,
                ),
              ),
            );
          },
          child: _ControlArea(state: s, controller: controller),
        ),
        // Settings gear, always reachable.
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
  final GameState state;
  final AppController controller;
  final Palette palette;
  final ScrollController scroll;

  _HeaderDelegate({
    required this.height,
    required this.topInset,
    required this.panelHeight,
    required this.state,
    required this.controller,
    required this.palette,
    required this.scroll,
  });

  @override
  double get minExtent => height;
  @override
  double get maxExtent => height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
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
          _Countdown(
            ms: _displayMs(controller, s),
            dimmed: phase == Phase.focusPaused,
          ),
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

    // The header's lower edge is see-through at rest, so the timer floats over
    // the mountains. As the Journey scrolls up into the header zone, that edge
    // fills back to solid sky — the rising content disappears cleanly beneath
    // the timer rather than ghosting through it.
    return AnimatedBuilder(
      animation: scroll,
      builder: (context, child) {
        final offset = scroll.hasClients ? scroll.position.pixels : 0.0;
        final solidTop = height + panelHeight + 140 - offset;
        final merge = (1 - (solidTop - height) / 140).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.sky, p.sky.withValues(alpha: merge)],
              stops: const [0.62, 1.0],
            ),
          ),
          child: child,
        );
      },
      child: body,
    );
  }

  @override
  bool shouldRebuild(_HeaderDelegate old) =>
      old.state != state ||
      old.palette != palette ||
      old.height != height ||
      old.panelHeight != panelHeight;
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
    final size = (w * 0.235).clamp(64.0, 112.0);
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
          Text('+ ${formatKm(widget.reveal.distanceKm)}',
              style: Type.label(p, size: 14, color: p.ink)),
          if (line != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(line.toUpperCase(),
                  style: Type.label(p,
                      size: 10, color: p.inkSoft.withValues(alpha: 0.9))),
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
    // Compact block (104 ring + 42 link = 146); the overlay places it.
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _ControlFor(state: state, controller: controller),
        SizedBox(
          height: 42,
          child:
              Center(child: _LinkFor(state: state, controller: controller)),
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
            onTap: controller.pauseFocus);
      case Phase.focusPaused:
        return BigControl(label: 'Resume', onTap: controller.resumeFocus);
      case Phase.focusComplete:
        return BigControl(
            label: state.timer.breakKind == BreakKind.long
                ? 'Begin\nlong break'
                : 'Begin\nbreak',
            onTap: controller.startBreak);
      case Phase.breakRunning:
        return BigControl(
            label: 'Begin\nearly',
            subdued: true,
            onTap: controller.startFocusDuringBreak);
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
  const _JourneyBody({required this.state, required this.stamina});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Column(
      children: [
        // The ground dissolves into the background colour.
        SizedBox(
          height: 140,
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
          child: Padding(
            // A breath of sky above 'The road so far' before the odometer,
            // so the section clears the floating control as it scrolls up.
            padding: EdgeInsets.fromLTRB(
                32, 44, 32, MediaQuery.viewPaddingOf(context).bottom + 56),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DistanceSection(state: state),
                const SizedBox(height: 48),
                _ProgressSection(state: state, stamina: stamina),
                const SizedBox(height: 48),
                _StatsSection(state: state),
                const SizedBox(height: 48),
                // Markers close the Journey — the collection earned along it.
                _MarkersSection(badgeIds: state.badgeIds),
              ],
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
        Text(formatKm(state.lifetimeKm),
            style: Type.reveal(p, 50), textAlign: TextAlign.center),
        const SizedBox(height: 14),
        if (passed != null)
          Text('Farther than the ${passed.name}.',
              textAlign: TextAlign.center,
              style: Type.body(p, color: p.inkSoft)),
        if (upcoming != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Ahead: ${upcoming.name} · ${formatKm(upcoming.km)}',
                textAlign: TextAlign.center,
                style: Type.body(p,
                    size: 13, color: p.inkSoft.withValues(alpha: 0.65))),
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
        Text('LEVEL ${state.level} · ${formatPace(state.paceKmh).toUpperCase()}',
            style: Type.label(p, size: 11)),
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
          caption: stamina >= 60
              ? 'full pace'
              : stamina <= 0
                  ? 'resting needed'
                  : stamina >= 100
                      ? 'fully rested'
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
  const _StatsSection({required this.state});

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
                value: formatFocusTime(state.totalFocusSeconds)),
            _Stat(label: 'SESSIONS', value: thousands(state.sessionsCompleted)),
            _Stat(label: 'SETS', value: thousands(state.setsCompleted)),
          ],
        ),
        const SizedBox(height: 36),
        Text('LAST 14 DAYS', style: Type.label(p, size: 10)),
        const SizedBox(height: 18),
        _History(dailyMinutes: state.dailyFocusMinutes),
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
        Text(caption.toUpperCase(),
            style: Type.label(p,
                size: 9, color: p.inkSoft.withValues(alpha: 0.7))),
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
  _BarPainter(
      {required this.fraction, required this.track, required this.fill});

  @override
  void paint(Canvas canvas, Size size) {
    final r = Radius.circular(size.height / 2);
    canvas.drawRRect(
        RRect.fromRectAndRadius(Offset.zero & size, r), Paint()..color = track);
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
          : tierForLevel(kEternalLevel +
              (prevIdx - kBaseTiers.length + 1) * kProceduralTierInterval);
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
                Text('${tier.name} · level ${tier.level}',
                    style: Type.body(p,
                        size: 13, color: p.ink.withValues(alpha: alpha))),
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
      return Text('The road ahead holds its markers.',
          style: Type.body(p, color: p.inkSoft));
    }
    // A fixed four-column grid: rows of four, the last row left-aligned.
    return Column(
      children: [
        for (var i = 0; i < earned.length; i += 4)
          Padding(
            padding:
                EdgeInsets.only(bottom: i + 4 < earned.length ? 26 : 0),
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
          Text(badge.name,
              textAlign: TextAlign.center,
              maxLines: 2,
              style: Type.body(p, size: 10, color: p.inkSoft)),
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
              child: Builder(builder: (context) {
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
              }),
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
      canvas.drawLine(c + d * (r + size.shortestSide * 0.04),
          c + d * (r + size.shortestSide * 0.16), stroke);
    }
    canvas.drawCircle(c, size.shortestSide * 0.07, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_GearPainter old) => old.color != color;
}
