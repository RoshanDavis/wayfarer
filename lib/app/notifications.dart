/// Session notifications — the only notifications this app sends. Presentation
/// only: timer correctness never depends on them. Two channels:
///   • Completion alert ([phaseEndId], 'session_end_v4', high importance):
///     scheduled at phase start, announces the end with the app's chime and
///     ringer-following vibration. A fresh, distinct post so the OS re-alerts.
///   • Ongoing status ([sessionActiveId], 'session_active', low importance):
///     Android-only — a silent "Focusing until …" shade entry while backgrounded
///     that clears at end/reopen. Desktop/iOS toast backends re-alert on every
///     post, so this status is suppressed there (see [showSessionActive]).
library;

import 'dart:typed_data';

import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  /// The completion alert (chime + vibration).
  static const int phaseEndId = 1;

  /// The ongoing, silent "session in progress" status. A distinct id from
  /// [phaseEndId] so the completion alert fires as its own fresh notification
  /// and the OS reliably re-alerts, instead of silently replacing this one.
  static const int sessionActiveId = 2;

  /// The current channel id. A channel's sound and vibration are immutable once
  /// Android has created it, so a new id is the only way installs that already
  /// had the old (silent, no-vibration) 'session_end' channel pick up the chime
  /// and vibration. The legacy channel is deleted in [init].
  static const String _channelId = 'session_end_v4';
  static const String _channelName = 'Session complete';
  static const String _channelDescription =
      'Announces when a focus session or break finishes.';

  /// Low-importance, silent channel for the ongoing status notification — no
  /// sound, no vibration, no heads-up; it simply sits in the shade.
  static const String _activeChannelId = 'session_active';
  static const String _activeChannelName = 'Session in progress';
  static const String _activeChannelDescription =
      'A quiet, ongoing status shown while a focus session or break is running.';

  static final Int64List _vibrationPattern =
      Int64List.fromList([0, 500, 250, 500]);

  /// Windows toast registration. [_windowsGuid] identifies the COM activation
  /// callback and must stay stable across releases; the app-user-model id
  /// matches the Android applicationId so the app is identified consistently.
  static const String _windowsAppUserModelId = 'com.wayfarer_pomodoro.app';
  static const String _windowsGuid = '30cf9ff6-3f9c-426a-b74d-f1933607617b';

  /// The bundled completion chime (res/raw/session_chime.wav), produced by
  /// tool/generate_chime.dart. It plays via this notification's channel — the
  /// app ships no in-app audio, so the alert is the only session-end sound.
  static const AndroidNotificationSound _sound =
      RawResourceAndroidNotificationSound('session_chime');

  /// Scheduled slightly after the true end so a live in-app completion can
  /// cancel it first — when the user is looking at the app, the reveal (and
  /// optional chime) announces completion, not a banner.
  static const int graceMs = 1500;

  static const MethodChannel _platform =
      MethodChannel('wayfarer/notifications');

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<void> init() async {
    if (_ready) return;
    // flutter_local_notifications has no web backend, so leave the service
    // disabled on web and let every method below no-op. Android, Windows and
    // Linux are all supported and initialize from the settings below.
    if (kIsWeb) return;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_wayfarer'),
      windows: WindowsInitializationSettings(
        appName: 'Wayfarer',
        appUserModelId: _windowsAppUserModelId,
        guid: _windowsGuid,
      ),
      linux: LinuxInitializationSettings(defaultActionName: 'Open Wayfarer'),
    );
    try {
      await _plugin.initialize(settings);
      // Drop legacy channels to clear cached Android configuration (no sound, no vibration)
      await _android?.deleteNotificationChannel('session_end');
      await _android?.deleteNotificationChannel('session_end_v2');
      await _android?.deleteNotificationChannel('session_end_v3');
      await _android?.createNotificationChannel(
        AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          playSound: true,
          sound: _sound,
          enableVibration: true,
          vibrationPattern: _vibrationPattern,
        ),
      );
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _activeChannelId,
          _activeChannelName,
          description: _activeChannelDescription,
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
        ),
      );
      _ready = true;
    } catch (_) {
      // Notifications are optional comfort; never let them break the app.
    }
  }

  /// Whether the OS currently allows the app to post notifications.
  Future<bool> areEnabled() async {
    if (!_ready) return false;
    // Desktop backends (Windows/Linux) have no runtime permission gate — once
    // initialized, posting is allowed. Only Android exposes an enabled check.
    final android = _android;
    if (android == null) return true;
    try {
      return await android.areNotificationsEnabled() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Ensures the Android 13+ POST_NOTIFICATIONS runtime permission and returns
  /// whether notifications are now allowed. The OS shows its dialog only on the
  /// first request; once the user has denied it this is a silent no-op, and the
  /// caller should guide the user to system settings via [openSystemSettings].
  Future<bool> ensurePermission() async {
    if (!_ready) return false;
    // Desktop backends grant posting once initialized; only Android prompts.
    final android = _android;
    if (android == null) return true;
    try {
      if (await android.areNotificationsEnabled() ?? false) return true;
      return await android.requestNotificationsPermission() ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens this app's notification settings so the user can re-enable a
  /// previously denied permission.
  Future<void> openSystemSettings() async {
    try {
      await _platform.invokeMethod('openNotificationSettings');
    } catch (_) {}
  }

  /// Shared presentation for the completion alert (high importance, chime,
  /// ringer-following vibration), used by both the scheduled ([schedulePhaseEnd])
  /// and live ([showPhaseEnd]) paths so they stay identical.
  NotificationDetails get _phaseEndDetails => NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.high,
          priority: Priority.high,
          playSound: true,
          sound: _sound,
          enableVibration: true,
          vibrationPattern: _vibrationPattern,
        ),
        // Desktop backends use the system's default notification sound (the
        // bundled chime is an Android raw resource). Title and body come from
        // the show/schedule call, so empty details give a plain default alert.
        windows: const WindowsNotificationDetails(),
        linux: const LinuxNotificationDetails(),
      );

  Future<void> schedulePhaseEnd({
    required int atMs,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    final details = _phaseEndDetails;
    final when =
        tz.TZDateTime.fromMillisecondsSinceEpoch(tz.UTC, atMs + graceMs);
    try {
      // Inexact scheduling — no exact-alarm permission (Play restricts
      // USE_EXACT_ALARM to clock/calendar apps). May arrive a little late under
      // Doze; the live reveal announces completion when open, so it's fine.
      await _plugin.zonedSchedule(
        phaseEndId,
        title,
        body,
        when,
        details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    } catch (_) {}
  }

  /// Posts the completion alert immediately — used when a phase ends while the
  /// app is foregrounded, so the same heads-up banner, chime and vibration fire
  /// as when it ends in the background. Shares [phaseEndId] with the scheduled
  /// alert, so cancel that first ([cancelPhaseEnd]) to avoid a duplicate.
  Future<void> showPhaseEnd({
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    try {
      await _plugin.show(phaseEndId, title, body, _phaseEndDetails);
    } catch (_) {}
  }

  Future<void> cancelPhaseEnd() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(phaseEndId);
    } catch (_) {}
  }

  /// Shows the quiet, ongoing "session in progress" status while backgrounded.
  /// Silent and low-priority (its own channel), so it never chimes, vibrates, or
  /// peeks. [timeoutAfterMs], when given, auto-dismisses it the moment the
  /// session ends, just as the completion alert fires — leaving only the alert.
  ///
  /// Android-only: it relies on Android's silent, update-in-place ongoing
  /// notification. Desktop/iOS toast backends have no such concept — every post
  /// pops a fresh banner, so the status would re-alert on each window focus.
  /// There we suppress it and rely on the app window plus the completion alert.
  Future<void> showSessionActive({
    required String title,
    required String body,
    int? timeoutAfterMs,
  }) async {
    if (!_ready) return;
    if (defaultTargetPlatform != TargetPlatform.android) return;
    final details = NotificationDetails(
      android: AndroidNotificationDetails(
        _activeChannelId,
        _activeChannelName,
        channelDescription: _activeChannelDescription,
        importance: Importance.low,
        priority: Priority.low,
        playSound: false,
        enableVibration: false,
        silent: true,
        ongoing: true,
        autoCancel: false,
        onlyAlertOnce: true,
        showWhen: false,
        timeoutAfter: (timeoutAfterMs != null && timeoutAfterMs > 0)
            ? timeoutAfterMs
            : null,
      ),
      // Keep the ongoing status quiet on desktop too, matching the silent
      // Android channel — no sound when a session begins.
      windows: WindowsNotificationDetails(audio: WindowsNotificationAudio.silent()),
      linux: const LinuxNotificationDetails(suppressSound: true),
    );
    try {
      await _plugin.show(
        sessionActiveId,
        title,
        body,
        details,
      );
    } catch (_) {}
  }

  Future<void> cancelSessionActive() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(sessionActiveId);
    } catch (_) {}
  }
}
