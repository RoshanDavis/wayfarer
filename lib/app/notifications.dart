/// Session-end notifications — the only notification this app may ever send.
///
/// One local notification is scheduled when a focus session or break starts,
/// announcing its completion; it is cancelled on pause, early end, or live
/// in-app completion. Notifications are presentation only: timer correctness
/// never depends on them. The completion banner carries the app's own chime as
/// its sound and follows the phone's ringer for vibration — it chimes when the
/// ring volume is up, vibrates when the phone is on vibrate, and stays silent
/// under Do Not Disturb.
library;

import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static const int phaseEndId = 1;

  /// The current channel id. A channel's sound and vibration are immutable once
  /// Android has created it, so a new id is the only way installs that already
  /// had the old (silent, no-vibration) 'session_end' channel pick up the chime
  /// and vibration. The legacy channel is deleted in [init].
  static const String _channelId = 'session_end_v2';
  static const String _legacyChannelId = 'session_end';
  static const String _channelName = 'Session complete';
  static const String _channelDescription =
      'Announces when a focus session or break finishes. Nothing else.';

  /// The bundled chime (res/raw/session_chime.wav) — the same tone the app
  /// plays in the foreground, produced by tool/generate_chime.dart.
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
      // Drop the legacy channel (locked to no custom sound and no vibration)
      // and create the current one with the chime and vibration. Both calls are
      // idempotent and preserve any later user customisation of session_end_v2.
      await _android?.deleteNotificationChannel(_legacyChannelId);
      await _android?.createNotificationChannel(
        const AndroidNotificationChannel(
          _channelId,
          _channelName,
          description: _channelDescription,
          importance: Importance.high,
          playSound: true,
          sound: _sound,
          enableVibration: true,
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

  Future<void> schedulePhaseEnd({
    required int atMs,
    required String title,
    required String body,
  }) async {
    if (!_ready) return;
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        sound: _sound,
        enableVibration: true,
      ),
    );
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

  Future<void> cancelPhaseEnd() async {
    if (!_ready) return;
    try {
      await _plugin.cancel(phaseEndId);
    } catch (_) {}
  }
}
