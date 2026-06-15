/// Time-integrity tests: the app is backgrounded, screen-locked and
/// process-killed mid-session; everything must reconstruct from wall-clock
/// timestamps alone. These tests simulate process death by serializing state
/// to JSON, "waking up" much later, and reconstructing.
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wayfarer/core/models.dart';
import 'package:wayfarer/core/session_engine.dart';

const minMs = 60 * 1000;
const hourMs = 60 * minMs;
final t0 = DateTime(2026, 6, 1, 9, 0).millisecondsSinceEpoch;

/// Simulates process death and relaunch at [wakeMs].
GameState killAndRelaunch(GameState s, int wakeMs) {
  final persisted = jsonEncode(s.toJson());
  final restored =
      GameState.fromJson(jsonDecode(persisted) as Map<String, Object?>);
  return Engine.reconstruct(restored, wakeMs);
}

void main() {
  group('killed mid-focus', () {
    test('before the scheduled end: session continues from wall clock', () {
      final s = Engine.startFocus(GameState.initial, t0);
      final wake = killAndRelaunch(s, t0 + 18 * minMs);
      expect(wake.timer.phase, Phase.focusRunning);
      expect(wake.timer.remainingMs(t0 + 18 * minMs), 7 * minMs);
      expect(wake.lifetimeKm, 0);
    });

    test('after the scheduled end: resolved at the end time, not wake time',
        () {
      final s = Engine.startFocus(GameState.initial, t0);
      final endMs = t0 + 25 * minMs;
      final wake = killAndRelaunch(s, t0 + 9 * hourMs); // returns much later
      expect(wake.timer.phase, Phase.focusComplete);
      expect(wake.lifetimeKm, closeTo(25 / 60, 1e-9));
      expect(wake.sessionsCompleted, 1);
      expect(wake.xpIntoLevel, 10);
      // The session's drain is resolved at the end time; stamina then recovers
      // passively over the long idle gap — fully, nine hours on.
      expect(wake.stamina, closeTo(100, 1e-9));
      expect(wake.pendingReveal, isNotNull);
      // Focus minutes are attributed to the day the session ended.
      expect(wake.dailyFocusMinutes[dateKey(endMs)], 25);
    });

    test('completion awards are identical whether the app was alive or dead',
        () {
      final s = Engine.startFocus(GameState.initial, t0);
      // Reconstructed at the *same* wake time, every award — including stamina —
      // is identical regardless of whether the app stayed alive.
      final live = Engine.reconstruct(s, t0 + 25 * minMs);
      final dead = killAndRelaunch(s, t0 + 25 * minMs);
      expect(dead.lifetimeKm, live.lifetimeKm);
      expect(dead.stamina, live.stamina);
      expect(dead.xpIntoLevel, live.xpIntoLevel);
      expect(dead.sessionsCompleted, live.sessionsCompleted);
      expect(dead.dailyFocusMinutes, live.dailyFocusMinutes);

      // Waking much later resolves the completion at the same scheduled end —
      // distance, XP and sessions are unchanged — while stamina simply keeps
      // recovering over the extra idle time.
      final later = killAndRelaunch(s, t0 + 3 * 24 * hourMs);
      expect(later.lifetimeKm, closeTo(live.lifetimeKm, 1e-9));
      expect(later.xpIntoLevel, live.xpIntoLevel);
      expect(later.sessionsCompleted, live.sessionsCompleted);
      expect(later.stamina, greaterThan(live.stamina));
    });

    test('a session spanning midnight is attributed to the day it ends', () {
      final lateStart =
          DateTime(2026, 6, 1, 23, 50).millisecondsSinceEpoch;
      final s = Engine.startFocus(GameState.initial, lateStart);
      final wake = killAndRelaunch(s, lateStart + 2 * 24 * hourMs);
      expect(wake.dailyFocusMinutes['2026-06-02'], 25);
      expect(wake.dailyFocusMinutes['2026-06-01'], isNull);
    });

    test('reconstruction is idempotent — no double award', () {
      final s = Engine.startFocus(GameState.initial, t0);
      final once = killAndRelaunch(s, t0 + hourMs);
      final twice = killAndRelaunch(once, t0 + 2 * hourMs);
      expect(twice.lifetimeKm, once.lifetimeKm);
      expect(twice.sessionsCompleted, once.sessionsCompleted);
      expect(twice.timer.phase, Phase.focusComplete);
    });
  });

  group('killed mid-pause', () {
    test('a paused session waits indefinitely without change', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + 10 * minMs);
      final wake = killAndRelaunch(s, t0 + 30 * 24 * hourMs); // a month later
      expect(wake.timer.phase, Phase.focusPaused);
      expect(wake.timer.accumulatedFocusMs, 10 * minMs);
      expect(wake.timer.bankedDistanceKm, closeTo(0.4 * 25 / 60, 1e-9));
      expect(wake.stamina, closeTo(90, 1e-9));
    });
  });

  group('killed mid-break', () {
    test('before the break end: break continues from wall clock', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.reconstruct(s, t0 + 25 * minMs);
      s = Engine.startBreak(s, t0 + 30 * minMs);
      final wake = killAndRelaunch(s, t0 + 32 * minMs);
      expect(wake.timer.phase, Phase.breakRunning);
      expect(wake.timer.remainingMs(t0 + 32 * minMs), 3 * minMs);
    });

    test('after the break end: full recovery applied exactly once', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.reconstruct(s, t0 + 25 * minMs); // stamina 75
      s = Engine.startBreak(s, t0 + 30 * minMs);
      final wake = killAndRelaunch(s, t0 + 8 * hourMs);
      expect(wake.timer.phase, Phase.breakComplete);
      expect(wake.stamina, closeTo(100, 1e-9));
      final again = killAndRelaunch(wake, t0 + 20 * hourMs);
      expect(again.stamina, closeTo(100, 1e-9));
    });
  });

  group('sequential gaps across multiple phases', () {
    test('focus dies → reveal survives → break dies → next session correct',
        () {
      // Start a focus session, phone dies, user returns hours later.
      var s = Engine.startFocus(GameState.initial, t0);
      s = killAndRelaunch(s, t0 + 2 * hourMs);
      expect(s.timer.phase, Phase.focusComplete);
      expect(s.pendingReveal, isNotNull);

      // The reveal survives another relaunch before being acknowledged.
      s = killAndRelaunch(s, t0 + 3 * hourMs);
      expect(s.pendingReveal, isNotNull);
      expect(s.pendingReveal!.distanceKm, closeTo(25 / 60, 1e-9));

      // User starts the break, phone dies again, returns days later. The
      // distance reveal persists through the break (it shows under the timer).
      final breakStart = t0 + 3 * hourMs;
      s = Engine.startBreak(s, breakStart);
      expect(s.pendingReveal, isNotNull);
      s = killAndRelaunch(s, breakStart + 2 * 24 * hourMs);
      expect(s.timer.phase, Phase.breakComplete);
      expect(s.stamina, closeTo(100, 1e-9));

      // Next focus session runs normally with the recovered stamina.
      final nextStart = breakStart + 2 * 24 * hourMs;
      s = Engine.startFocus(s, nextStart);
      expect(s.timer.staminaAtSessionStart, closeTo(100, 1e-9));
      s = killAndRelaunch(s, nextStart + 25 * minMs);
      expect(s.sessionsCompleted, 2);
      expect(s.sessionIndexInSet, 2);
      expect(s.lifetimeKm, closeTo(2 * 25 / 60, 1e-9));
    });

    test('pause → death → resume → death → completion stays exact', () {
      var s = Engine.startFocus(GameState.initial, t0);
      s = Engine.pauseFocus(s, t0 + 8 * minMs);
      s = killAndRelaunch(s, t0 + 5 * hourMs);
      expect(s.timer.phase, Phase.focusPaused);
      s = Engine.resumeFocus(s, t0 + 5 * hourMs);
      s = killAndRelaunch(s, t0 + 9 * hourMs);
      expect(s.timer.phase, Phase.focusComplete);
      expect(s.lifetimeKm, closeTo(25 / 60, 1e-9));
      // Distance and focus time resolve at the end; stamina recovers fully over
      // the hours of idle since.
      expect(s.stamina, closeTo(100, 1e-9));
      expect(s.totalFocusSeconds, 1500);
    });

    test('a set boundary resolved while dead still changes the map', () {
      // 11 completed sessions; the 12th completes while the app is dead.
      var s = GameState.initial;
      var clock = t0;
      for (var i = 0; i < 11; i++) {
        s = Engine.startFocus(s, clock);
        s = Engine.reconstruct(s, clock + 25 * minMs);
        s = Engine.skipBreak(s);
        clock += hourMs;
      }
      s = Engine.startFocus(s, clock);
      s = killAndRelaunch(s, clock + 6 * hourMs);
      expect(s.setsCompleted, 3);
      expect(s.pendingReveal!.newMapIndex, 1);
      expect(s.badgeIds, contains('map-1'));
    });
  });
}
