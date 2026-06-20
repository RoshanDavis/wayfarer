/// The single source of app state: owns the persisted [GameState], applies
/// engine transitions, keeps the wall-clock ticker, and performs the side
/// effects (persistence, notifications).
library;

import 'dart:async';
import 'dart:math';

import 'package:flutter/widgets.dart';

import '../core/game_math.dart' as gm;
import '../core/models.dart';
import '../core/session_engine.dart';
import '../data/persistence.dart';
import 'notifications.dart';

class AppController extends ChangeNotifier {
  AppController({
    required this._persistence,
    required this._notifications,
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
    // If the app cold-started mid-session, surface the ongoing status now (it
    // shows in the foreground too, not only when backgrounded).
    _syncSessionActiveNotification();
    unawaited(_initNotifications());
  }

  final Persistence _persistence;
  final NotificationService _notifications;

  late GameState _state;
  GameState get state => _state;

  /// A fresh offset into the accent palettes, rolled once per launch so each
  /// open lands on a different place's colour (see accentForSession).
  final int accentSeed = Random().nextInt(1 << 30);

  Timer? _ticker;
  bool _foreground = true;

  /// Whether the OS currently lets the app post notifications. Refreshed at
  /// launch, on resume, and after each permission request; drives the Settings
  /// "blocked" hint.
  bool _notificationsAuthorized = false;
  bool get notificationsAuthorized => _notificationsAuthorized;

  int get nowMs => DateTime.now().millisecondsSinceEpoch;

  // ---------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------

  /// Called on every AppLifecycleState.resumed and at launch: re-derive the
  /// true state from wall-clock timestamps.
  void onAppResumed() {
    _foreground = true;
    // Drop the pending scheduled alarm: while the app is open the live tick
    // posts the completion alert itself, so the scheduled one must not also
    // fire after its grace window. (onAppPaused re-schedules it on the way out.)
    // The ongoing status is left up — it shows in the foreground too now.
    unawaited(_notifications.cancelPhaseEnd());
    // The user may have flipped the OS permission while away (e.g. via the
    // settings deep-link); re-read it so the hint stays accurate.
    unawaited(_refreshNotificationPermission());
    final next = Engine.reconstruct(_state, nowMs);
    if (!identical(next, _state)) {
      // Completed while away — the notification announced it; no chime now.
      _apply(next);
    } else {
      _syncTicker();
      // Reschedule the alarm we just cancelled, and keep the ongoing status up.
      _schedulePhaseEndNotification(_state);
      _syncSessionActiveNotification();
      notifyListeners();
    }
  }

  void onAppPaused() {
    _foreground = false;
    _ticker?.cancel();
    _ticker = null;
    _tickerInterval = null;
    // Save the latest (e.g. idle-recovered) stamina. Re-derivable from the sync
    // point regardless, but persisting keeps the on-disk snapshot current.
    unawaited(_persistence.save(_state));
    // (Re)schedule the completion alert so it fires even if the alarm was never
    // set this run (e.g. cold-started mid-session); idempotent, same id replaces.
    _schedulePhaseEndNotification(_state);
    _showSessionActiveNotification();
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

  Future<void> setNotificationsEnabled(bool enabled) async {
    _apply(_state.copyWith(
        settings: _state.settings.copyWith(notificationsEnabled: enabled)));
    if (!enabled) {
      unawaited(_notifications.cancelPhaseEnd());
      unawaited(_notifications.cancelSessionActive());
      return;
    }
    // Enabling is the natural moment to ask: the OS shows its permission dialog
    // here. Schedule only once we actually hold the permission; if it's blocked
    // the Settings hint guides the user to re-enable it.
    _notificationsAuthorized = await _notifications.ensurePermission();
    notifyListeners();
    if (_notificationsAuthorized) _schedulePhaseEndNotification(_state);
  }

  Future<void> resetData() async {
    await _notifications.cancelPhaseEnd();
    await _notifications.cancelSessionActive();
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
        final elapsed = (now - (t.segmentStartedAtMs ?? now))
            .clamp(0, t.plannedDurationMs);
        final recovered = gm.recovery(elapsed);
        return (t.staminaAtBreakStart + recovered).clamp(0.0, gm.kMaxStamina);
      case Phase.focusPaused:
      case Phase.idle:
      case Phase.focusComplete:
      case Phase.breakComplete:
        // Resting (incl. paused): project long-break-rate recovery accrued
        // since the last sync point.
        final since = _state.staminaSyncedAtMs;
        if (since <= 0 || _state.stamina >= gm.kMaxStamina) {
          return _state.stamina;
        }
        return (_state.stamina + gm.recovery(now - since))
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
    _syncSessionActiveNotification();
    notifyListeners();
  }

  /// 1 Hz while a phase is running (live countdown/completion); a calmer 0.2 Hz
  /// while only stamina is recovering between sessions. Correctness never depends
  /// on the ticker — reconstruction covers every gap.
  static const Duration _runningTickInterval = Duration(seconds: 1);
  static const Duration _recoveryTickInterval = Duration(seconds: 5);

  /// The period of the currently active [_ticker], or null when it is stopped —
  /// kept in lockstep with [_ticker] so [_syncTicker] only rebuilds the timer
  /// when the required cadence actually changes.
  Duration? _tickerInterval;

  void _syncTicker() {
    final phase = _state.timer.phase;
    final running =
        phase == Phase.focusRunning || phase == Phase.breakRunning;
    // While resting between sessions, tick to accrue passive idle recovery so
    // the stamina bar climbs live — until it tops out. The bar moves slowly
    // enough that 5 s steps read the same as 1 s while sparing ~5× the wake-ups
    // when the user lingers on the screen after a session.
    final recovering = Engine.restsBetweenFocus(phase) &&
        _state.staminaSyncedAtMs > 0 &&
        _state.stamina < gm.kMaxStamina;
    final desired = !_foreground
        ? null
        : running
            ? _runningTickInterval
            : recovering
                ? _recoveryTickInterval
                : null;
    if (desired == _tickerInterval) return;
    _ticker?.cancel();
    _tickerInterval = desired;
    _ticker =
        desired == null ? null : Timer.periodic(desired, (_) => _tick());
  }

  void _tick() {
    final t = _state.timer;
    final running =
        t.phase == Phase.focusRunning || t.phase == Phase.breakRunning;
    if (!running) {
      // Resting: accrue idle recovery. Deterministic from the persisted sync
      // point, so we update in-memory and notify without a per-second write.
      if (Engine.restsBetweenFocus(t.phase) && _state.stamina < gm.kMaxStamina) {
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
      // Live completion with the app open: drop the scheduled alarm (so it can't
      // double-fire) and post the alert live alongside the in-app reveal.
      unawaited(_notifications.cancelPhaseEnd());
      _showPhaseEndNotificationNow(_state);
      _apply(Engine.reconstruct(_state, nowMs));
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

  void _showSessionActiveNotification() {
    if (!_state.settings.notificationsEnabled) return;
    final t = _state.timer;
    if (t.phaseEndsAtMs == null) return;
    final isFocus = t.phase == Phase.focusRunning;
    if (!isFocus && t.phase != Phase.breakRunning) return;

    final dt = DateTime.fromMillisecondsSinceEpoch(t.phaseEndsAtMs!).toLocal();
    final hourVal = dt.hour;
    final amPm = hourVal >= 12 ? 'PM' : 'AM';
    final displayHour = hourVal == 0 ? 12 : (hourVal > 12 ? hourVal - 12 : hourVal);
    final minuteStr = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$displayHour:$minuteStr $amPm';

    unawaited(_notifications.showSessionActive(
      title: isFocus ? 'Focus session active' : 'Break active',
      body: isFocus ? 'Focusing until $timeStr.' : 'Resting until $timeStr.',
      timeoutAfterMs: t.phaseEndsAtMs! - nowMs,
    ));
  }

  /// Keeps the quiet, ongoing "session in progress" status in sync with the
  /// phase: shown whenever a focus or break is running — in the foreground as
  /// well as the background — and cleared otherwise. Driven from [_apply] (every
  /// transition), launch, and resume.
  void _syncSessionActiveNotification() {
    final phase = _state.timer.phase;
    if (phase == Phase.focusRunning || phase == Phase.breakRunning) {
      _showSessionActiveNotification();
    } else {
      unawaited(_notifications.cancelSessionActive());
    }
  }

  /// Posts the completion alert immediately when a phase ends while the app is
  /// open, so the banner and chime fire in the foreground just as they do in
  /// the background. Read [s] before reconstruct, while the phase is still
  /// running, so the wording matches the phase that is ending.
  void _showPhaseEndNotificationNow(GameState s) {
    if (!s.settings.notificationsEnabled || !_notificationsAuthorized) return;
    final t = s.timer;
    final isFocus = t.phase == Phase.focusRunning;
    if (!isFocus && t.phase != Phase.breakRunning) return;
    unawaited(_notifications.showPhaseEnd(
      title: isFocus ? 'Focus complete' : 'Break over',
      body: isFocus
          ? 'The road carried you onward. Time to rest.'
          : 'The road waits, whenever you are ready.',
    ));
  }

  Future<void> _ensureNotificationPermission() async {
    if (!_state.settings.notificationsEnabled) return;
    _notificationsAuthorized = await _notifications.ensurePermission();
    notifyListeners();
  }

  /// Notification setup at launch: if the user wants alerts but POST_NOTIFICATIONS
  /// isn't granted, ask once the first frame is up (surfaces Android 13+'s dialog
  /// on fresh install). The request is a no-op once decided, so it's safe every
  /// launch and deliberately NOT gated on a first-run flag — a stray early save
  /// could wrongly clear that and suppress the prompt forever. Denial is recovered
  /// via the Settings "blocked" hint, never by auto-disabling the toggle.
  Future<void> _initNotifications() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // The OS only shows its permission dialog for a resumed, focused
      // activity; a short settle keeps the request from being silently dropped
      // during the launch transition on physical devices.
      await Future.delayed(const Duration(milliseconds: 500));
      _notificationsAuthorized = _state.settings.notificationsEnabled
          ? await _notifications.ensurePermission()
          : await _notifications.areEnabled();
      notifyListeners();
    });
  }

  /// Re-reads the OS permission state (e.g. after the user toggles it in system
  /// settings and returns) so the Settings hint reflects reality.
  Future<void> _refreshNotificationPermission() async {
    final authorized = await _notifications.areEnabled();
    if (authorized != _notificationsAuthorized) {
      _notificationsAuthorized = authorized;
      notifyListeners();
    }
  }

  /// Opens the app's system notification settings — the recovery path when the
  /// permission has been denied and the OS will no longer show its dialog.
  Future<void> openNotificationSettings() =>
      _notifications.openSystemSettings();

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
