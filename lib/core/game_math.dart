/// Wayfarer game math — the single source of truth for all numbers.
///
/// Pure Dart: no Flutter imports. Every rule of the game economy lives here
/// as a named constant or a pure function, so the whole game is tunable from
/// this one file and testable without a device.
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

/// Base XP earned per minute of focus. A full default 25-minute session earns
/// 10 XP (0.4 × 25); time spent always counts, so ending early is still
/// rewarded for the minutes worked.
const double kXpPerFocusMinute = 0.4;

/// Bonus XP for completing a full set (4 sessions). Scaled by the consistency
/// multiplier in the engine, but not by time or stamina.
const int kXpSetBonus = 7;

/// XP awarded per marker (badge) earned this session — tier, map, comparison,
/// or odometer. Like the set bonus, scaled only by the consistency multiplier.
const int kXpPerMarker = 7;

/// Trailing-window consistency multiplier knobs. Each distinct day with focus
/// in the last [kConsistencyWindowDays] adds [kConsistencyBonusPerDay] to the
/// XP-gain multiplier, capped at [kConsistencyMaxBonus]. Rewards showing up
/// regularly without punishing the odd missed day.
const double kConsistencyBonusPerDay = 0.05;
const int kConsistencyWindowDays = 14;
const double kConsistencyMaxBonus = 0.70; // == kConsistencyWindowDays * perDay

/// Safety cap on the marker-XP fixpoint passes in the engine: marker XP can
/// fund another level, which can cross another marker. Converges in 1–2 passes
/// in practice; the cap only guards against a pathological loop.
const int kMaxMarkerPasses = 8;

// ---------------------------------------------------------------------------
// Stamina
// ---------------------------------------------------------------------------

/// Stamina capacity in full focus sessions at level 1. A full session drains
/// `100 / capacity` percent — at 2.0 that is 50% per session, so the bar empties
/// after 50 minutes of focus at the default 25-minute length.
const double kBaseStaminaCapacitySessions = 2.0;

/// Additional capacity per level past 1.
const double kStaminaCapacityPerLevel = 0.05;

/// Speed and XP-per-time multiplier while fully drained. Above 0% stamina travel
/// is at full speed and full XP; at exactly 0% both are halved, restoring the
/// moment stamina rises above 0 — pillar 2 (nothing ever fully stops).
const double kSpeedFloor = 0.5;

const double kMaxStamina = 100.0;

/// Minutes of any non-focus time (idle, paused, short or long break) needed to
/// refill a fully drained stamina bar — the single recovery-rate knob. Kept
/// independent of the long-break timer length so recovery feel and break
/// duration tune separately. Defaults to the long-break default (15 min).
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

/// Base XP earned for [elapsedFocusMs] of focus. Uses [effectiveFocusMs] so the
/// half-rate debuff engages the instant stamina hits 0 mid-session (full rate
/// before the zero-crossing, halved after). The set-completion bonus and the
/// consistency multiplier are applied separately by the engine, so a full
/// default 25-minute session from full stamina yields 10 XP and a 20-minute
/// early end yields 8.
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

/// Effective full-rate focus milliseconds for a chunk of [elapsedFocusMs],
/// accounting for the half-rate stamina debuff. Stamina falls linearly from
/// [staminaAtStart] as focus accrues; milliseconds before the zero-crossing
/// count at full rate, milliseconds after it at [kSpeedFloor]. Within a focus
/// session stamina only drains, so there is at most one crossing — the debuff
/// engages the instant stamina hits 0 and lifts the instant it rises above 0.
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

/// Stamina recovered over [elapsedMs] of any non-focus time — idle, paused, or a
/// short/long break — all at the same rate: a fully drained bar refills over
/// [kStaminaRecoveryMinutes]. The caller decides which phases count and clamps
/// the resulting stamina to 100.
double recovery(int elapsedMs) =>
    elapsedMs <= 0 ? 0 : kMaxStamina * (elapsedMs / kStaminaRecoveryMs);

// ---------------------------------------------------------------------------
// Distance
// ---------------------------------------------------------------------------

/// Distance in km for [elapsedFocusMs] of travel.
///
/// Pace is fixed by the level at session start. The stamina modifier is dynamic
/// within the chunk: full while stamina is above 0, halved the instant it hits
/// 0 (see [effectiveFocusMs]). [staminaAtSessionStart] is the stamina at the
/// start of this chunk. Computed only at pause or session end — never on a live
/// tick.
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
