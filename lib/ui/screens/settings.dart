/// Settings — durations, theme, sound, the session-end notification, reset,
/// about. Reached by the gear on the home screen.
library;

import 'dart:async';

import 'package:flutter/services.dart' show FilteringTextInputFormatter;
import 'package:flutter/widgets.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/game_math.dart' as gm;
import '../../core/models.dart';
import '../../app/theme.dart';
import '../app_scope.dart';
import '../widgets/controls.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _confirmingReset = false;
  Timer? _confirmTimer;

  // Installed version, read from the build at runtime so it always matches the
  // APK/AAB (e.g. "1.3.2+11") — no manual pubspec sync. Empty until loaded.
  String _version = '';

  // Optional support link. Opens in the external browser and unlocks nothing
  // inside the app, so Wayfarer stays free with no in-app purchases.
  static final Uri _supportUrl =
      Uri.parse('https://buymeacoffee.com/monsoonwinds');

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _version = '${info.version}+${info.buildNumber}');
    } catch (_) {
      // Version is informational only; never let it break Settings.
    }
  }

  @override
  void dispose() {
    _confirmTimer?.cancel();
    super.dispose();
  }

  Future<void> _openSupport() async {
    await launchUrl(_supportUrl, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppScope.of(context);
    final settings = controller.state.settings;
    final p = PaletteScope.of(context);

    return ColoredBox(
      color: p.sky,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Centered title with a back chevron. The +8 top pad aligns the
            // title's line-top with the Focus header on home, so the two line up
            // when navigating between screens.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 48,
                child: Stack(
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: QuietLink(
                          label: '‹  Back',
                          onTap: () => Navigator.of(context).maybePop()),
                    ),
                    Center(
                      child: Text('SETTINGS', style: Type.label(p, size: 12)),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(34, 24, 34, 48),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('TIMERS', style: Type.label(p, size: 10)),
                    const SizedBox(height: 18),
                    _DurationRow(
                      label: 'Focus',
                      minutes: settings.focusMinutes,
                      min: gm.kFocusMinMinutes,
                      max: gm.kFocusMaxMinutes,
                      step: gm.kFocusStepMinutes,
                      onChanged: (m) =>
                          controller.setDurations(focusMinutes: m),
                    ),
                    const SizedBox(height: 18),
                    _DurationRow(
                      label: 'Short break',
                      minutes: settings.shortBreakMinutes,
                      min: gm.kShortBreakMinMinutes,
                      max: gm.kShortBreakMaxMinutes,
                      step: gm.kShortBreakStepMinutes,
                      onChanged: (m) =>
                          controller.setDurations(shortBreakMinutes: m),
                    ),
                    const SizedBox(height: 18),
                    _DurationRow(
                      label: 'Long break',
                      minutes: settings.longBreakMinutes,
                      min: gm.kLongBreakMinMinutes,
                      max: gm.kLongBreakMaxMinutes,
                      step: gm.kLongBreakStepMinutes,
                      onChanged: (m) =>
                          controller.setDurations(longBreakMinutes: m),
                    ),
                    const SizedBox(height: 44),

                    Text('THEME', style: Type.label(p, size: 10)),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        for (final pref in ThemePreference.values) ...[
                          _ThemeOption(
                            label: switch (pref) {
                              ThemePreference.system => 'System',
                              ThemePreference.light => 'Light',
                              ThemePreference.dark => 'Dark',
                            },
                            selected: settings.theme == pref,
                            onTap: () => controller.setTheme(pref),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ],
                    ),
                    const SizedBox(height: 40),

                    _ToggleRow(
                      label: 'Notifications',
                      detail: 'A quiet status while a session runs, and an '
                          'alert when it ends.',
                      value: settings.notificationsEnabled,
                      onChanged: controller.setNotificationsEnabled,
                    ),
                    // Reflects the live OS permission state: shown when the user
                    // wants alerts but Android is blocking them, with a one-tap
                    // route into system settings to re-enable.
                    ListenableBuilder(
                      listenable: controller,
                      builder: (context, _) {
                        final blocked =
                            controller.state.settings.notificationsEnabled &&
                                !controller.notificationsAuthorized;
                        if (!blocked) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Notifications are blocked by Android.',
                                style: Type.body(p,
                                    size: 12,
                                    color: p.inkSoft.withValues(alpha: 0.8)),
                              ),
                              const SizedBox(height: 14),
                              _OutlineButton(
                                label: 'OPEN NOTIFICATION SETTINGS',
                                onTap: controller.openNotificationSettings,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 48),

                    Text('DATA', style: Type.label(p, size: 10)),
                    const SizedBox(height: 14),
                    _ResetButton(
                      confirming: _confirmingReset,
                      onTap: () {
                        if (_confirmingReset) {
                          _confirmTimer?.cancel();
                          setState(() => _confirmingReset = false);
                          controller.resetData();
                        } else {
                          setState(() => _confirmingReset = true);
                          _confirmTimer =
                              Timer(const Duration(seconds: 4), () {
                            if (mounted) {
                              setState(() => _confirmingReset = false);
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 48),

                    Text('SUPPORT', style: Type.label(p, size: 10)),
                    const SizedBox(height: 14),
                    Text(
                      'Wayfarer is free, with nothing to unlock. If it has '
                      'helped your focus, you can leave a small tip — always '
                      'optional, with no effect on the app.',
                      style: Type.body(p,
                          size: 12, color: p.inkSoft.withValues(alpha: 0.8)),
                    ),
                    const SizedBox(height: 16),
                    _OutlineButton(label: 'BUY ME A COFFEE', onTap: _openSupport),
                    const SizedBox(height: 48),

                    Text('ABOUT', style: Type.label(p, size: 10)),
                    const SizedBox(height: 14),
                    Text(
                      _version.isEmpty
                          ? 'Wayfarer\n\nA calm pomodoro journey.'
                          : 'Wayfarer $_version\n\nA calm pomodoro journey.',
                      style: Type.body(p, size: 13, color: p.inkSoft),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Duration stepper row — − / value (tap to type) / +
// ---------------------------------------------------------------------------

class _DurationRow extends StatelessWidget {
  final String label;
  final int minutes;
  final int min;
  final int max;
  final int step;
  final ValueChanged<int> onChanged;

  const _DurationRow({
    required this.label,
    required this.minutes,
    required this.min,
    required this.max,
    required this.step,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return Row(
      children: [
        Expanded(child: Text(label, style: Type.body(p, size: 15))),
        _StepButton(
          glyph: _StepGlyph.minus,
          enabled: minutes > min,
          onTap: () => onChanged(gm.clampMinutes(minutes - step, min, max)),
        ),
        _ValueBox(
          minutes: minutes,
          min: min,
          max: max,
          onChanged: onChanged,
        ),
        _StepButton(
          glyph: _StepGlyph.plus,
          enabled: minutes < max,
          onTap: () => onChanged(gm.clampMinutes(minutes + step, min, max)),
        ),
      ],
    );
  }
}

enum _StepGlyph { minus, plus }

class _StepButton extends StatelessWidget {
  final _StepGlyph glyph;
  final bool enabled;
  final VoidCallback onTap;
  const _StepButton(
      {required this.glyph, required this.enabled, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    final color = p.ink.withValues(alpha: enabled ? 0.8 : 0.25);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: SizedBox(
        width: 40,
        height: 40,
        child: CustomPaint(
          painter: _StepPainter(plus: glyph == _StepGlyph.plus, color: color),
        ),
      ),
    );
  }
}

class _StepPainter extends CustomPainter {
  final bool plus;
  final Color color;
  _StepPainter({required this.plus, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide * 0.42;
    canvas.drawCircle(
        c,
        r,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2);
    final arm = size.shortestSide * 0.18;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(c - Offset(arm, 0), c + Offset(arm, 0), stroke);
    if (plus) canvas.drawLine(c - Offset(0, arm), c + Offset(0, arm), stroke);
  }

  @override
  bool shouldRepaint(_StepPainter old) =>
      old.plus != plus || old.color != color;
}

/// Displays the value; tap to type a custom number on a numeric keypad.
class _ValueBox extends StatefulWidget {
  final int minutes;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;
  const _ValueBox({
    required this.minutes,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_ValueBox> createState() => _ValueBoxState();
}

class _ValueBoxState extends State<_ValueBox> {
  final FocusNode _focus = FocusNode();
  late final TextEditingController _text =
      TextEditingController(text: '${widget.minutes}');
  bool _editing = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (_focus.hasFocus) {
      // Select the whole value so a new number replaces it.
      _text.selection =
          TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      if (!_editing) setState(() => _editing = true);
    } else if (_editing) {
      _commit();
    }
  }

  @override
  void didUpdateWidget(_ValueBox old) {
    super.didUpdateWidget(old);
    if (widget.minutes != old.minutes) {
      _text.text = '${widget.minutes}';
      if (_editing) {
        _text.selection =
            TextSelection(baseOffset: 0, extentOffset: _text.text.length);
      }
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChange);
    _focus.dispose();
    _text.dispose();
    super.dispose();
  }

  /// Parses, clamps, and reports the typed value. Idempotent; runs on focus
  /// loss (tap away, keyboard dismiss) and on submit.
  void _commit() {
    final parsed = int.tryParse(_text.text);
    final clamped =
        gm.clampMinutes(parsed ?? widget.minutes, widget.min, widget.max);
    _text.text = '$clamped';
    if (_editing) setState(() => _editing = false);
    widget.onChanged(clamped);
  }

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _focus.requestFocus,
      child: Container(
        width: 78,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: p.ink.withValues(alpha: _editing ? 0.6 : 0.22),
              width: 1.2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 34,
              child: EditableText(
                controller: _text,
                focusNode: _focus,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                maxLines: 1,
                cursorColor: p.ink,
                backgroundCursorColor: p.inkSoft,
                style: Type.body(p, size: 16, color: p.ink),
                onSubmitted: (_) => _focus.unfocus(),
              ),
            ),
            Text('m',
                style: Type.label(p,
                    size: 11, color: p.inkSoft.withValues(alpha: 0.8))),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Reset button (the one red accent in the app)
// ---------------------------------------------------------------------------

class _ResetButton extends StatelessWidget {
  final bool confirming;
  final VoidCallback onTap;
  const _ResetButton({required this.confirming, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kDangerRed.withValues(alpha: 0.9), width: 1.4),
        ),
        child: Center(
          child: Text(
            confirming
                ? 'TAP AGAIN TO ERASE THE JOURNEY'
                : 'RESET ALL DATA',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w400,
              letterSpacing: 2.0,
              color: kDangerRed,
            ),
          ),
        ),
      ),
    );
  }
}

/// A quiet bordered action in the app's neutral ink (not the danger red of
/// reset) — used for "Buy me a coffee" and the "Open notification settings"
/// recovery action, so both read identically. Full-width with a centred label,
/// matching the Reset button's footprint.
class _OutlineButton extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _OutlineButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: p.ink.withValues(alpha: 0.5), width: 1.4),
        ),
        child: Center(
          child: Text(
            label,
            style:
                Type.label(p, size: 12, color: p.ink.withValues(alpha: 0.85)),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Theme chips + toggles
// ---------------------------------------------------------------------------

class _ThemeOption extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ThemeOption(
      {required this.label, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: p.ink.withValues(alpha: selected ? 0.7 : 0.18),
            width: 1.2,
          ),
        ),
        child: Text(
          label.toUpperCase(),
          style: Type.label(p,
              size: 10.5,
              color: p.ink.withValues(alpha: selected ? 0.9 : 0.45)),
        ),
      ),
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final p = PaletteScope.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: Type.body(p, size: 15)),
                const SizedBox(height: 5),
                Text(detail,
                    style: Type.body(p,
                        size: 12, color: p.inkSoft.withValues(alpha: 0.8))),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: _Toggle(value: value, palette: p),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatelessWidget {
  final bool value;
  final Palette palette;
  const _Toggle({required this.value, required this.palette});

  @override
  Widget build(BuildContext context) {
    final p = palette;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
      width: 38,
      height: 20,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: p.ink.withValues(alpha: value ? 0.7 : 0.25), width: 1.2),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: p.ink.withValues(alpha: value ? 0.85 : 0.3),
          ),
        ),
      ),
    );
  }
}
