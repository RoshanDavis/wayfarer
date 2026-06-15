# Smoke-test seed states (debug build + tool/seed_state.ps1)

Placeholders: `{NOW}` = current epoch ms; arithmetic offsets in ms.

1. Reconstruction → reveal with tier moment (level 9 → 10, "Wanderer"):
   timer.phase=focusRunning, segmentStartedAtMs={NOW}-1800000,
   phaseEndsAtMs={NOW}-300000, level=9, xpIntoLevel=25 (xpToNext(9)=30).
   Expect on launch: Session-end reveal, "+ 0.7 km", LEVEL 10 line,
   Wanderer tier moment, continue → break.

2. Mid-session live: phaseEndsAtMs={NOW}+1200000 (20 min left).
   Expect countdown ~20:00, runner running, parallax drift.
   Then force-stop + relaunch → countdown continues from wall clock.

3. Break running: phase=breakRunning, breakKind=short,
   phaseEndsAtMs={NOW}+240000, staminaAtBreakStart=75, stamina=75.
   Expect resting runner on rock, softened palette, countdown.

4. Map/theme spot checks (idle states): setsCompleted=3 (Golden Plains),
   9 (Pine Ridge), 15 (Canyon), 33 (Fjords), 51 (Volcanic Fields),
   63 (Night Desert), 69 (The Stratosphere); level 65 for glide gait;
   settings.theme=dark for dark-ramp variants.

5. Notification: phase=focusRunning ending {NOW}+75000,
   notificationsEnabled=true; pm grant POST_NOTIFICATIONS; press HOME;
   after ~90 s check `dumpsys notification` for the session-end banner.

6. Journey screen: lifetimeKm=850, badges [tier-10, tier-20, cmp-walking-human,
   odo-5, odo-10, odo-21, odo-42, odo-100, odo-800, map-1], dailyFocusMinutes
   spread over last 14 days. Expect odometer "850 km", "Farther than the
   Camino de Santiago.", badge grid, history bars.
