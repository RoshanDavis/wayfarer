/// Session notifications — the only notifications this app may ever send.
///
/// Two kinds, on two channels:
///   • The completion alert (id [phaseEndId], channel 'session_end_v4',
///     high importance): scheduled when a focus session or break starts,
///     announcing its end. It carries the app's own chime and follows the
///     phone's ringer for vibration — chiming when the ring volume is up,
///     vibrating on vibrate, silent under Do Not Disturb. It is a fresh,
///     distinct post (separate from the ongoing status below) so the OS always
///     re-alerts when it fires.
///   • The ongoing status (id [sessionActiveId], channel 'session_active',
///     low importance): a quiet "Focusing until …" banner shown while the app
///     is in the background. No sound, no vibration, no heads-up — it just sits
///     in the shade and clears when the session ends or the app is reopened.
///
/// Notifications are presentation only: timer correctness never depends on them.
library;

import 'dart:typed_data';

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
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_wayfarer'),
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
    try {
      return await _android?.areNotificationsEnabled() ?? false;
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
    try {
      if (await _android?.areNotificationsEnabled() ?? false) return true;
      return await _android?.requestNotificationsPermission() ?? false;
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

  /// The shared presentation for the completion alert — high importance, the
  /// bundled chime, and the ringer-following vibration. Used both when the alert
  /// is scheduled ([schedulePhaseEnd]) and when it is posted live in the
  /// foreground ([showPhaseEnd]), so the two paths stay identical.
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
      // Inexact scheduling — the app requests no exact-alarm permission (Google
      // Play restricts USE_EXACT_ALARM to clock/calendar apps). The banner may
      // arrive a little late under Doze; when the app is open the live reveal
      // announces completion first, and correctness never depends on it.
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
  Future<void> showSessionActive({
    required String title,
    required String body,
    int? timeoutAfterMs,
  }) async {
    if (!_ready) return;
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
