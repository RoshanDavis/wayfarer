/// State models for Wayfarer. Pure Dart, JSON-serializable.
///
/// All time fields are wall-clock epoch milliseconds — the app never depends
/// on running timers for correctness; state is always reconstructible from
/// these timestamps.
library;

import 'game_math.dart' as gm;

/// The explicit pomodoro state machine. Phases never auto-chain: every
/// running phase begins with a user tap (the game's one decision).
enum Phase {
  idle,
  focusRunning,
  focusPaused,

  /// A focus session finished; its reveal is pending or showing.
  focusComplete,
  breakRunning,

  /// A break finished (fully or ended early); next focus awaits a tap.
  breakComplete,
}

enum BreakKind { short, long }

/// What the single continue button starts next.
enum NextAction { shortBreak, longBreak, focus }

// ---------------------------------------------------------------------------
// TimerState
// ---------------------------------------------------------------------------

/// Wall-clock snapshot of the current pomodoro phase.
class TimerState {
  final Phase phase;

  /// Set during breakRunning/breakComplete.
  final BreakKind? breakKind;

  /// Wall-clock start of the current running segment (focusRunning or
  /// breakRunning); null otherwise.
  final int? segmentStartedAtMs;

  /// Wall-clock scheduled end of the running phase; null otherwise.
  final int? phaseEndsAtMs;

  /// Focus milliseconds banked from segments before the current one
  /// (accumulates across pauses within one session).
  final int accumulatedFocusMs;

  /// Distance banked at pauses for the in-flight session.
  final double bankedDistanceKm;

  /// Stamina at session start — fixes the speed modifier for the session.
  final double staminaAtSessionStart;

  /// Level at session start — fixes the pace for the session.
  final int levelAtSessionStart;

  /// Stamina when the current break started — recovery accrues from here.
  final double staminaAtBreakStart;

  /// Planned length of the in-flight phase in ms (set at start). Self-contained
  /// so reconstruction stays correct even if the user edits durations later.
  final int plannedDurationMs;

  const TimerState({
    required this.phase,
    this.breakKind,
    this.segmentStartedAtMs,
    this.phaseEndsAtMs,
    this.accumulatedFocusMs = 0,
    this.bankedDistanceKm = 0,
    this.staminaAtSessionStart = gm.kMaxStamina,
    this.levelAtSessionStart = 1,
    this.staminaAtBreakStart = gm.kMaxStamina,
    this.plannedDurationMs = gm.kFocusMs,
  });

  static const idle = TimerState(phase: Phase.idle);

  /// Total focus ms elapsed in the in-flight session as of [nowMs],
  /// clamped to the planned session length.
  int elapsedFocusMs(int nowMs) {
    var elapsed = accumulatedFocusMs;
    if (phase == Phase.focusRunning && segmentStartedAtMs != null) {
      elapsed += (nowMs - segmentStartedAtMs!).clamp(0, plannedDurationMs);
    }
    return elapsed.clamp(0, plannedDurationMs);
  }

  /// Remaining ms in the running or paused phase as of [nowMs]; 0 elsewhere.
  int remainingMs(int nowMs) {
    switch (phase) {
      case Phase.focusRunning:
      case Phase.breakRunning:
        return (phaseEndsAtMs! - nowMs).clamp(0, plannedDurationMs);
      case Phase.focusPaused:
        return plannedDurationMs - accumulatedFocusMs;
      case Phase.idle:
      case Phase.focusComplete:
      case Phase.breakComplete:
        return 0;
    }
  }

  TimerState copyWith({
    Phase? phase,
    BreakKind? breakKind,
    int? segmentStartedAtMs,
    int? phaseEndsAtMs,
    int? accumulatedFocusMs,
    double? bankedDistanceKm,
    double? staminaAtSessionStart,
    int? levelAtSessionStart,
    double? staminaAtBreakStart,
    int? plannedDurationMs,
    bool clearSegment = false,
  }) =>
      TimerState(
        phase: phase ?? this.phase,
        breakKind: breakKind ?? this.breakKind,
        segmentStartedAtMs:
            clearSegment ? null : segmentStartedAtMs ?? this.segmentStartedAtMs,
        phaseEndsAtMs: clearSegment ? null : phaseEndsAtMs ?? this.phaseEndsAtMs,
        accumulatedFocusMs: accumulatedFocusMs ?? this.accumulatedFocusMs,
        bankedDistanceKm: bankedDistanceKm ?? this.bankedDistanceKm,
        staminaAtSessionStart:
            staminaAtSessionStart ?? this.staminaAtSessionStart,
        levelAtSessionStart: levelAtSessionStart ?? this.levelAtSessionStart,
        staminaAtBreakStart: staminaAtBreakStart ?? this.staminaAtBreakStart,
        plannedDurationMs: plannedDurationMs ?? this.plannedDurationMs,
      );

