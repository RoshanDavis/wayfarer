/// Wayfarer — a calm pomodoro idle-travel app.
/// One runner, one road, no finish line.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app/app_controller.dart';
import 'app/notifications.dart';
import 'app/theme.dart';
import 'core/maps.dart';
import 'core/models.dart';
import 'data/persistence.dart';
import 'ui/app_scope.dart';
import 'ui/screens/home.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

  final persistence = await Persistence.open();
  final notifications = NotificationService();
  await notifications.init();
  final controller = AppController(
    persistence: persistence,
    notifications: notifications,
  );
  runApp(WayfarerApp(controller: controller));
}

class WayfarerApp extends StatefulWidget {
  final AppController controller;
  const WayfarerApp({super.key, required this.controller});

  @override
  State<WayfarerApp> createState() => _WayfarerAppState();
}

class _WayfarerAppState extends State<WayfarerApp>
    with WidgetsBindingObserver {
  bool _foreground = true;

  AppController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        setState(() => _foreground = true);
        controller.onAppResumed();
      case AppLifecycleState.inactive:
        // Transient (permission dialog, shade, call, app switcher) — not a real
        // background: keep ticking and don't post the ongoing status (it would
        // flash in and out). A genuine background follows with hidden/paused.
        break;
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        if (_foreground) setState(() => _foreground = false);
        controller.onAppPaused();
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Wayfarer',
        debugShowCheckedModeBanner: false,
        // The palette is provided above the Navigator so every route —
        // Horizon, the reveal, Journey, Settings — shares the same animated
        // tonal ramp.
        builder: (context, child) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final s = controller.state;
            final brightness = switch (s.settings.theme) {
              ThemePreference.light => Brightness.light,
              ThemePreference.dark => Brightness.dark,
              ThemePreference.system =>
                MediaQuery.platformBrightnessOf(context),
            };

            final softened = s.timer.phase == Phase.breakRunning ||
                s.timer.phase == Phase.breakComplete;

            // Accent starts at a random place each open (accentSeed) and steps
            // through the palettes per completed session; PaletteTransition
            // crossfades to the new colour.
            final palette = buildPalette(
              map: accentForSession(s.sessionsCompleted,
                  seed: controller.accentSeed),
              brightness: brightness,
              cycle: mapCycleForLevel(s.level),
              soften: softened ? 1 : 0,
            );

            final overlayStyle = brightness == Brightness.dark
                ? SystemUiOverlayStyle.light
                : SystemUiOverlayStyle.dark;

            return PaletteTransition(
              target: palette,
              child: AnnotatedRegion<SystemUiOverlayStyle>(
                value: overlayStyle.copyWith(
                  statusBarColor: const Color(0x00000000),
                  systemNavigationBarColor: const Color(0x00000000),
                ),
                // Transparent Material gives Text its DefaultTextStyle —
                // nothing of stock Material is ever visible.
                child: Material(
                  type: MaterialType.transparency,
                  // On wide desktop/web windows, scale the portrait UI up to
                  // fill the window at a tablet-like aspect; on phones it passes
                  // through unchanged.
                  child: TickerMode(
                    enabled: _foreground,
                    child: _AdaptiveShell(
                      skyColor: palette.sky,
                      groundColor: palette.near,
                      child: child!,
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        home: _Root(controller: controller),
      ),
    );
  }
}

/// Scales the phone-designed UI *up* to fill larger windows (desktop, web, big
/// tablets) instead of leaving it small with empty margins. The app is always
/// laid out at the same phone design width and then uniformly scaled to the
/// window — so a Pixel-tablet-sized window shows the same layout, just bigger,
/// the way a phone app looks scaled up on a tablet.
///
/// To avoid the layout collapsing to a short/landscape shape on a wide monitor,
/// the laid-out canvas is kept within a portrait-tablet aspect band: the window
/// is filled edge-to-edge for any aspect inside the band, and only letterboxed
/// for aspect ratios outside it. The letterbox is a sky→ground vertical gradient
/// so the margins read as the scene's atmosphere continuing, not dead bars.
/// Phones (≤ the design width) pass straight through, so mobile is unchanged.
class _AdaptiveShell extends StatelessWidget {
  final Color skyColor;
  final Color groundColor;
  final Widget child;
  const _AdaptiveShell({
    required this.skyColor,
    required this.groundColor,
    required this.child,
  });

  /// The width the UI is designed and laid out at. At or below this the child
  /// passes through untouched (phones); above it the child is scaled up.
  static const double _designWidth = 480;

  /// Portrait-tablet aspect band (width / height) the laid-out canvas is held
  /// within, so the design never becomes too tall-and-thin or too square.
  static const double _minAspect = 0.50;
  static const double _maxAspect = 0.75;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final win = mq.size;
    // Phones: leave the native layout exactly as designed.
    if (win.width <= _designWidth || win.height <= 0) return child;

    final winAspect = win.width / win.height;
    final designAspect = winAspect.clamp(_minAspect, _maxAspect);
    final designHeight = _designWidth / designAspect;
    // Uniform scale that fits the design canvas into the window (contain).
    final wScale = win.width / _designWidth;
    final hScale = win.height / designHeight;
    final scale = wScale < hScale ? wScale : hScale;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [skyColor, groundColor],
        ),
      ),
      child: Center(
        // The outer box has the design's exact aspect, so BoxFit.fill scales
        // without distortion; any leftover window area shows the gradient behind.
        child: SizedBox(
          width: _designWidth * scale,
          height: designHeight * scale,
          // An explicit ClipRect (not FittedBox.clipBehavior, which only clips
          // on detected layout overflow) contains the landscape painters'
          // parallax overflow so it can't bleed into the gradient margins.
          child: ClipRect(
            child: FittedBox(
              fit: BoxFit.fill,
              child: SizedBox(
                width: _designWidth,
                height: designHeight,
                // Report the design size to the app so its MediaQuery-derived
                // metrics (panel height, insets) match the box it's laid in.
                child: MediaQuery(
                  data: mq.copyWith(
                    size: Size(_designWidth, designHeight),
                    padding: EdgeInsets.zero,
                    viewPadding: EdgeInsets.zero,
                    viewInsets: EdgeInsets.zero,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The home route — a single scrollable surface. Rebuilds on every state
/// change so the timer, distance, and journey stay live.
class _Root extends StatelessWidget {
  final AppController controller;
  const _Root({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => const HomeScreen(),
    );
  }
}
