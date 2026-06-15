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
// always 4 sessions and the map advances every 3 sets.
// ---------------------------------------------------------------------------

const int kFocusMinutes = 25;
const int kShortBreakMinutes = 5;
const int kLongBreakMinutes = 15;
const int kSessionsPerSet = 4;
const int kSetsPerMap = 3;

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

const int kXpPerSession = 10;
const int kXpSetBonus = 10;

// ---------------------------------------------------------------------------
// Stamina
// ---------------------------------------------------------------------------

/// Stamina capacity in full focus sessions at level 1.
const double kBaseStaminaCapacitySessions = 4.0;

/// Additional capacity per level past 1.
const double kStaminaCapacityPerLevel = 0.1;

/// At or above this stamina percentage, travel is at full speed.
const double kFullSpeedStaminaThreshold = 60.0;

/// Speed multiplier at 0% stamina. Speed never drops below this — pillar 2.
const double kSpeedFloor = 0.5;

const double kMaxStamina = 100.0;

/// Hours of idle time (the focus timer not running) needed to passively refill
/// a fully drained stamina bar. Breaks remain the fast, deliberate recovery;
/// this is the slow background rest the body takes whenever you are not
/// focusing — so stepping away for a while, or returning the next day, leaves
/// you recovered.
const double kIdleRecoveryHoursFull = 6.0;

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

/// Speed multiplier for a given stamina value: 1.0 at >= 60%, scaling
/// linearly down to 0.5 at 0%. Never below 0.5, never zero.
double staminaSpeedModifier(double stamina) {
  if (stamina >= kFullSpeedStaminaThreshold) return 1.0;
  final t = (stamina / kFullSpeedStaminaThreshold).clamp(0.0, 1.0);
  return kSpeedFloor + (1.0 - kSpeedFloor) * t;
}

/// Stamina passively recovered over [elapsedMs] of idle time (not focusing).
///
/// Linear in wall-clock time: an empty bar refills over
/// [kIdleRecoveryHoursFull] hours. The caller decides which phases count as
/// idle and clamps the resulting stamina to 100.
double idleRecovery(int elapsedMs) => elapsedMs <= 0
    ? 0
    : kMaxStamina * (elapsedMs / (kIdleRecoveryHoursFull * 60 * 60 * 1000));

/// Stamina restored by a break.
///
/// A fully completed short break restores one full session's drain at
/// [level]; a fully completed long break restores the whole bar (the deficit
/// from [staminaAtBreakStart] to 100). Partial breaks restore proportionally
/// ([fraction] in 0..1). Caller clamps the resulting stamina to 100.
double breakRecovery({
  required bool isLong,
  required int level,
  required double staminaAtBreakStart,
  required double fraction,
}) {
  final f = fraction.clamp(0.0, 1.0);
  final amount =
      isLong ? (kMaxStamina - staminaAtBreakStart) : fullSessionDrain(level);
  return amount * f;
}

// ---------------------------------------------------------------------------
// Distance
// ---------------------------------------------------------------------------

/// Distance in km for [elapsedFocusMs] of travel.
///
/// Pace comes from the level at session start; the stamina modifier is
/// evaluated from stamina at session start and held constant for the session.
/// Computed only at pause or session end — never on a live tick.
double distanceKm({
  required int levelAtSessionStart,
  required double staminaAtSessionStart,
  required int elapsedFocusMs,
}) =>
    paceKmh(levelAtSessionStart) *
    staminaSpeedModifier(staminaAtSessionStart) *
    (elapsedFocusMs / (1000 * 60 * 60));