  Map<String, Object?> toJson() => {
        'phase': phase.name,
        'breakKind': breakKind?.name,
        'segmentStartedAtMs': segmentStartedAtMs,
        'phaseEndsAtMs': phaseEndsAtMs,
        'accumulatedFocusMs': accumulatedFocusMs,
        'bankedDistanceKm': bankedDistanceKm,
        'staminaAtSessionStart': staminaAtSessionStart,
        'levelAtSessionStart': levelAtSessionStart,
        'staminaAtBreakStart': staminaAtBreakStart,
        'plannedDurationMs': plannedDurationMs,
      };

  factory TimerState.fromJson(Map<String, Object?> json) => TimerState(
        phase: Phase.values.byName(json['phase'] as String? ?? 'idle'),
        breakKind: json['breakKind'] == null
            ? null
            : BreakKind.values.byName(json['breakKind'] as String),
        segmentStartedAtMs: json['segmentStartedAtMs'] as int?,
        phaseEndsAtMs: json['phaseEndsAtMs'] as int?,
        accumulatedFocusMs: json['accumulatedFocusMs'] as int? ?? 0,
        bankedDistanceKm: (json['bankedDistanceKm'] as num?)?.toDouble() ?? 0,
        staminaAtSessionStart:
            (json['staminaAtSessionStart'] as num?)?.toDouble() ??
                gm.kMaxStamina,
        levelAtSessionStart: json['levelAtSessionStart'] as int? ?? 1,
        staminaAtBreakStart:
            (json['staminaAtBreakStart'] as num?)?.toDouble() ?? gm.kMaxStamina,
        plannedDurationMs: json['plannedDurationMs'] as int? ?? gm.kFocusMs,
      );
}

// ---------------------------------------------------------------------------
// RevealSequence
// ---------------------------------------------------------------------------

/// Everything the session-end screen reveals, in spec order. Persisted until
/// acknowledged so process death never loses a reward.
class RevealSequence {
  final double distanceKm;

  /// False for an early end — distance only, no XP, no set progress.
  final bool sessionCompleted;

  final int xpGained;
  final int levelBefore;
  final int levelAfter;

  /// Unlock levels of tiers reached this session (names resolve via tiers.dart).
  final List<int> tierLevelsReached;

  /// Ids of speed comparisons crossed this session.
  final List<String> comparisonIds;

  /// Set when the map changed: the new map index (0..23).
  final int? newMapIndex;

  /// All badge ids awarded this session, in reveal order.
  final List<String> badgeIds;

  /// What the single continue button starts.
  final NextAction nextAction;

  const RevealSequence({
    required this.distanceKm,
    required this.sessionCompleted,
    this.xpGained = 0,
    required this.levelBefore,
    required this.levelAfter,
    this.tierLevelsReached = const [],
    this.comparisonIds = const [],
    this.newMapIndex,
    this.badgeIds = const [],
    required this.nextAction,
  });

  bool get leveledUp => levelAfter > levelBefore;

  Map<String, Object?> toJson() => {
        'distanceKm': distanceKm,
        'sessionCompleted': sessionCompleted,
        'xpGained': xpGained,
        'levelBefore': levelBefore,
        'levelAfter': levelAfter,
        'tierLevelsReached': tierLevelsReached,
        'comparisonIds': comparisonIds,
        'newMapIndex': newMapIndex,
        'badgeIds': badgeIds,
        'nextAction': nextAction.name,
      };

