/// The pomodoro session engine: an explicit state machine over [GameState],
/// driven entirely by wall-clock timestamps. Pure Dart.
///
/// Every transition is a pure function `(GameState, nowMs) -> GameState`.
/// [reconstruct] re-derives the true state after any time gap (backgrounding,
/// process death, reboot) — phases that finished while the app was dead are
/// resolved at their *scheduled* wall-clock end, so distance, XP, badges and
/// the pending reveal are identical whether or not the app was alive.
///
/// Phases never auto-chain: each running phase begins with a user tap, so at
/// most the single in-flight phase can complete during a dead gap.
library;

import 'badges.dart';
import 'comparisons.dart';
import 'game_math.dart' as gm;
import 'maps.dart';
import 'models.dart';
import 'tiers.dart';

/// Local-date key 'yyyy-MM-dd' for daily focus history.
String dateKey(int epochMs) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochMs);
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year.toString().padLeft(4, '0')}-$m-$day';
}

/// Count of distinct days with focus minutes in the trailing
/// [gm.kConsistencyWindowDays] window ending at [endMs] (inclusive) — the same
/// window the Journey's 14-day chart draws. Drives the consistency multiplier.
int activeDaysInWindow(Map<String, int> daily, int endMs) {
  final end = DateTime.fromMillisecondsSinceEpoch(endMs);
  var count = 0;
  for (var i = 0; i < gm.kConsistencyWindowDays; i++) {
    final key =
        dateKey(end.subtract(Duration(days: i)).millisecondsSinceEpoch);
    if ((daily[key] ?? 0) > 0) count++;
  }
  return count;
}

class Engine {
  Engine._();

  // -------------------------------------------------------------------------
  // User actions
  // -------------------------------------------------------------------------

  /// Starts a focus session. Valid from idle or breakComplete.
  static GameState startFocus(GameState s, int nowMs) {
    if (s.timer.phase != Phase.idle && s.timer.phase != Phase.breakComplete) {
      return s;
    }
    // Credit any idle rest taken since the last session before this one starts,
    // so the session-start stamina (which fixes the speed) reflects it.
    final rested = _applyIdleRecovery(s, nowMs);
    final dur = rested.settings.focusMs;
    return rested.copyWith(
      clearPendingReveal: true,
      staminaSyncedAtMs: nowMs,
      timer: TimerState(
        phase: Phase.focusRunning,
        segmentStartedAtMs: nowMs,
        phaseEndsAtMs: nowMs + dur,
        accumulatedFocusMs: 0,
        bankedDistanceKm: 0,
        staminaAtSessionStart: rested.stamina,
        levelAtSessionStart: rested.level,
        plannedDurationMs: dur,
      ),
    );
  }

  /// Pauses a running focus session: banks the segment's distance, applies
  /// its proportional stamina drain, and stops the clock.
  static GameState pauseFocus(GameState s, int nowMs) {
    final t = s.timer;
    if (t.phase != Phase.focusRunning) return s;
    if (nowMs >= t.phaseEndsAtMs!) return reconstruct(s, nowMs);
    final segmentMs = (nowMs - t.segmentStartedAtMs!)
        .clamp(0, t.plannedDurationMs - t.accumulatedFocusMs);
    final segmentDistance = gm.distanceKm(
      levelAtSessionStart: t.levelAtSessionStart,
      // Stamina at the start of *this* segment — so the half-rate debuff
      // engages the instant the bar empties mid-session.
      staminaAtSessionStart: s.stamina,
      elapsedFocusMs: segmentMs,
      focusDurationMs: t.plannedDurationMs,
    );
    final drain = gm.drainFor(
      level: t.levelAtSessionStart,
      elapsedFocusMs: segmentMs,
      focusDurationMs: t.plannedDurationMs,
    );
    return s.copyWith(
      stamina: (s.stamina - drain).clamp(0.0, gm.kMaxStamina),
      // Anchor the recovery clock: a paused session rests at the long-break rate.
      staminaSyncedAtMs: nowMs,
      timer: t.copyWith(
        phase: Phase.focusPaused,
        clearSegment: true,
        accumulatedFocusMs: t.accumulatedFocusMs + segmentMs,
        bankedDistanceKm: t.bankedDistanceKm + segmentDistance,
      ),
    );
  }

