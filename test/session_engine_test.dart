import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wayfarer/core/game_math.dart' as gm;
import 'package:wayfarer/core/models.dart';
import 'package:wayfarer/core/session_engine.dart';

const minMs = 60 * 1000;
final t0 = DateTime(2026, 6, 1, 9, 0).millisecondsSinceEpoch;

GameState completeOneSession(GameState s, int startMs) {
  final running = Engine.startFocus(s, startMs);
  return Engine.reconstruct(running, startMs + gm.kFocusMs);
}

void main() {
  group('focus session lifecycle', () {
    test('start sets up a 25-minute wall-clock session', () {
      final s = Engine.startFocus(GameState.initial, t0);
      expect(s.timer.phase, Phase.focusRunning);
      expect(s.timer.phaseEndsAtMs, t0 + 25 * minMs);
      expect(s.timer.staminaAtSessionStart, 100);
      expect(s.timer.levelAtSessionStart, 1);
      expect(s.timer.remainingMs(t0 + 10 * minMs), 15 * minMs);
    });

    test('completion awards distance, XP, drain, and a pending reveal', () {
      final s = completeOneSession(GameState.initial, t0);
      expect(s.timer.phase, Phase.focusComplete);
      expect(s.lifetimeKm, closeTo(25 / 60, 1e-9));
      expect(s.xpIntoLevel, 10);
      expect(s.level, 1);
      expect(s.stamina, closeTo(75, 1e-9));
      expect(s.sessionsCompleted, 1);
      expect(s.sessionIndexInSet, 1);
      expect(s.setsCompleted, 0);
      expect(s.totalFocusSeconds, 1500);
      final reveal = s.pendingReveal!;
      expect(reveal.sessionCompleted, isTrue);
      expect(reveal.distanceKm, closeTo(25 / 60, 1e-9));
      expect(reveal.xpGained, 10);
      expect(reveal.nextAction, NextAction.shortBreak);
      expect(s.dailyFocusMinutes[dateKey(t0 + 25 * minMs)], 25);
    });

    test('distance is computed from pace at the session-start level', () {
      final leveled = GameState.initial.copyWith(level: 3);
      final s = completeOneSession(leveled, t0);
      expect(s.lifetimeKm, closeTo(gm.paceKmh(3) * 25 / 60, 1e-9));
    });

    test('stamina modifier is evaluated at session start and held constant',
        () {
      final tired = GameState.initial.copyWith(stamina: 30);
      final s = completeOneSession(tired, t0);
      // 30% stamina → modifier 0.75.
      expect(s.lifetimeKm, closeTo(0.75 * 25 / 60, 1e-9));
    });

    test('the 50% speed floor still moves the runner at 0% stamina', () {
      final exhausted = GameState.initial.copyWith(stamina: 0);
      final s = completeOneSession(exhausted, t0);
      expect(s.lifetimeKm, closeTo(0.5 * 25 / 60, 1e-9));
      expect(s.stamina, 0); // drain clamps at zero
    });
  });

  group('pause and resume', () {
    test('pause banks distance and applies proportional drain', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + 10 * minMs);
      expect(s.timer.phase, Phase.focusPaused);
      expect(s.timer.accumulatedFocusMs, 10 * minMs);
      expect(s.timer.bankedDistanceKm, closeTo(0.4 * 25 / 60, 1e-9));
      // 10 of 25 minutes drains 40% of a full session's drain.
      expect(s.stamina, closeTo(100 - 0.4 * 25, 1e-9));
      expect(s.lifetimeKm, 0); // odometer credited only at session end
    });

    test('resume after a long gap completes at the shifted end time', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + 10 * minMs);
      final resumeAt = t0 + 3 * 60 * minMs; // resumed 3 hours later
      s = Engine.resumeFocus(s, resumeAt);
      expect(s.timer.phaseEndsAtMs, resumeAt + 15 * minMs);
      s = Engine.reconstruct(s, resumeAt + 15 * minMs);
      expect(s.timer.phase, Phase.focusComplete);
      expect(s.lifetimeKm, closeTo(25 / 60, 1e-9)); // full session distance
      expect(s.stamina, closeTo(75, 1e-9)); // full session drain, once
    });

    test('pausing while paused or idle is a no-op', () {
      expect(Engine.pauseFocus(GameState.initial, t0).timer.phase, Phase.idle);
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + minMs);
      expect(Engine.pauseFocus(s, t0 + 2 * minMs), same(s));
    });
  });

  group('ending early', () {
    test('awards elapsed distance but no XP and no set progress', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.endFocusEarly(s, t0 + 10 * minMs);
      expect(s.timer.phase, Phase.idle);
      expect(s.lifetimeKm, closeTo(0.4 * 25 / 60, 1e-9));
      expect(s.xpIntoLevel, 0);
      expect(s.sessionsCompleted, 0);
      expect(s.sessionIndexInSet, 0);
      expect(s.stamina, closeTo(90, 1e-9));
      expect(s.totalFocusSeconds, 600);
      expect(s.dailyFocusMinutes[dateKey(t0 + 10 * minMs)], 10);
      final reveal = s.pendingReveal!;
      expect(reveal.sessionCompleted, isFalse);
      expect(reveal.xpGained, 0);
      expect(reveal.distanceKm, closeTo(0.4 * 25 / 60, 1e-9));
      expect(reveal.nextAction, NextAction.focus);
    });

    test('ending early from a paused session awards the banked distance', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + 5 * minMs);
      s = Engine.endFocusEarly(s, t0 + 60 * minMs);
      expect(s.lifetimeKm, closeTo(0.2 * 25 / 60, 1e-9));
      expect(s.stamina, closeTo(95, 1e-9));
    });

    test('an early end past the scheduled end resolves as a completion', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.endFocusEarly(s, t0 + 26 * minMs);
      expect(s.timer.phase, Phase.focusComplete);
      expect(s.sessionsCompleted, 1);
    });
  });

  group('sets and breaks', () {
    test('four completed sessions form a set with bonus XP and a long break',
        () {
      var s = GameState.initial;
      for (var i = 0; i < 4; i++) {
        final start = t0 + i * 60 * minMs;
        s = completeOneSession(s, start);
        if (i < 3) {
          expect(s.timer.breakKind, BreakKind.short);
          expect(s.pendingReveal!.nextAction, NextAction.shortBreak);
          s = Engine.skipBreak(s);
        }
      }
      expect(s.setsCompleted, 1);
      expect(s.sessionIndexInSet, 0);
      expect(s.sessionsCompleted, 4);
      expect(s.timer.breakKind, BreakKind.long);
      expect(s.pendingReveal!.nextAction, NextAction.longBreak);
      expect(s.pendingReveal!.xpGained, 20); // 10 + 10 set bonus
      // 10+10+10+20 = 50 XP: 16 to level 2, 17 to level 3, 17 remaining.
      expect(s.level, 3);
      expect(s.xpIntoLevel, 17);
    });

    test('early-ended sessions do not advance the set', () {
      var s = completeOneSession(GameState.initial, t0);
      s = Engine.skipBreak(s);
      s = Engine.startFocus(s, t0 + 60 * minMs);
      s = Engine.endFocusEarly(s, t0 + 70 * minMs);
      expect(s.sessionIndexInSet, 1);
      expect(s.sessionsCompleted, 1);
    });

    test('a full short break restores one session of drain', () {
      var s = completeOneSession(GameState.initial, t0); // stamina 75
      final breakStart = t0 + 30 * minMs;
      s = Engine.startBreak(s, breakStart);
      expect(s.timer.phase, Phase.breakRunning);
      expect(s.timer.phaseEndsAtMs, breakStart + 5 * minMs);
      s = Engine.reconstruct(s, breakStart + 5 * minMs);
      expect(s.timer.phase, Phase.breakComplete);
      expect(s.stamina, closeTo(100, 1e-9));
    });

    test('half a break restores half the recovery, continuously accrued', () {
      var s = completeOneSession(GameState.initial, t0); // stamina 75
      final breakStart = t0 + 30 * minMs;
      s = Engine.startBreak(s, breakStart);
      s = Engine.endBreakEarly(s, breakStart + 150 * 1000); // 2.5 of 5 min
      expect(s.timer.phase, Phase.breakComplete);
      expect(s.stamina, closeTo(75 + 12.5, 1e-9));
    });

    test('recovery caps at 100 — over-resting gives nothing extra', () {
      // A short break at level 1 restores 25 points; from 95 stamina the
      // uncapped result would be 120.
      var s = GameState.initial.copyWith(
        stamina: 95,
        timer: TimerState(
          phase: Phase.breakRunning,
          breakKind: BreakKind.short,
          segmentStartedAtMs: t0,
          phaseEndsAtMs: t0 + 5 * minMs,
          staminaAtBreakStart: 95,
        ),
      );
      s = Engine.reconstruct(s, t0 + 60 * minMs); // long over-rest
      expect(s.timer.phase, Phase.breakComplete);
      expect(s.stamina, 100);
    });

    test('a full long break restores the whole bar', () {
      var s = GameState.initial.copyWith(
        stamina: 15,
        sessionIndexInSet: 3,
      );
      s = completeOneSession(s, t0);
      expect(s.timer.breakKind, BreakKind.long);
      final low = s.stamina;
      expect(low, lessThan(15)); // drained below start
      s = Engine.startBreak(s, t0 + 30 * minMs);
      s = Engine.reconstruct(s, t0 + 30 * minMs + 15 * minMs);
      expect(s.stamina, 100);
    });

    test('a partial long break restores a proportional share of the deficit',
        () {
      var s = GameState.initial.copyWith(stamina: 40, sessionIndexInSet: 3);
      s = completeOneSession(s, t0);
      final atBreakStart = s.stamina; // 15
      s = Engine.startBreak(s, t0 + 30 * minMs);
      s = Engine.endBreakEarly(s, t0 + 30 * minMs + 5 * minMs); // 1/3 of 15
      expect(
          s.stamina, closeTo(atBreakStart + (100 - atBreakStart) / 3, 1e-9));
    });

    test('skipping a break gives no recovery but keeps the distance reveal',
        () {
      var s = completeOneSession(GameState.initial, t0);
      final before = s.stamina;
      s = Engine.skipBreak(s);
      expect(s.timer.phase, Phase.idle);
      expect(s.stamina, before);
      // The reveal persists (it feeds the under-timer distance) until the
      // next focus session starts.
      expect(s.pendingReveal, isNotNull);
      expect(Engine.startFocus(s, t0 + 60 * minMs).pendingReveal, isNull);
    });

    test('low stamina never blocks starting a session', () {
      final s =
          Engine.startFocus(GameState.initial.copyWith(stamina: 0), t0);
      expect(s.timer.phase, Phase.focusRunning);
    });

    test('starting focus from a running break applies partial recovery first',
        () {
      var s = completeOneSession(GameState.initial, t0); // 75
      s = Engine.startBreak(s, t0 + 30 * minMs);
      final at = t0 + 30 * minMs + 150 * 1000;
      s = Engine.startFocus(Engine.endBreakEarly(s, at), at);
      expect(s.timer.phase, Phase.focusRunning);
      expect(s.timer.staminaAtSessionStart, closeTo(87.5, 1e-9));
    });
  });

  group('idle recovery', () {
    test('idle time between sessions recovers stamina on reconstruct', () {
      var s = completeOneSession(GameState.initial, t0); // stamina 75
      s = Engine.skipBreak(s); // → idle, sync anchored at completion
      // One hour of idle recovers a proportional share of a full bar.
      s = Engine.reconstruct(s, t0 + 25 * minMs + 60 * minMs);
      expect(s.stamina, closeTo(75 + gm.idleRecovery(60 * minMs), 1e-9));
    });

    test('idle recovery never exceeds a full bar', () {
      var s = completeOneSession(GameState.initial, t0);
      s = Engine.skipBreak(s);
      s = Engine.reconstruct(s, t0 + 25 * minMs + 10 * 60 * minMs); // 10h
      expect(s.stamina, 100);
    });

    test('a paused session does not recover — pausing freezes the bar', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + 10 * minMs); // stamina 90
      s = Engine.reconstruct(s, t0 + 5 * 60 * minMs); // 5h paused
      expect(s.timer.phase, Phase.focusPaused);
      expect(s.stamina, closeTo(90, 1e-9));
    });

    test('starting a session credits the idle rest taken since the last', () {
      var s = completeOneSession(GameState.initial, t0); // 75
      s = Engine.skipBreak(s);
      final start = t0 + 25 * minMs + 60 * minMs; // an hour later
      s = Engine.startFocus(s, start);
      expect(s.timer.staminaAtSessionStart,
          closeTo(75 + gm.idleRecovery(60 * minMs), 1e-9));
    });
  });

  group('progression events', () {
    test('reaching a tier level awards the tier badge in the reveal', () {
      final nearTier =
          GameState.initial.copyWith(level: 9, xpIntoLevel: gm.xpToNext(9) - 5);
      final s = completeOneSession(nearTier, t0);
      expect(s.level, 10);
      expect(s.pendingReveal!.tierLevelsReached, [10]);
      expect(s.badgeIds, contains('tier-10'));
    });

    test('speed-comparison crossings fire exactly once', () {
      // Level 24 → 25 crosses 5 km/h (walking human).
      final near = GameState.initial
          .copyWith(level: 24, xpIntoLevel: gm.xpToNext(24) - 5);
      var s = completeOneSession(near, t0);
      expect(s.level, 25);
      expect(s.pendingReveal!.comparisonIds, ['walking-human']);
      expect(s.badgeIds, contains('cmp-walking-human'));

      // Another level-up does not re-cross it.
      s = Engine.skipBreak(s)
          .copyWith(xpIntoLevel: gm.xpToNext(25) - 5);
      s = completeOneSession(s, t0 + 60 * minMs);
      expect(s.level, 26);
      expect(s.pendingReveal!.comparisonIds, isEmpty);
      expect(s.badgeIds.where((b) => b.startsWith('cmp-')).length, 1);
    });

    test('map changes exactly every 3 completed sets with a map badge', () {
      var s = GameState.initial;
      var clock = t0;
      for (var session = 1; session <= 12; session++) {
        s = completeOneSession(s, clock);
        clock += 60 * minMs;
        final reveal = s.pendingReveal!;
        if (session == 12) {
          expect(s.setsCompleted, 3);
          expect(reveal.newMapIndex, 1);
          expect(s.badgeIds, contains('map-1'));
        } else {
          expect(reveal.newMapIndex, isNull,
              reason: 'map must not change at session $session');
        }
        s = Engine.skipBreak(s);
      }
    });

    test('odometer milestones are crossed in the reveal', () {
      final near = GameState.initial.copyWith(lifetimeKm: 4.9, level: 7);
      // pace(7) ≈ 1.5 km/h → ~0.63 km this session crosses 5 km.
      final s = completeOneSession(near, t0);
      expect(s.lifetimeKm, greaterThan(5));
      expect(s.badgeIds, contains('odo-5'));
      expect(s.pendingReveal!.badgeIds, contains('odo-5'));
    });
  });

  group('configurable durations', () {
    GameState withFocus(int minutes) => GameState.initial.copyWith(
        settings: GameState.initial.settings.copyWith(focusMinutes: minutes));

    test('a custom focus length sets the planned end and distance', () {
      const fifty = 50 * minMs;
      var s = Engine.startFocus(withFocus(50), t0);
      expect(s.timer.phaseEndsAtMs, t0 + fifty);
      expect(s.timer.plannedDurationMs, fifty);
      s = Engine.reconstruct(s, t0 + fifty);
      expect(s.timer.phase, Phase.focusComplete);
      // Distance scales with real time: 50 min at 1 km/h = 50/60 km.
      expect(s.lifetimeKm, closeTo(50 / 60, 1e-9));
      // Drain is still one full session regardless of length.
      expect(s.stamina, closeTo(75, 1e-9));
      // Focus time and daily minutes credit the configured length.
      expect(s.totalFocusSeconds, 3000);
      expect(s.dailyFocusMinutes[dateKey(t0 + fifty)], 50);
    });

    test('a custom short break still restores one full session of drain', () {
      var s = Engine.startFocus(withFocus(50), t0);
      s = Engine.reconstruct(s, t0 + 50 * minMs); // stamina 75
      final settings = s.settings.copyWith(shortBreakMinutes: 10);
      s = s.copyWith(settings: settings);
      final breakStart = t0 + 60 * minMs;
      s = Engine.startBreak(s, breakStart);
      expect(s.timer.plannedDurationMs, 10 * minMs);
      s = Engine.endBreakEarly(s, breakStart + 5 * minMs); // half of 10 min
      expect(s.stamina, closeTo(75 + 12.5, 1e-9));
    });

    test('editing durations mid-session does not change the in-flight phase',
        () {
      var s = Engine.startFocus(withFocus(50), t0);
      // User opens settings and changes focus to 25 while a 50-min session runs.
      s = s.copyWith(
          settings: s.settings.copyWith(focusMinutes: 25));
      // The running session keeps its own 50-min plan.
      expect(s.timer.plannedDurationMs, 50 * minMs);
      s = Engine.reconstruct(s, t0 + 50 * minMs);
      expect(s.timer.phase, Phase.focusComplete);
      expect(s.totalFocusSeconds, 3000);
      // The *next* session uses the new 25-min setting.
      s = Engine.skipBreak(s);
      final next = Engine.startFocus(s, t0 + 2 * 60 * minMs);
      expect(next.timer.plannedDurationMs, 25 * minMs);
    });
  });

  group('state serialization', () {
    test('GameState round-trips through JSON unchanged', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + 7 * minMs);
      s = s.copyWith(
        badgeIds: {'tier-10', 'odo-5'},
        dailyFocusMinutes: {'2026-06-01': 50},
        settings: const Settings(
            theme: ThemePreference.dark,
            soundEnabled: true,
            notificationsEnabled: false,
            focusMinutes: 40,
            shortBreakMinutes: 8,
            longBreakMinutes: 20),
      );
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
      expect(restored.timer.phase, Phase.focusPaused);
      expect(restored.timer.accumulatedFocusMs, 7 * minMs);
      expect(restored.timer.plannedDurationMs, s.timer.plannedDurationMs);
      expect(restored.timer.bankedDistanceKm,
          closeTo(s.timer.bankedDistanceKm, 1e-12));
      expect(restored.stamina, closeTo(s.stamina, 1e-12));
      expect(restored.badgeIds, s.badgeIds);
      expect(restored.dailyFocusMinutes, s.dailyFocusMinutes);
      expect(restored.settings.theme, ThemePreference.dark);
      expect(restored.settings.soundEnabled, isTrue);
      expect(restored.settings.notificationsEnabled, isFalse);
      expect(restored.settings.focusMinutes, 40);
      expect(restored.settings.shortBreakMinutes, 8);
      expect(restored.settings.longBreakMinutes, 20);
    });

    test('a pending reveal survives the JSON round-trip', () {
      final s = completeOneSession(GameState.initial, t0);
      final restored = GameState.fromJson(
          jsonDecode(jsonEncode(s.toJson())) as Map<String, Object?>);
      expect(restored.pendingReveal, isNotNull);
      expect(restored.pendingReveal!.distanceKm,
          closeTo(s.pendingReveal!.distanceKm, 1e-12));
      expect(restored.pendingReveal!.nextAction, NextAction.shortBreak);
    });
  });
}
