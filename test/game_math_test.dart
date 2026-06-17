import 'package:flutter_test/flutter_test.dart';
import 'package:wayfarer/core/game_math.dart';

void main() {
  group('pace curve', () {
    test('level 1 is exactly 1 km/h', () {
      expect(paceKmh(1), 1.0);
    });

    test('matches the spec table at reference levels (0.1% tolerance)', () {
      expect(paceKmh(10), closeTo(1.8, 0.05));
      expect(paceKmh(20), closeTo(3.6, 0.05));
      expect(paceKmh(50), closeTo(27.5, 27.5 * 0.002));
      expect(paceKmh(100), closeTo(810.7, 810.7 * 0.001));
      expect(paceKmh(200), closeTo(703432, 703432 * 0.001));
    });

    test('+7% compounding per level, no cap', () {
      for (final level in [1, 10, 100, 1000]) {
        expect(paceKmh(level + 1) / paceKmh(level), closeTo(1.07, 1e-9));
      }
    });

    test('no overflow or precision loss at very high levels', () {
      expect(paceKmh(5000).isFinite, isTrue);
      expect(paceKmh(5000), greaterThan(paceKmh(4999)));
    });
  });

  group('XP curve', () {
    test('early exponential values match spec', () {
      expect(xpToNext(1), 16);
      expect(xpToNext(20), 70);
      expect(xpToNext(30), 151);
    });

    test('linear segment values match spec', () {
      expect(xpToNext(50), 251);
      expect(xpToNext(100), 501);
      expect(xpToNext(200), 1001);
    });

    test('continuity at the level-30 transition — no jump', () {
      // The exponential piece at 30 and the linear anchor are the same value,
      // and the first linear step is exactly +kXpLinearSlope.
      expect(xpToNext(kXpTransitionLevel), 151);
      expect(xpToNext(kXpTransitionLevel + 1), 151 + kXpLinearSlope);
      // The curve is monotonically nondecreasing through the seam.
      for (var l = 25; l <= 35; l++) {
        expect(xpToNext(l + 1), greaterThanOrEqualTo(xpToNext(l)));
      }
    });

    test('applyXp resolves multiple level-ups', () {
      // 16 + 17 + 19 = 52 XP carries level 1 → 4 exactly.
      expect(xpToNext(2), 17);
      expect(xpToNext(3), 19);
      final p = applyXp(level: 1, xpIntoLevel: 0, gained: 52);
      expect(p.level, 4);
      expect(p.xpIntoLevel, 0);
      expect(p.levelsGained, 3);
    });

    test('applyXp at high levels stays exact', () {
      final p = applyXp(level: 500, xpIntoLevel: 0, gained: xpToNext(500));
      expect(p.level, 501);
      expect(p.xpIntoLevel, 0);
    });
  });

  group('stamina', () {
    test('capacity grows +0.05 sessions per level; drains 50% per session', () {
      expect(staminaCapacitySessions(1), 2.0);
      expect(staminaCapacitySessions(11), closeTo(2.5, 1e-9));
      // 2× faster than before: one full session at L1 drains half the bar, so
      // it empties after two sessions (50 min of focus).
      expect(fullSessionDrain(1), 50.0);
    });

    test('drain is proportional to elapsed focus time', () {
      final full = fullSessionDrain(1);
      expect(drainFor(level: 1, elapsedFocusMs: kFocusMs), closeTo(full, 1e-9));
      // 10 of 25 minutes drains 40% of a full session's drain.
      expect(drainFor(level: 1, elapsedFocusMs: 10 * 60 * 1000),
          closeTo(full * 0.4, 1e-9));
      expect(drainFor(level: 1, elapsedFocusMs: 0), 0);
    });

    test('a full session drains the same amount at any configured length', () {
      final full = fullSessionDrain(1);
      const fiftyMin = 50 * 60 * 1000;
      // A completed 50-minute session drains exactly one full session's worth.
      expect(
          drainFor(level: 1, elapsedFocusMs: fiftyMin, focusDurationMs: fiftyMin),
          closeTo(full, 1e-9));
      // Half of it drains half.
      expect(
          drainFor(
              level: 1, elapsedFocusMs: fiftyMin ~/ 2, focusDurationMs: fiftyMin),
          closeTo(full * 0.5, 1e-9));
    });

    test('speed modifier: full while any stamina remains, halved only at 0%',
        () {
      expect(staminaSpeedModifier(100), 1.0);
      expect(staminaSpeedModifier(60), 1.0);
      expect(staminaSpeedModifier(1), 1.0);
      expect(staminaSpeedModifier(0), 0.5);
      // Never below the floor, never zero.
      expect(staminaSpeedModifier(-5), 0.5);
    });

    test('recovery refills a full bar over kStaminaRecoveryMinutes', () {
      // A full recovery window's worth of any non-focus time refills the bar...
      expect(recovery(kStaminaRecoveryMs), closeTo(kMaxStamina, 1e-9));
      // ...linearly, so 5 of the 15 recovery minutes restores a third.
      expect(recovery(5 * 60 * 1000), closeTo(kMaxStamina / 3, 1e-9));
      expect(recovery(0), 0);
      expect(recovery(-1000), 0);
    });
  });

  group('focus XP', () {
    test('a full default 25-minute session earns 10 XP', () {
      expect(
          xpForFocus(
              elapsedFocusMs: kFocusMs, staminaAtSessionStart: 100, level: 1),
          10);
    });

    test('XP scales with the minutes actually spent', () {
      expect(
          xpForFocus(
              elapsedFocusMs: 20 * 60 * 1000,
              staminaAtSessionStart: 100,
              level: 1),
          8);
      expect(
          xpForFocus(
              elapsedFocusMs: 50 * 60 * 1000,
              staminaAtSessionStart: 100,
              level: 1),
          20);
      expect(
          xpForFocus(elapsedFocusMs: 0, staminaAtSessionStart: 100, level: 1),
          0);
    });

    test('XP per time is halved when the session starts at 0% stamina', () {
      expect(
          xpForFocus(
              elapsedFocusMs: kFocusMs, staminaAtSessionStart: 0, level: 1),
          5);
    });

    test('the debuff engages mid-session: a full 25-min from 30% earns 8 XP',
        () {
      // Stamina hits 0 fifteen minutes in (drains 50% over 25 min); 15 min at
      // full + 10 min at half = 20 effective minutes → 8 XP.
      expect(
          xpForFocus(
              elapsedFocusMs: kFocusMs, staminaAtSessionStart: 30, level: 1),
          8);
    });
  });

  group('effective focus time (mid-session stamina debuff)', () {
    test('full while stamina > 0, halved the instant it hits 0', () {
      // Level 1, 30% bar empties 15 min into a 25-min session → 20 eff. minutes.
      expect(
          effectiveFocusMs(
              level: 1, staminaAtStart: 30, elapsedFocusMs: kFocusMs),
          closeTo(20 * 60 * 1000, 1e-6));
      // Never reaches 0 → the whole chunk counts at full rate.
      expect(
          effectiveFocusMs(
              level: 1, staminaAtStart: 100, elapsedFocusMs: kFocusMs),
          closeTo(kFocusMs.toDouble(), 1e-6));
      // Starts empty → the entire chunk runs at the floor.
      expect(
          effectiveFocusMs(
              level: 1, staminaAtStart: 0, elapsedFocusMs: kFocusMs),
          closeTo(kFocusMs * kSpeedFloor, 1e-6));
    });
  });

  group('consistency multiplier', () {
    test('no history is a flat 1.0x; each active day adds 5%', () {
      expect(consistencyMultiplier(0), 1.0);
      expect(consistencyMultiplier(1), closeTo(1.05, 1e-9));
      expect(consistencyMultiplier(10), closeTo(1.50, 1e-9));
    });

    test('caps at the full 14-day window (+70%)', () {
      expect(consistencyMultiplier(14), closeTo(1.70, 1e-9));
      expect(consistencyMultiplier(20), closeTo(1.70, 1e-9)); // clamped
    });

    test('bonus fraction is the multiplier minus one', () {
      expect(consistencyBonusFraction(0), 0.0);
      expect(consistencyBonusFraction(10), closeTo(0.5, 1e-9));
      expect(consistencyBonusFraction(99), closeTo(0.70, 1e-9));
    });
  });

  group('distance', () {
    test('full session at level 1 and full stamina is ~0.4167 km', () {
      expect(
          distanceKm(
              levelAtSessionStart: 1,
              staminaAtSessionStart: 100,
              elapsedFocusMs: kFocusMs),
          closeTo(25 / 60, 1e-9));
    });

    test('at 0% stamina distance runs at the half-rate floor', () {
      expect(
          distanceKm(
              levelAtSessionStart: 1,
              staminaAtSessionStart: 0,
              elapsedFocusMs: kFocusMs),
          closeTo(0.5 * 25 / 60, 1e-9));
    });

    test('distance halves only after stamina empties mid-session', () {
      // Level 1, start 30%: empties 15 min in, so 20 effective minutes.
      expect(
          distanceKm(
              levelAtSessionStart: 1,
              staminaAtSessionStart: 30,
              elapsedFocusMs: kFocusMs),
          closeTo(20 / 60, 1e-9));
    });

    test('proportional to elapsed time', () {
      final full = distanceKm(
          levelAtSessionStart: 7,
          staminaAtSessionStart: 100,
          elapsedFocusMs: kFocusMs);
      final partial = distanceKm(
          levelAtSessionStart: 7,
          staminaAtSessionStart: 100,
          elapsedFocusMs: kFocusMs ~/ 5);
      expect(partial, closeTo(full / 5, 1e-9));
    });
  });
}
