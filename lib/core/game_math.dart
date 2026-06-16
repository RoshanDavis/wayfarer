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

/// Base XP earned per minute of focus. A full default 25-minute session earns
/// 10 XP (0.4 × 25); time spent always counts, so ending early is still
/// rewarded for the minutes worked.
const double kXpPerFocusMinute = 0.4;

/// Bonus XP for completing a full set (4 sessions). Not time- or stamina-scaled.
const int kXpSetBonus = 10;

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

/// Base XP earned for [elapsedFocusMs] of focus, scaled by the stamina modifier
/// (halved at 0% stamina, the same rule as speed). The set-completion bonus is
/// added separately by the engine, so a full default 25-minute session yields
/// 10 XP and a 20-minute early end yields 8.
int xpForFocus(
        {required int elapsedFocusMs, required double staminaAtSessionStart}) =>
    (kXpPerFocusMinute *
            (elapsedFocusMs / 60000) *
            staminaSpeedModifier(staminaAtSessionStart))
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
