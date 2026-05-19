import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  static const _dailyReminderId = 2200;
  static const _channelId = 'daily_accounting_reminder';
  static const _channelName = '\u8bb0\u8d26\u63d0\u9192';
  static const _channelDescription =
      '\u6bcf\u5929\u665a\u4e0a\u63d0\u9192\u4f60\u8bb0\u4e00\u7b14\u8d26';
  static const _notificationTitle = '\u8bb0\u8d26\u63d0\u9192';
  static const _notificationBody =
      '\u55b5~\u4eca\u5929\u4f60\u8bb0\u5e10\u4e86\u561b\uff1f';

  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  bool get _isSupportedMobilePlatform => Platform.isAndroid || Platform.isIOS;

  Future<void> initialize() async {
    if (_initialized) return;

    if (!_isSupportedMobilePlatform) {
      _initialized = true;
      return;
    }

    tz_data.initializeTimeZones();
    await _configureLocalTimeZone();

    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _notifications.initialize(
      settings: const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );
    _initialized = true;
  }

  Future<void> setDailyReminderEnabled(bool enabled) async {
    await initialize();
    if (!_isSupportedMobilePlatform) return;

    await cancelDailyReminder();
    if (!enabled) return;

    await _scheduleDailyReminder();
  }

  Future<void> cancelDailyReminder() async {
    await initialize();
    if (!_isSupportedMobilePlatform) return;

    await _notifications.cancel(id: _dailyReminderId);
  }

  Future<void> _scheduleDailyReminder() async {
    final permissionGranted = await _requestNotificationPermission();
    if (!permissionGranted) return;

    final scheduledTime = _nextTenPm();
    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
      ),
    );

    try {
      await _notifications.zonedSchedule(
        id: _dailyReminderId,
        title: _notificationTitle,
        body: _notificationBody,
        scheduledDate: scheduledTime,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: _channelId,
      );
    } on PlatformException {
      await _notifications.zonedSchedule(
        id: _dailyReminderId,
        title: _notificationTitle,
        body: _notificationBody,
        scheduledDate: scheduledTime,
        notificationDetails: details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: _channelId,
      );
    }
  }

  Future<bool> _requestNotificationPermission() async {
    if (Platform.isAndroid) {
      final androidPlugin = _notifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final notificationAllowed =
          await androidPlugin?.requestNotificationsPermission() ?? true;
      if (!notificationAllowed) return false;

      final canScheduleExact =
          await androidPlugin?.canScheduleExactNotifications() ?? true;
      if (!canScheduleExact) {
        await androidPlugin?.requestExactAlarmsPermission();
      }
      return true;
    }

    final iosPlugin = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await iosPlugin?.requestPermissions(
          alert: true,
          badge: false,
          sound: true,
        ) ??
        true;
  }

  Future<void> _configureLocalTimeZone() async {
    try {
      final timezoneInfo = await FlutterTimezone.getLocalTimezone();
      _setLocalLocation(timezoneInfo.identifier);
    } catch (_) {
      _setLocalLocation('Asia/Shanghai');
    }
  }

  void _setLocalLocation(String identifier) {
    try {
      tz.setLocalLocation(tz.getLocation(identifier));
    } catch (_) {
      tz.setLocalLocation(tz.getLocation('Asia/Shanghai'));
    }
  }

  tz.TZDateTime _nextTenPm() {
    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      22,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }
}
