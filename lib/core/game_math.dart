/// Wayfarer game math — the single source of truth for all numbers.
/// Pure Dart: every economy rule is a named constant or pure function here, so
/// the game is tunable from one file and testable without a device.
library;

import 'dart:math' as math;

// ---------------------------------------------------------------------------
// Master tuning knobs
// ---------------------------------------------------------------------------

/// Pace multiplier per level, compounding. The only speed rule in the game.
const double kPaceGrowth = 1.07;

/// XP curve growth rate for the early exponential segment.
const double kXpGrowth = 1.08;

/// Base of the exponential XP segment: XP_to_next(level) = round(15 * 1.08^level).
const double kXpBase = 15;

/// Level at which the XP curve switches from exponential to linear.
const int kXpTransitionLevel = 30;

/// Linear XP slope past the transition: +5 XP required per level.
const int kXpLinearSlope = 5;

// ---------------------------------------------------------------------------
// Pomodoro structure — durations are the user-tunable defaults; a set is
// always 4 sessions. The map advances every level (see maps.dart).
// ---------------------------------------------------------------------------

const int kFocusMinutes = 25;
const int kShortBreakMinutes = 5;
const int kLongBreakMinutes = 15;
const int kSessionsPerSet = 4;

const int kFocusMs = kFocusMinutes * 60 * 1000;
const int kShortBreakMs = kShortBreakMinutes * 60 * 1000;
const int kLongBreakMs = kLongBreakMinutes * 60 * 1000;

/// Bounds and step sizes for the Settings duration steppers (minutes).
const int kFocusMinMinutes = 5;
const int kFocusMaxMinutes = 90;
const int kFocusStepMinutes = 5;

const int kShortBreakMinMinutes = 1;
const int kShortBreakMaxMinutes = 30;
const int kShortBreakStepMinutes = 1;

const int kLongBreakMinMinutes = 5;
const int kLongBreakMaxMinutes = 60;
const int kLongBreakStepMinutes = 5;

/// Clamps [minutes] to [[lo], [hi]].
int clampMinutes(int minutes, int lo, int hi) =>
    minutes < lo ? lo : (minutes > hi ? hi : minutes);

// ---------------------------------------------------------------------------
// XP economy
// ---------------------------------------------------------------------------

/// Base XP per focus minute. A full 25-minute session earns 10 XP (0.4 × 25);
/// time always counts, so ending early is still rewarded for minutes worked.
const double kXpPerFocusMinute = 0.4;

/// Bonus XP for completing a full set (4 sessions). Scaled by the consistency
/// multiplier in the engine, but not by time or stamina.
const int kXpSetBonus = 7;

/// XP awarded per marker (badge) earned this session — tier, map, comparison,
/// or odometer. Like the set bonus, scaled only by the consistency multiplier.
const int kXpPerMarker = 7;

/// Consistency multiplier knobs: each distinct day with focus in the last
/// [kConsistencyWindowDays] adds [kConsistencyBonusPerDay] to the XP-gain
/// multiplier, capped at [kConsistencyMaxBonus].
const double kConsistencyBonusPerDay = 0.05;
const int kConsistencyWindowDays = 14;
const double kConsistencyMaxBonus = 0.70; // == kConsistencyWindowDays * perDay

/// Safety cap on the engine's marker-XP fixpoint: marker XP can fund a level
/// that crosses another marker. Converges in 1–2 passes; the cap guards a loop.
const int kMaxMarkerPasses = 8;

// ---------------------------------------------------------------------------
// Stamina
// ---------------------------------------------------------------------------

/// Stamina capacity in full focus sessions at level 1. A session drains
/// `100 / capacity` percent — at 2.0 that is 50%, emptying after 50 focus min.
const double kBaseStaminaCapacitySessions = 2.0;

/// Additional capacity per level past 1.
const double kStaminaCapacityPerLevel = 0.05;

/// Speed/XP multiplier while fully drained: full above 0% stamina, halved at
/// exactly 0%, restoring the moment it rises again — nothing ever fully stops.
const double kSpeedFloor = 0.5;

const double kMaxStamina = 100.0;

/// Minutes of any non-focus time (idle, paused, break) to refill a drained bar
/// — the single recovery-rate knob, kept independent of the long-break length so
/// recovery feel and break duration tune separately.
const int kStaminaRecoveryMinutes = 15;
const int kStaminaRecoveryMs = kStaminaRecoveryMinutes * 60 * 1000;

// ---------------------------------------------------------------------------
// Pace and XP functions
// ---------------------------------------------------------------------------

/// Running pace in km/h at [level]. 1 km/h at level 1, +7% compounding,
/// no cap. Doubles are exact enough far beyond any reachable level.
double paceKmh(int level) => math.pow(kPaceGrowth, level - 1).toDouble();

/// XP required to advance from [level] to the next.
///
/// Exponential through [kXpTransitionLevel], linear after; the two pieces
/// meet at the transition with no jump.
int xpToNext(int level) {
  if (level <= kXpTransitionLevel) {
    return (kXpBase * math.pow(kXpGrowth, level)).round();
  }
  final atTransition =
      (kXpBase * math.pow(kXpGrowth, kXpTransitionLevel)).round();
  return atTransition + kXpLinearSlope * (level - kXpTransitionLevel);
}