  /// Resumes a paused focus session.
  static GameState resumeFocus(GameState s, int nowMs) {
    if (s.timer.phase != Phase.focusPaused) return s;
    // Credit the rest taken while paused up to now, then restart the clock.
    final rested = _applyIdleRecovery(s, nowMs);
    final t = rested.timer;
    return rested.copyWith(
      timer: t.copyWith(
        phase: Phase.focusRunning,
        segmentStartedAtMs: nowMs,
        phaseEndsAtMs: nowMs + (t.plannedDurationMs - t.accumulatedFocusMs),
      ),
    );
  }

  /// Ends a focus session early. Distance and time-based XP for the minutes
  /// worked are awarded (never confiscated), but the session does not count
  /// toward the set — the focus simply ends and the user advances to the next
  /// session, a short break. Valid from running or paused.
  static GameState endFocusEarly(GameState s, int nowMs) {
    var state = s;
    if (state.timer.phase == Phase.focusRunning) {
      if (nowMs >= state.timer.phaseEndsAtMs!) return reconstruct(s, nowMs);
      state = pauseFocus(state, nowMs);
    }
    if (state.timer.phase != Phase.focusPaused) return s;
    // Credit any rest taken while paused before awarding, so the bar is current.
    state = _applyIdleRecovery(state, nowMs);
    final t = state.timer;

    final distance = t.bankedDistanceKm;
    final elapsedMs = t.accumulatedFocusMs;
    // Nothing worked yet — return to idle rather than offering a break.
    if (elapsedMs <= 0 && distance <= 0) {
      return state.copyWith(timer: TimerState.idle, staminaSyncedAtMs: nowMs);
    }
    return _finishFocus(
      state,
      stamina: state.stamina,
      distance: distance,
      elapsedFocusMs: elapsedMs,
      staminaAtSessionStart: t.staminaAtSessionStart,
      focusDurationMs: t.plannedDurationMs,
      completed: false,
      dayKeyMs: nowMs,
      syncAtMs: nowMs,
    );
  }

  /// Starts the break that follows a completed focus session. The just-earned
  /// distance/milestone reveal is kept (cleared only at the next focus start)
  /// so it stays under the timer while the user rests.
  static GameState startBreak(GameState s, int nowMs) {
    final t = s.timer;
    if (t.phase != Phase.focusComplete) return s;
    final kind = t.breakKind ?? BreakKind.short;
    final durationMs =
        kind == BreakKind.long ? s.settings.longBreakMs : s.settings.shortBreakMs;
    return s.copyWith(
      timer: TimerState(
        phase: Phase.breakRunning,
        breakKind: kind,
        segmentStartedAtMs: nowMs,
        phaseEndsAtMs: nowMs + durationMs,
        staminaAtBreakStart: s.stamina,
        plannedDurationMs: durationMs,
      ),
    );
  }

  /// Skips the pending break entirely — no recovery, straight to idle. The
  /// reveal is kept so the distance stays under the timer until next focus.
  static GameState skipBreak(GameState s) {
    if (s.timer.phase != Phase.focusComplete) return s;
    return s.copyWith(timer: TimerState.idle);
  }

  /// Ends a running break early: recovery proportional to the break fraction
  /// actually rested.
  static GameState endBreakEarly(GameState s, int nowMs) {
    final t = s.timer;
    if (t.phase != Phase.breakRunning) return s;
    if (nowMs >= t.phaseEndsAtMs!) return reconstruct(s, nowMs);
    final fraction = (nowMs - t.segmentStartedAtMs!) / t.plannedDurationMs;
    return _finishBreak(s, fraction, nowMs);
  }

  /// Clears an acknowledged reveal (used after an early-end reveal, where
  /// the next action is simply returning to idle).
  static GameState acknowledgeReveal(GameState s) =>
      s.copyWith(clearPendingReveal: true);

  // -------------------------------------------------------------------------
  // Reconstruction — the single completion code path
  // -------------------------------------------------------------------------

