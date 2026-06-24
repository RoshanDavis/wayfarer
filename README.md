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

```sh
flutter pub get
flutter test
```

All game logic is platform-agnostic; the same codebase targets every platform.

```sh
flutter build apk --release        # Android (minSdk 26+)
flutter build web --release        # Web (PWA)
flutter build windows --release    # Windows desktop (needs VS "Desktop development with C++")
flutter build linux --release      # Linux desktop (build on Linux/WSL2 — no cross-compile)
```

### Windows Store (MSIX)

Packaging is configured under `msix_config:` in `pubspec.yaml` (via the `msix`
dev dependency). Build with:

```powershell
pwsh tool/build_msix.ps1            # local self-signed test package
pwsh tool/build_msix.ps1 -Store     # unsigned package for Microsoft Store upload
```

The script uses `dart run msix:build` to generate the package, then the Windows
SDK's `makeappx`/`signtool` to pack and sign it (the msix package's *bundled*
makeappx fails to start on this machine — a side-by-side runtime error — so
`dart run msix:create` is not used). Output: `build/windows/x64/runner/*.msix`.

Before the first **Store** build, reserve the app in
[Partner Center](https://partner.microsoft.com/dashboard) and replace the three
`STORE`-marked values in `pubspec.yaml > msix_config` (`identity_name`,
`publisher_display_name`, `publisher`) with the ones from *Product management →
Product identity*. The Store signs the package itself, so `-Store` emits an
unsigned `.msix` on purpose. To install the **local test** package, trust its
test certificate once (the script prints the exact admin command).

Notifications use the system backend on Android, Windows and Linux; the web has
no notification backend, so those controls are hidden there (the timer and game
are unaffected). On phones the UI is portrait; on desktop/web wide windows it
stays a centred phone-width column.

**iOS / macOS** require a Mac with Xcode and cannot be built on Windows or Linux.
The codebase is ready for them (scaffold with `flutter create --platforms=ios,macos .`
on a Mac); build via a Mac or cloud macOS CI (e.g. Codemagic, GitHub Actions
`macos` runners). iOS device/store distribution also needs an Apple Developer
account.