/// Result of pouring XP into the level counter.
class LevelProgress {
  final int level;
  final int xpIntoLevel;
  final int levelsGained;
  const LevelProgress(this.level, this.xpIntoLevel, this.levelsGained);
}

/// Adds [gained] XP to a player at [level] with [xpIntoLevel] progress,
/// resolving any number of level-ups.
LevelProgress applyXp(
    {required int level, required int xpIntoLevel, required int gained}) {
  var l = level;
  var xp = xpIntoLevel + gained;
  while (xp >= xpToNext(l)) {
    xp -= xpToNext(l);
    l++;
  }
  return LevelProgress(l, xp, l - level);
}

/// Fraction added to the XP-gain multiplier for [activeDays] distinct active
/// days in the trailing window: +[kConsistencyBonusPerDay] per day, capped at
/// [kConsistencyMaxBonus]. 0 when there is no recent history.
double consistencyBonusFraction(int activeDays) =>
    (kConsistencyBonusPerDay * activeDays).clamp(0.0, kConsistencyMaxBonus);

/// XP-gain multiplier from recent consistency: 1 + [consistencyBonusFraction].
double consistencyMultiplier(int activeDays) =>
    1.0 + consistencyBonusFraction(activeDays);

/// Base XP for [elapsedFocusMs] of focus, via [effectiveFocusMs] so the half-rate
/// debuff applies after stamina hits 0 mid-session. The set bonus and consistency
/// multiplier are applied separately by the engine (full 25-min run → 10 XP).
int xpForFocus({
  required int elapsedFocusMs,
  required double staminaAtSessionStart,
  required int level,
  int focusDurationMs = kFocusMs,
}) =>
    (kXpPerFocusMinute *
            (effectiveFocusMs(
                  level: level,
                  staminaAtStart: staminaAtSessionStart,
                  elapsedFocusMs: elapsedFocusMs,
                  focusDurationMs: focusDurationMs,
                ) /
                60000))
        .round();

// ---------------------------------------------------------------------------
// Stamina functions
// ---------------------------------------------------------------------------

/// Stamina capacity in full sessions at [level]: 4.0 at level 1, +0.1/level.
double staminaCapacitySessions(int level) =>
    kBaseStaminaCapacitySessions + kStaminaCapacityPerLevel * (level - 1);

/// Stamina percentage drained by one full focus session at [level].
/// A "full session" is one configured focus duration, whatever its length —
/// so drain depends on level, not on how long the user set the timer.
double fullSessionDrain(int level) => kMaxStamina / staminaCapacitySessions(level);

/// Stamina drained by [elapsedFocusMs] of focus at [level], proportional to
/// the fraction of a full session ([focusDurationMs]) actually worked.
double drainFor({
  required int level,
  required int elapsedFocusMs,
  int focusDurationMs = kFocusMs,
}) =>
    fullSessionDrain(level) * (elapsedFocusMs / focusDurationMs);

/// Speed/XP multiplier from stamina: full while any stamina remains, halved
/// ([kSpeedFloor]) only when fully depleted. Restores to full the moment stamina
/// rises above 0.
double staminaSpeedModifier(double stamina) =>
    stamina <= 0 ? kSpeedFloor : 1.0;

/// Effective full-rate focus ms for [elapsedFocusMs], accounting for the half-rate
/// debuff. Stamina falls linearly from [staminaAtStart]; ms before the zero-
/// crossing count at full rate, ms after at [kSpeedFloor]. Stamina only drains
/// within a session, so there is at most one crossing.
double effectiveFocusMs({
  required int level,
  required double staminaAtStart,
  required int elapsedFocusMs,
  int focusDurationMs = kFocusMs,
}) {
  if (staminaAtStart <= 0) return elapsedFocusMs * kSpeedFloor;
  final drainPerMs = fullSessionDrain(level) / focusDurationMs;
  final msToZero = staminaAtStart / drainPerMs;
  if (msToZero >= elapsedFocusMs) return elapsedFocusMs.toDouble();
  return msToZero + (elapsedFocusMs - msToZero) * kSpeedFloor;
}

/// Stamina recovered over [elapsedMs] of non-focus time (idle, paused, break),
/// all at the same rate — a drained bar refills over [kStaminaRecoveryMinutes].
/// The caller decides which phases count and clamps the result to 100.
double recovery(int elapsedMs) =>
    elapsedMs <= 0 ? 0 : kMaxStamina * (elapsedMs / kStaminaRecoveryMs);

// ---------------------------------------------------------------------------
// Distance
// ---------------------------------------------------------------------------

/// Distance in km for [elapsedFocusMs] of travel. Pace is fixed by the
/// session-start level; the stamina modifier is dynamic within the chunk (see
/// [effectiveFocusMs]). Computed only at pause or session end — never on a tick.
double distanceKm({
  required int levelAtSessionStart,
  required double staminaAtSessionStart,
  required int elapsedFocusMs,
  int focusDurationMs = kFocusMs,
}) =>
    paceKmh(levelAtSessionStart) *
    (effectiveFocusMs(
          level: levelAtSessionStart,
          staminaAtStart: staminaAtSessionStart,
          elapsedFocusMs: elapsedFocusMs,
          focusDurationMs: focusDurationMs,
        ) /
        (1000 * 60 * 60));
