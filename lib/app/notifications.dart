/// Session-end notifications — the only notification this app may ever send.
///
/// One local notification is scheduled when a focus session or break
/// starts, announcing its completion; it is cancelled on pause, early end, or
/// live in-app completion. Notifications are presentation only: timer
/// correctness never depends on them.
library;

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static const int phaseEndId = 1;

  /// Scheduled slightly after the true end so a live in-app completion can
  /// cancel it first — when the user is looking at the app, the reveal (and
  /// optional chime) announces completion, not a banner.
  static const int graceMs = 1500;

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('ic_stat_wayfarer'),
    );
    try {
      await _plugin.initialize(settings);
      _ready = true;
    } catch (_) {
      // Notifications are optional comfort; never let them break the app.
    }
  }

  /// Android 13+ runtime permission. Denial is accepted silently — the app
  /// never nags.
  Future<void> requestPermissionOnce() async {
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
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
        'session_end',
        'Session complete',
        channelDescription:
            'Announces when a focus session or break finishes. Nothing else.',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: false,
      ),
    );
    final when = tz.TZDateTime.fromMillisecondsSinceEpoch(
        tz.UTC, atMs + graceMs);
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