  factory RevealSequence.fromJson(Map<String, Object?> json) => RevealSequence(
        distanceKm: (json['distanceKm'] as num).toDouble(),
        sessionCompleted: json['sessionCompleted'] as bool? ?? false,
        xpGained: json['xpGained'] as int? ?? 0,
        levelBefore: json['levelBefore'] as int? ?? 1,
        levelAfter: json['levelAfter'] as int? ?? 1,
        tierLevelsReached: [
          ...(json['tierLevelsReached'] as List? ?? const []).cast<int>()
        ],
        comparisonIds: [
          ...(json['comparisonIds'] as List? ?? const []).cast<String>()
        ],
        newMapIndex: json['newMapIndex'] as int?,
        badgeIds: [...(json['badgeIds'] as List? ?? const []).cast<String>()],
        nextAction:
            NextAction.values.byName(json['nextAction'] as String? ?? 'focus'),
      );
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

enum ThemePreference { system, light, dark }

class Settings {
  final ThemePreference theme;
  final bool soundEnabled;
  final bool notificationsEnabled;

  /// User-configurable pomodoro durations, in minutes.
  final int focusMinutes;
  final int shortBreakMinutes;
  final int longBreakMinutes;

  const Settings({
    this.theme = ThemePreference.system,
    this.soundEnabled = false,
    this.notificationsEnabled = true,
    this.focusMinutes = gm.kFocusMinutes,
    this.shortBreakMinutes = gm.kShortBreakMinutes,
    this.longBreakMinutes = gm.kLongBreakMinutes,
  });

  int get focusMs => focusMinutes * 60 * 1000;
  int get shortBreakMs => shortBreakMinutes * 60 * 1000;
  int get longBreakMs => longBreakMinutes * 60 * 1000;

  Settings copyWith({
    ThemePreference? theme,
    bool? soundEnabled,
    bool? notificationsEnabled,
    int? focusMinutes,
    int? shortBreakMinutes,
    int? longBreakMinutes,
  }) =>
      Settings(
        theme: theme ?? this.theme,
        soundEnabled: soundEnabled ?? this.soundEnabled,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        focusMinutes: focusMinutes ?? this.focusMinutes,
        shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
        longBreakMinutes: longBreakMinutes ?? this.longBreakMinutes,
      );

  Map<String, Object?> toJson() => {
        'theme': theme.name,
        'soundEnabled': soundEnabled,
        'notificationsEnabled': notificationsEnabled,
        'focusMinutes': focusMinutes,
        'shortBreakMinutes': shortBreakMinutes,
        'longBreakMinutes': longBreakMinutes,
      };

  factory Settings.fromJson(Map<String, Object?> json) => Settings(
        theme: ThemePreference.values
            .byName(json['theme'] as String? ?? 'system'),
        soundEnabled: json['soundEnabled'] as bool? ?? false,
        notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
        focusMinutes: json['focusMinutes'] as int? ?? gm.kFocusMinutes,
        shortBreakMinutes:
            json['shortBreakMinutes'] as int? ?? gm.kShortBreakMinutes,
        longBreakMinutes:
            json['longBreakMinutes'] as int? ?? gm.kLongBreakMinutes,
      );
}

// ---------------------------------------------------------------------------
// GameState
// ---------------------------------------------------------------------------

/// The complete persisted state of the game.
class GameState {
  /// XP progress within the current level.
  final int xpIntoLevel;
  final int level;

  /// 0..100.
  final double stamina;

  /// Wall-clock time (epoch ms) at which [stamina] was last reconciled. Idle
  /// recovery accrues from here while not focusing; 0 means "not yet anchored".
  final int staminaSyncedAtMs;

  final double lifetimeKm;
  final int totalFocusSeconds;
  final int sessionsCompleted;
  final int setsCompleted;

  /// Completed sessions in the current set, 0..3.
  final int sessionIndexInSet;

  final Set<String> badgeIds;

  /// 'yyyy-MM-dd' (local) → focus minutes that day.
  final Map<String, int> dailyFocusMinutes;

  final TimerState timer;
  final RevealSequence? pendingReveal;
  final Settings settings;

  const GameState({
    this.xpIntoLevel = 0,
    this.level = 1,
    this.stamina = gm.kMaxStamina,
    this.staminaSyncedAtMs = 0,
    this.lifetimeKm = 0,
    this.totalFocusSeconds = 0,
    this.sessionsCompleted = 0,
    this.setsCompleted = 0,
    this.sessionIndexInSet = 0,
    this.badgeIds = const {},
    this.dailyFocusMinutes = const {},
    this.timer = TimerState.idle,
    this.pendingReveal,
    this.settings = const Settings(),
  });

