class ReminderService {
  Future<void> initialize() async {}

  Future<void> setDailyReminderEnabled(
    bool enabled, {
    int hour = 22,
    int minute = 0,
    String? title,
    String? body,
  }) async {}

  Future<void> cancelDailyReminder() async {}
}