  /// Re-derives the true state at [nowMs]. Called on launch, on every
  /// lifecycle resume, and by the foreground ticker when a phase's scheduled
  /// end passes. Resolves at most one phase completion (phases never
  /// auto-chain).
  static GameState reconstruct(GameState s, int nowMs) {
    final t = s.timer;
    // Resolve at most one phase completion (phases never auto-chain)...
    final GameState resolved;
    switch (t.phase) {
      case Phase.focusRunning:
        resolved =
            nowMs >= t.phaseEndsAtMs! ? _resolveFocusComplete(s) : s;
      case Phase.breakRunning:
        resolved =
            nowMs >= t.phaseEndsAtMs! ? _finishBreak(s, 1.0, t.phaseEndsAtMs!) : s;
      case Phase.idle:
      case Phase.focusPaused:
      case Phase.focusComplete:
      case Phase.breakComplete:
        resolved = s;
    }
    // ...then accrue passive idle recovery for whatever resting phase we land
    // in, from the last sync point up to now. A no-op for running phases.
    return _applyIdleRecovery(resolved, nowMs);
  }

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  /// Resolves a focus session that reached its scheduled end — always at the
  /// scheduled end time, regardless of when we noticed.
  static GameState _resolveFocusComplete(GameState s) {
    final t = s.timer;
    final endMs = t.phaseEndsAtMs!;
    final focusDurationMs = t.plannedDurationMs;
    final segmentMs = focusDurationMs - t.accumulatedFocusMs;

    final distance = t.bankedDistanceKm +
        gm.distanceKm(
          levelAtSessionStart: t.levelAtSessionStart,
          // Stamina at the start of the final segment, so a mid-session empty
          // bar halves only the distance travelled after it emptied.
          staminaAtSessionStart: s.stamina,
          elapsedFocusMs: segmentMs,
          focusDurationMs: focusDurationMs,
        );
    final drain = gm.drainFor(
      level: t.levelAtSessionStart,
      elapsedFocusMs: segmentMs,
      focusDurationMs: focusDurationMs,
    );
    final stamina = (s.stamina - drain).clamp(0.0, gm.kMaxStamina);

    return _finishFocus(
      s,
      stamina: stamina,
      distance: distance,
      elapsedFocusMs: focusDurationMs,
      staminaAtSessionStart: t.staminaAtSessionStart,
      focusDurationMs: focusDurationMs,
      completed: true,
      // Idle recovery accrues from the moment focus ended, not from when we
      // noticed — so a late wake-up still credits the full rest since.
      dayKeyMs: endMs,
      syncAtMs: endMs,
    );
  }

