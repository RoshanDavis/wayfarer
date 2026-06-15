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
      staminaAtSessionStart: t.staminaAtSessionStart,
      elapsedFocusMs: segmentMs,
    );
    final drain = gm.drainFor(
      level: t.levelAtSessionStart,
      elapsedFocusMs: segmentMs,
      focusDurationMs: t.plannedDurationMs,
    );
    return s.copyWith(
      stamina: (s.stamina - drain).clamp(0.0, gm.kMaxStamina),
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
    final t = s.timer;
    if (t.phase != Phase.focusPaused) return s;
    return s.copyWith(
      timer: t.copyWith(
        phase: Phase.focusRunning,
        segmentStartedAtMs: nowMs,
        phaseEndsAtMs: nowMs + (t.plannedDurationMs - t.accumulatedFocusMs),
      ),
    );
  }

  /// Ends a focus session early. Distance traveled is awarded (never
  /// confiscated); no XP, no set progress. Valid from running or paused.
  static GameState endFocusEarly(GameState s, int nowMs) {
    var state = s;
    if (state.timer.phase == Phase.focusRunning) {
      if (nowMs >= state.timer.phaseEndsAtMs!) return reconstruct(s, nowMs);
      state = pauseFocus(state, nowMs);
    }
    final t = state.timer;
    if (t.phase != Phase.focusPaused) return s;

    final distance = t.bankedDistanceKm;
    final elapsedMs = t.accumulatedFocusMs;
    final oldKm = state.lifetimeKm;
    final newKm = oldKm + distance;
    final odoBadges = [
      for (final m in milestonesCrossedBetween(oldKm, newKm))
        if (!state.badgeIds.contains(m.id)) m.id,
    ];
    return state.copyWith(
      lifetimeKm: newKm,
      totalFocusSeconds: state.totalFocusSeconds + elapsedMs ~/ 1000,
      badgeIds: {...state.badgeIds, ...odoBadges},
      dailyFocusMinutes: _addDailyMinutes(
          state.dailyFocusMinutes, dateKey(nowMs), elapsedMs ~/ 60000),
      staminaSyncedAtMs: nowMs,
      timer: TimerState.idle,
      pendingReveal: RevealSequence(
        distanceKm: distance,
        sessionCompleted: false,
        levelBefore: state.level,
        levelAfter: state.level,
        badgeIds: odoBadges,
        nextAction: NextAction.focus,
      ),
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
          staminaAtSessionStart: t.staminaAtSessionStart,
          elapsedFocusMs: segmentMs,
        );
    final drain = gm.drainFor(
      level: t.levelAtSessionStart,
      elapsedFocusMs: segmentMs,
      focusDurationMs: focusDurationMs,
    );
    final stamina = (s.stamina - drain).clamp(0.0, gm.kMaxStamina);

    // Set and session counting. A session only counts when fully completed.
    final completedSet = s.sessionIndexInSet == gm.kSessionsPerSet - 1;
    final newSessionIndex = (s.sessionIndexInSet + 1) % gm.kSessionsPerSet;
    final newSets = s.setsCompleted + (completedSet ? 1 : 0);

    // XP and level-ups.
    final xpGained = gm.kXpPerSession + (completedSet ? gm.kXpSetBonus : 0);
    final progress = gm.applyXp(
        level: s.level, xpIntoLevel: s.xpIntoLevel, gained: xpGained);

    // Tier crossings.
    final tiers = tiersReachedBetween(s.level, progress.level);

    // Speed-comparison crossings (awarded exactly once via the badge set).
    final crossings = [
      for (final c
          in crossingsBetween(gm.paceKmh(s.level), gm.paceKmh(progress.level)))
        if (!s.badgeIds.contains(comparisonBadgeId(c.id))) c,
    ];

    // Map progression: changes exactly every kSetsPerMap completed sets.
    int? newMapIndex;
    if (completedSet && mapChangedAtSet(newSets)) {
      newMapIndex = mapIndexForSets(newSets);
    }

    // Odometer milestones.
    final oldKm = s.lifetimeKm;
    final newKm = oldKm + distance;
    final milestones = [
      for (final m in milestonesCrossedBetween(oldKm, newKm))
        if (!s.badgeIds.contains(m.id)) m,
    ];

    // Badges, in reveal order: tier, map, comparison, odometer.
    final newBadgeIds = <String>[
      for (final tier in tiers)
        if (!s.badgeIds.contains(tierBadgeId(tier.level))) tierBadgeId(tier.level),
      if (newMapIndex != null && !s.badgeIds.contains(mapBadgeId(newMapIndex)))
        mapBadgeId(newMapIndex),
      for (final c in crossings) comparisonBadgeId(c.id),
      for (final m in milestones) m.id,
    ];

    final nextBreak = newSessionIndex == 0 ? BreakKind.long : BreakKind.short;

    return s.copyWith(
      stamina: stamina,
      lifetimeKm: newKm,
      totalFocusSeconds: s.totalFocusSeconds + focusDurationMs ~/ 1000,
      sessionsCompleted: s.sessionsCompleted + 1,
      setsCompleted: newSets,
      sessionIndexInSet: newSessionIndex,
      xpIntoLevel: progress.xpIntoLevel,
      level: progress.level,
      badgeIds: {...s.badgeIds, ...newBadgeIds},
      dailyFocusMinutes: _addDailyMinutes(
          s.dailyFocusMinutes, dateKey(endMs), focusDurationMs ~/ 60000),
      // Idle recovery accrues from the moment focus ended, not from when we
      // noticed — so a late wake-up still credits the full rest since.
      staminaSyncedAtMs: endMs,
      timer: TimerState(phase: Phase.focusComplete, breakKind: nextBreak),
      pendingReveal: RevealSequence(
        distanceKm: distance,
        sessionCompleted: true,
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

  /// Applies break recovery for [fraction] of the break (1.0 = full) and
  /// moves to breakComplete at [endedAtMs]. Computed from stamina at break
  /// start, so it is idempotent under reconstruction.
  static GameState _finishBreak(GameState s, double fraction, int endedAtMs) {
    final t = s.timer;
    final recovery = gm.breakRecovery(
      isLong: t.breakKind == BreakKind.long,
      level: s.level,
      staminaAtBreakStart: t.staminaAtBreakStart,
      fraction: fraction,
    );
    return s.copyWith(
      stamina:
          (t.staminaAtBreakStart + recovery).clamp(0.0, gm.kMaxStamina),
      // Passive idle recovery resumes from the break's end.
      staminaSyncedAtMs: endedAtMs,
      timer: TimerState(phase: Phase.breakComplete, breakKind: t.breakKind),
    );
  }

  /// True for phases where the focus timer is not running and stamina passively
  /// recovers: between sessions (idle), after a finished session awaiting a
  /// break (focusComplete), and after a finished break (breakComplete). A
  /// *paused* session is deliberately excluded — pausing freezes everything.
  static bool _restsBetweenFocus(Phase phase) =>
      phase == Phase.idle ||
      phase == Phase.focusComplete ||
      phase == Phase.breakComplete;

  /// Accrues passive idle recovery onto [s] from its last sync point up to
  /// [nowMs], for resting phases only. Idempotent: it always advances the sync
  /// point to [nowMs], so re-running it credits nothing new. A no-op (beyond
  /// anchoring the clock) for running or paused phases.
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
        (s.stamina + gm.idleRecovery(nowMs - since)).clamp(0.0, gm.kMaxStamina);
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
