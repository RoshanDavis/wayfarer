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

class _WayfarerAppState extends State<WayfarerApp> with WidgetsBindingObserver {
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
              ThemePreference.system => MediaQuery.platformBrightnessOf(
                context,
              ),
            };

            final softened =
                s.timer.phase == Phase.breakRunning ||
                s.timer.phase == Phase.breakComplete;

            // Accent starts at a random place each open (accentSeed) and steps
            // through the palettes per completed session; PaletteTransition
            // crossfades to the new colour.
            final palette = buildPalette(
              map: accentForSession(
                s.sessionsCompleted,
                seed: controller.accentSeed,
              ),
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
                  child: TickerMode(enabled: _foreground, child: child!),
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