  /// Shared tail of finishing a focus segment: awards time-based XP (plus the
  /// set bonus on a full set and a marker bonus per badge earned, all lifted by
  /// the recent-consistency multiplier), resolves level-ups and tier/comparison/
  /// odometer/map badges, banks distance and focus time, and routes to the
  /// pending-break (focusComplete) state. [completed] distinguishes a full
  /// session — which counts the session and set, adds the set bonus, and takes
  /// the long break every 4th — from an early end, which counts neither and
  /// always takes a short break (the long break is earned only by finishing a
  /// set). The map advances on any level-up, independent of sets.
  static GameState _finishFocus(
    GameState s, {
    required double stamina,
    required double distance,
    required int elapsedFocusMs,
    required double staminaAtSessionStart,
    required int focusDurationMs,
    required bool completed,
    required int dayKeyMs,
    required int syncAtMs,
  }) {
    // Set and session counting. A session only counts when fully completed.
    final completedSet =
        completed && s.sessionIndexInSet == gm.kSessionsPerSet - 1;
    final newSessionIndex = completed
        ? (s.sessionIndexInSet + 1) % gm.kSessionsPerSet
        : s.sessionIndexInSet;
    final newSets = s.setsCompleted + (completedSet ? 1 : 0);

    // Odometer milestones depend only on distance (independent of XP), so they
    // resolve up front and feed the marker count below.
    final oldKm = s.lifetimeKm;
    final newKm = oldKm + distance;
    final milestones = [
      for (final m in milestonesCrossedBetween(oldKm, newKm))
        if (!s.badgeIds.contains(m.id)) m,
    ];

    // Daily history, updated once and reused for the consistency window and the
    // final state. Counting today (via dayKeyMs) makes the awarded bonus match
    // what the 14-day chart shows after this session.
    final dailyAfter = _addDailyMinutes(
        s.dailyFocusMinutes, dateKey(dayKeyMs), elapsedFocusMs ~/ 60000);
    final mult =
        gm.consistencyMultiplier(activeDaysInWindow(dailyAfter, dayKeyMs));

    // Base XP: time-based (with the mid-session stamina debuff applied inside
    // xpForFocus) plus the set bonus, lifted by the consistency multiplier.
    final timeXp = gm.xpForFocus(
      elapsedFocusMs: elapsedFocusMs,
      staminaAtSessionStart: staminaAtSessionStart,
      level: s.level,
      focusDurationMs: focusDurationMs,
    );
    final setBonus = completedSet ? gm.kXpSetBonus : 0;
    final baseXp = ((timeXp + setBonus) * mult).round();

    // Markers award XP too, which can fund another level and so cross more
    // markers. Resolve level, marker count and marker XP together by iterating
    // to a fixpoint — always re-levelling from the original anchor so base XP is
    // never double-counted. The marker count only grows with level, so this
    // converges in a pass or two; the cap is a safety net.
    var markerXp = 0;
    var markerCount = -1;
    var progress = gm.applyXp(
        level: s.level, xpIntoLevel: s.xpIntoLevel, gained: baseXp);
    for (var pass = 0; pass < gm.kMaxMarkerPasses; pass++) {
      progress = gm.applyXp(
          level: s.level,
          xpIntoLevel: s.xpIntoLevel,
          gained: baseXp + markerXp);
      final count = _markerCount(s, progress.level, milestones.length);
      if (count == markerCount) break;
      markerCount = count;
      markerXp = (gm.kXpPerMarker * count * mult).round();
    }

    // Concrete marker lists at the final level — the single source of truth for
    // both the awarded badges and the reveal.
    final tiers = tiersReachedBetween(s.level, progress.level);
    final crossings = [
      for (final c
          in crossingsBetween(gm.paceKmh(s.level), gm.paceKmh(progress.level)))
        if (!s.badgeIds.contains(comparisonBadgeId(c.id))) c,
    ];
    // The map advances on any level-up. The terrain still advances when the map
    // badge is a repeat (a later cycle of the 25 maps); only the badge/XP dedup.
    final int? newMapIndex =
        progress.level > s.level ? mapIndexForLevel(progress.level) : null;

    // Badges, in reveal order: tier, map, comparison, odometer.
    final newBadgeIds = <String>[
      for (final tier in tiers)
        if (!s.badgeIds.contains(tierBadgeId(tier.level)))
          tierBadgeId(tier.level),
      if (newMapIndex != null && !s.badgeIds.contains(mapBadgeId(newMapIndex)))
        mapBadgeId(newMapIndex),
      for (final c in crossings) comparisonBadgeId(c.id),
      for (final m in milestones) m.id,
    ];

    final xpGained = baseXp + markerXp;

    final nextBreak =
        completed && newSessionIndex == 0 ? BreakKind.long : BreakKind.short;

    return s.copyWith(
      stamina: stamina,
      lifetimeKm: newKm,
      totalFocusSeconds: s.totalFocusSeconds + elapsedFocusMs ~/ 1000,
      sessionsCompleted: s.sessionsCompleted + (completed ? 1 : 0),
      setsCompleted: newSets,
      sessionIndexInSet: newSessionIndex,
      xpIntoLevel: progress.xpIntoLevel,
      level: progress.level,
      badgeIds: {...s.badgeIds, ...newBadgeIds},
      dailyFocusMinutes: dailyAfter,
      staminaSyncedAtMs: syncAtMs,
      timer: TimerState(phase: Phase.focusComplete, breakKind: nextBreak),
      pendingReveal: RevealSequence(
        distanceKm: distance,
        sessionCompleted: completed,
        xpGained: xpGained,
        levelBefore: s.level,
        levelAfter: progress.level,
        tierLevelsReached: [for (final tier in tiers) tier.level],
        comparisonIds: [for (final c in crossings) c.id],
        newMapIndex: newMapIndex,
        badgeIds: newBadgeIds,
        nextAction: nextBreak == BreakKind.long
            ? NextAction.longBreak
            : NextAction.shortBreak,
      ),
    );
  }

