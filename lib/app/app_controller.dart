/// The single source of app state: owns the persisted [GameState], applies
/// engine transitions, keeps the wall-clock ticker, and performs the side
/// effects (persistence, notifications, chime).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../core/game_math.dart' as gm;
import '../core/models.dart';
import '../core/session_engine.dart';
import '../data/persistence.dart';
import 'audio.dart';
import 'notifications.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this._persistence,
    required this._notifications,
    required this._chime,
  }) {
    _state = _persistence.load();
    // Reconstruct at launch: phases that completed while the app was dead
    // resolve now (the scheduled notification already announced them).
    final next = Engine.reconstruct(_state, nowMs);
    if (!identical(next, _state)) {
      _state = next;
      unawaited(_persistence.save(next));
    }
    _syncTicker();
  }

  final Persistence _persistence;
  final NotificationService _notifications;
  final ChimePlayer _chime;

  late GameState _state;
  GameState get state => _state;

  /// A fresh random offset into the accent palettes, rolled once per app
  /// launch — so each time the app opens it lands on a different place's
  /// colour, then keeps stepping from there as sessions complete.
  final int accentSeed = Random().nextInt(1 << 30);

  Timer? _ticker;
  bool _foreground = true;
  bool _permissionRequested = false;

  int get nowMs => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// Called on every AppLifecycleState.resumed and at launch: re-derive the
  /// true state from wall-clock timestamps.
  void onAppResumed() {
    _foreground = true;
    final next = Engine.reconstruct(_state, nowMs);
    if (!identical(next, _state)) {
      // Completed while away — the notification announced it; no chime now.
      _apply(next);
    } else {
      _syncTicker();
      notifyListeners();
    }
  }

  void onAppPaused() {
    _foreground = false;
    _ticker?.cancel();
    _ticker = null;
    // Save the latest (e.g. idle-recovered) stamina. Re-derivable from the sync
    // point regardless, but persisting keeps the on-disk snapshot current.
    unawaited(_persistence.save(_state));
  }

  // ---------------------------------------------------------------------
  // User actions — each is an engine transition plus side effects
  // ---------------------------------------------------------------------

  Future<void> startFocus() async {
    final phase = _state.timer.phase;
    if (phase != Phase.idle && phase != Phase.breakComplete) return;
    await _ensureNotificationPermission();
    final next = Engine.startFocus(_state, nowMs);
    _apply(next);
    _schedulePhaseEndNotification(next);
  }

  void pauseFocus() {
    final next = Engine.pauseFocus(_state, nowMs);
    if (identical(next, _state)) return;
    _apply(next);
    unawaited(_notifications.cancelPhaseEnd());
  }

  void resumeFocus() {
    final next = Engine.resumeFocus(_state, nowMs);
    if (identical(next, _state)) return;
    _apply(next);
    _schedulePhaseEndNotification(next);
  }

  void endFocusEarly() {
    final next = Engine.endFocusEarly(_state, nowMs);
    if (identical(next, _state)) return;
    unawaited(_notifications.cancelPhaseEnd());
    _apply(next);
  }

  void startBreak() {
    final next = Engine.startBreak(_state, nowMs);
    if (identical(next, _state)) return;
    _apply(next);
    _schedulePhaseEndNotification(next);
  }

  void skipBreak() {
    _apply(Engine.skipBreak(_state));
  }

  /// One tap from a running break straight into the next focus session:
  /// partial recovery is applied for the rest actually taken (pillar 2 —
  /// nothing ever blocks starting a session).
  Future<void> startFocusDuringBreak() async {
    if (_state.timer.phase != Phase.breakRunning) return;
    await _ensureNotificationPermission();
    final now = nowMs;
    final next = Engine.startFocus(Engine.endBreakEarly(_state, now), now);
    unawaited(_notifications.cancelPhaseEnd());
    _apply(next);
    _schedulePhaseEndNotification(next);
  }

  void acknowledgeReveal() {
    if (_state.pendingReveal == null) return;
    _apply(Engine.acknowledgeReveal(_state));
  }

  // ---------------------------------------------------------------------
  // Settings
  // ---------------------------------------------------------------------

  void setTheme(ThemePreference theme) {
    _apply(_state.copyWith(
        settings: _state.settings.copyWith(theme: theme)));
  }

  void setSoundEnabled(bool enabled) {
    _apply(_state.copyWith(
        settings: _state.settings.copyWith(soundEnabled: enabled)));
  }

  /// Updates the configured pomodoro durations (minutes), clamped to bounds.
  /// Takes effect on the next phase the user starts; an in-flight phase keeps
  /// its own planned length.
  void setDurations({int? focusMinutes, int? shortBreakMinutes, int? longBreakMinutes}) {
    final s = _state.settings;
    _apply(_state.copyWith(
      settings: s.copyWith(
        focusMinutes: focusMinutes == null
            ? null
            : gm.clampMinutes(
                focusMinutes, gm.kFocusMinMinutes, gm.kFocusMaxMinutes),
        shortBreakMinutes: shortBreakMinutes == null
            ? null
            : gm.clampMinutes(shortBreakMinutes, gm.kShortBreakMinMinutes,
                gm.kShortBreakMaxMinutes),
        longBreakMinutes: longBreakMinutes == null
            ? null
            : gm.clampMinutes(longBreakMinutes, gm.kLongBreakMinMinutes,
                gm.kLongBreakMaxMinutes),
      ),
    ));
  }

  void setNotificationsEnabled(bool enabled) {
    _apply(_state.copyWith(
        settings: _state.settings.copyWith(notificationsEnabled: enabled)));
    if (!enabled) {
      unawaited(_notifications.cancelPhaseEnd());
    } else {
      unawaited(_ensureNotificationPermission());
      _schedulePhaseEndNotification(_state);
    }
  }

  Future<void> resetData() async {
    await _notifications.cancelPhaseEnd();
    await _persistence.reset();
    _state = GameState.initial;
    _syncTicker();
    notifyListeners();
  }

  // ---------------------------------------------------------------------
  // Display helpers
  // ---------------------------------------------------------------------

  /// Stamina for the quiet bar, with the live projection the engine will
  /// apply at phase end: draining during focus, recovering during breaks.
  double displayStamina() {
    final t = _state.timer;
    final now = nowMs;
    switch (t.phase) {
      case Phase.focusRunning:
        final segmentMs = (now - (t.segmentStartedAtMs ?? now))
            .clamp(0, t.plannedDurationMs - t.accumulatedFocusMs);
        final drain = gm.drainFor(
          level: t.levelAtSessionStart,
          elapsedFocusMs: segmentMs,
          focusDurationMs: t.plannedDurationMs,
        );
        return (_state.stamina - drain).clamp(0.0, gm.kMaxStamina);
      case Phase.breakRunning:
        final total = t.plannedDurationMs;
        final fraction =
            ((now - (t.segmentStartedAtMs ?? now)) / total).clamp(0.0, 1.0);
        final recovery = gm.breakRecovery(
          isLong: t.breakKind == BreakKind.long,
          level: _state.level,
          staminaAtBreakStart: t.staminaAtBreakStart,
          fraction: fraction,
        );
        return (t.staminaAtBreakStart + recovery).clamp(0.0, gm.kMaxStamina);
      case Phase.focusPaused:
        // Pausing freezes the bar — no drain, no recovery.
        return _state.stamina;
      case Phase.idle:
      case Phase.focusComplete:
      case Phase.breakComplete:
        // Resting: project passive idle recovery accrued since the last sync.
        final since = _state.staminaSyncedAtMs;
        if (since <= 0 || _state.stamina >= gm.kMaxStamina) {
          return _state.stamina;
        }
        return (_state.stamina + gm.idleRecovery(now - since))
            .clamp(0.0, gm.kMaxStamina);
    }
  }

  // ---------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------

  void _apply(GameState next) {
    _state = next;
    unawaited(_persistence.save(next));
    _syncTicker();
    notifyListeners();
  }

  /// A 1 Hz wall-clock check while a phase is running and the app is
  /// foregrounded — purely for live countdown display and live completion.
  /// Correctness never depends on it; reconstruction covers every gap.
  void _syncTicker() {
    final phase = _state.timer.phase;
    final running =
        phase == Phase.focusRunning || phase == Phase.breakRunning;
    // While resting between sessions, tick to accrue passive idle recovery so
    // the stamina bar climbs live — until it tops out.
    final recovering = _restingPhase(phase) &&
        _state.staminaSyncedAtMs > 0 &&
        _state.stamina < gm.kMaxStamina;
    if (_foreground && (running || recovering)) {
      _ticker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    } else {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  static bool _restingPhase(Phase phase) =>
      phase == Phase.idle ||
      phase == Phase.focusComplete ||
      phase == Phase.breakComplete;

  void _tick() {
    final t = _state.timer;
    final running =
        t.phase == Phase.focusRunning || t.phase == Phase.breakRunning;
    if (!running) {
      // Resting: accrue idle recovery. Deterministic from the persisted sync
      // point, so we update in-memory and notify without a per-second write.
      if (_restingPhase(t.phase) && _state.stamina < gm.kMaxStamina) {
        final next = Engine.reconstruct(_state, nowMs);
        if (!identical(next, _state)) {
          _state = next;
          notifyListeners();
        }
      }
      _syncTicker(); // stops the ticker once the bar is full
      return;
    }
    if (nowMs >= t.phaseEndsAtMs!) {
      // Live completion: cancel the scheduled banner inside its grace
      // window — the in-app reveal (and optional chime) announces it.
      unawaited(_notifications.cancelPhaseEnd());
      _apply(Engine.reconstruct(_state, nowMs));
      if (_state.settings.soundEnabled) {
        unawaited(_chime.play());
      }
    } else {
      notifyListeners(); // countdown repaint
    }
  }

  void _schedulePhaseEndNotification(GameState s) {
    if (!s.settings.notificationsEnabled) return;
    final t = s.timer;
    if (t.phaseEndsAtMs == null) return;
    final isFocus = t.phase == Phase.focusRunning;
    if (!isFocus && t.phase != Phase.breakRunning) return;
    unawaited(_notifications.schedulePhaseEnd(
      atMs: t.phaseEndsAtMs!,
      title: isFocus ? 'Focus complete' : 'Break over',
      body: isFocus
          ? 'The road carried you onward. Time to rest.'
          : 'The road waits, whenever you are ready.',
    ));
  }

  Future<void> _ensureNotificationPermission() async {
    if (_permissionRequested || !_state.settings.notificationsEnabled) return;
    _permissionRequested = true;
    await _notifications.requestPermissionOnce();
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _chime.dispose();
    super.dispose();
  }
}
