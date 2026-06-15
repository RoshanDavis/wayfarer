# Wayfarer

A calm pomodoro focus timer fused with an idle travel game. A lone runner
journeys on foot across an endless minimalist landscape — but only while a
focus session is running. Breaks restore stamina. Real focused work levels the
runner up forever: from a 1 km/h walk-jog past galloping horses, the speed of
sound, and orbital velocity. The world changes map every three completed sets,
each a new monochromatic landscape.

*One runner, one road, no finish line.*

## Design pillars

1. **One decision only** — the player only ever starts a timer.
2. **Never punish work** — low stamina slows travel (never below 50% speed);
   nothing ever blocks a session.
3. **Calm above all** — no mid-session rewards, counters, or interruptions;
   everything is revealed quietly after the session ends.
4. **Real distances, mythic speed** — the odometer is real kilometers, the
   milestones real journeys (Camino de Santiago, Earth to the Moon).

## Architecture

```
lib/
  core/      Pure Dart, no Flutter imports — the single source of truth.
             game_math (tuning constants & curves), tiers, comparisons,
             maps, badges, session_engine (state machine + wall-clock
             reconstruction), chime_synth (runtime WAV synthesis).
  data/      Versioned JSON persistence over shared_preferences.
  app/       AppController (ChangeNotifier), notifications, audio, theme
             (hue + 7-step tonal ramp token system).
  ui/        Custom-drawn everything: parallax landscape + runner painters,
             4 screens (Horizon, Session End, Journey, Settings).
test/        83 unit tests over the pure core, including time-gap
             reconstruction (process death mid-session/mid-break).
```

**Time integrity:** the app never depends on running timers. All state derives
from persisted wall-clock timestamps; on every launch/resume a pure
`reconstruct(state, now)` resolves anything that completed while the app was
backgrounded or dead — at the *scheduled* end time, identically to a live
completion. The one scheduled notification is presentation only.

**Rendering:** all visuals are `CustomPainter` paths — no bitmaps, no game
engine. Each map is pure data `{name, hue, terrain}`; landscapes are 3–4
parallax silhouette layers generated from ~9 seeded periodic terrain profiles,
tinted by the map's single accent hue (light ramp / inverted dark ramp).

## Build

```
flutter pub get
flutter test
flutter build apk --release
```

Android (minSdk 26+), portrait. iOS/web later from the same codebase — all
game logic is platform-agnostic.