  /// Number of markers (badges) the session would award if it ended at
  /// [finalLevel]: unearned tier, map, and comparison badges crossed between
  /// `s.level` and [finalLevel], plus [odometerCount] already-resolved odometer
  /// milestones. Filtered against `s.badgeIds` so the marker XP matches the
  /// badges actually shown.
  static int _markerCount(GameState s, int finalLevel, int odometerCount) {
    final tierCount = [
      for (final tier in tiersReachedBetween(s.level, finalLevel))
        if (!s.badgeIds.contains(tierBadgeId(tier.level))) tier,
    ].length;
    final comparisonCount = [
      for (final c
          in crossingsBetween(gm.paceKmh(s.level), gm.paceKmh(finalLevel)))
        if (!s.badgeIds.contains(comparisonBadgeId(c.id))) c,
    ].length;
    final mapCount = finalLevel > s.level &&
            !s.badgeIds.contains(mapBadgeId(mapIndexForLevel(finalLevel)))
        ? 1
        : 0;
    return tierCount + comparisonCount + mapCount + odometerCount;
  }

  /// Applies break recovery for [fraction] of the break (1.0 = full) and
  /// moves to breakComplete at [endedAtMs]. Computed from stamina at break
  /// start, so it is idempotent under reconstruction.
  static GameState _finishBreak(GameState s, double fraction, int endedAtMs) {
    final t = s.timer;
    final recovered =
        gm.recovery((fraction.clamp(0.0, 1.0) * t.plannedDurationMs).round());
    return s.copyWith(
      stamina:
          (t.staminaAtBreakStart + recovered).clamp(0.0, gm.kMaxStamina),
      // Passive idle recovery resumes from the break's end.
      staminaSyncedAtMs: endedAtMs,
      timer: TimerState(phase: Phase.breakComplete, breakKind: t.breakKind),
    );
  }

  /// True for phases where the focus timer is not running and stamina recovers
  /// at the long-break rate: between sessions (idle), after a finished session
  /// awaiting a break (focusComplete), after a finished break (breakComplete),
  /// and while a session is paused.
  static bool _restsBetweenFocus(Phase phase) =>
      phase == Phase.idle ||
      phase == Phase.focusPaused ||
      phase == Phase.focusComplete ||
      phase == Phase.breakComplete;

  /// Accrues long-break-rate recovery onto [s] from its last sync point up to
  /// [nowMs], for resting phases only (idle, paused, focusComplete,
  /// breakComplete). Idempotent: it always advances the sync point to [nowMs],
  /// so re-running it credits nothing new. A no-op (beyond anchoring the clock)
  /// for the running focus/break phases.
  static GameState _applyIdleRecovery(GameState s, int nowMs) {
    if (!_restsBetweenFocus(s.timer.phase)) return s;
    final since = s.staminaSyncedAtMs;
    // First reconciliation (fresh or migrated state): anchor the clock without
    // crediting recovery for time before the app knew about it.
    if (since <= 0) {
      return since == nowMs ? s : s.copyWith(staminaSyncedAtMs: nowMs);
    }
    if (nowMs <= since || s.stamina >= gm.kMaxStamina) {
      return s.copyWith(staminaSyncedAtMs: nowMs);
    }
    final recovered =
        (s.stamina + gm.recovery(nowMs - since)).clamp(0.0, gm.kMaxStamina);
    return s.copyWith(stamina: recovered, staminaSyncedAtMs: nowMs);
  }

  static Map<String, int> _addDailyMinutes(
      Map<String, int> daily, String key, int minutes) {
    if (minutes <= 0) return daily;
    final updated = {...daily, key: (daily[key] ?? 0) + minutes};
    // Prune to the most recent 60 days to keep the document small.
    if (updated.length > 60) {
      final keys = updated.keys.toList()..sort();
      for (final k in keys.take(updated.length - 60)) {
        updated.remove(k);
      }
    }
    return updated;
  }
}