  static const initial = GameState();

  double get paceKmh => gm.paceKmh(level);

  /// The break kind that follows the *next completed* focus session.
  BreakKind get upcomingBreakKind =>
      sessionIndexInSet == gm.kSessionsPerSet - 1 ? BreakKind.long : BreakKind.short;

  GameState copyWith({
    int? xpIntoLevel,
    int? level,
    double? stamina,
    int? staminaSyncedAtMs,
    double? lifetimeKm,
    int? totalFocusSeconds,
    int? sessionsCompleted,
    int? setsCompleted,
    int? sessionIndexInSet,
    Set<String>? badgeIds,
    Map<String, int>? dailyFocusMinutes,
    TimerState? timer,
    RevealSequence? pendingReveal,
    bool clearPendingReveal = false,
    Settings? settings,
  }) =>
      GameState(
        xpIntoLevel: xpIntoLevel ?? this.xpIntoLevel,
        level: level ?? this.level,
        stamina: stamina ?? this.stamina,
        staminaSyncedAtMs: staminaSyncedAtMs ?? this.staminaSyncedAtMs,
        lifetimeKm: lifetimeKm ?? this.lifetimeKm,
        totalFocusSeconds: totalFocusSeconds ?? this.totalFocusSeconds,
        sessionsCompleted: sessionsCompleted ?? this.sessionsCompleted,
        setsCompleted: setsCompleted ?? this.setsCompleted,
        sessionIndexInSet: sessionIndexInSet ?? this.sessionIndexInSet,
        badgeIds: badgeIds ?? this.badgeIds,
        dailyFocusMinutes: dailyFocusMinutes ?? this.dailyFocusMinutes,
        timer: timer ?? this.timer,
        pendingReveal: clearPendingReveal
            ? null
            : pendingReveal ?? this.pendingReveal,
        settings: settings ?? this.settings,
      );

  Map<String, Object?> toJson() => {
        'xpIntoLevel': xpIntoLevel,
        'level': level,
        'stamina': stamina,
        'staminaSyncedAtMs': staminaSyncedAtMs,
        'lifetimeKm': lifetimeKm,
        'totalFocusSeconds': totalFocusSeconds,
        'sessionsCompleted': sessionsCompleted,
        'setsCompleted': setsCompleted,
        'sessionIndexInSet': sessionIndexInSet,
        'badgeIds': badgeIds.toList(),
        'dailyFocusMinutes': dailyFocusMinutes,
        'timer': timer.toJson(),
        'pendingReveal': pendingReveal?.toJson(),
        'settings': settings.toJson(),
      };

  factory GameState.fromJson(Map<String, Object?> json) => GameState(
        xpIntoLevel: json['xpIntoLevel'] as int? ?? 0,
        level: json['level'] as int? ?? 1,
        stamina: (json['stamina'] as num?)?.toDouble() ?? gm.kMaxStamina,
        staminaSyncedAtMs: json['staminaSyncedAtMs'] as int? ?? 0,
        lifetimeKm: (json['lifetimeKm'] as num?)?.toDouble() ?? 0,
        totalFocusSeconds: json['totalFocusSeconds'] as int? ?? 0,
        sessionsCompleted: json['sessionsCompleted'] as int? ?? 0,
        setsCompleted: json['setsCompleted'] as int? ?? 0,
        sessionIndexInSet: json['sessionIndexInSet'] as int? ?? 0,
        badgeIds: {
          ...(json['badgeIds'] as List? ?? const []).cast<String>()
        },
        dailyFocusMinutes: {
          for (final e
              in (json['dailyFocusMinutes'] as Map? ?? const {}).entries)
            e.key as String: (e.value as num).toInt()
        },
        timer: json['timer'] == null
            ? TimerState.idle
            : TimerState.fromJson(
                (json['timer'] as Map).cast<String, Object?>()),
        pendingReveal: json['pendingReveal'] == null
            ? null
            : RevealSequence.fromJson(
                (json['pendingReveal'] as Map).cast<String, Object?>()),
        settings: json['settings'] == null
            ? const Settings()
            : Settings.fromJson(
                (json['settings'] as Map).cast<String, Object?>()),
      );
}
