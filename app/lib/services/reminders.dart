import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../data/models.dart';

/// A date coming up on an item, e.g. a premium due in 7 days.
class Upcoming {
  const Upcoming({
    required this.item,
    required this.fieldLabel,
    required this.date,
  });

  final VaultItem item;
  final String fieldLabel;
  final DateTime date;

  int daysFrom(DateTime today) => DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
}

/// Parses the `yyyy-mm-dd` form date fields are stored in.
DateTime? parseFieldDate(String? value) {
  if (value == null || value.isEmpty) return null;
  return DateTime.tryParse(value);
}

/// Every date field on live items that falls within [within] of [today],
/// soonest first. Shown on the home screen.
List<Upcoming> upcomingDates(
  Iterable<VaultItem> items,
  DateTime today, {
  Duration within = const Duration(days: 45),
}) {
  final start = DateTime(today.year, today.month, today.day);
  final end = start.add(within);
  final out = <Upcoming>[];
  for (final item in items) {
    if (item.deleted) continue;
    for (final field in item.template.dateFields) {
      final date = parseFieldDate(item.fields[field.key]);
      if (date == null || date.isBefore(start) || date.isAfter(end)) continue;
      out.add(Upcoming(item: item, fieldLabel: field.label, date: date));
    }
  }
  out.sort((a, b) => a.date.compareTo(b.date));
  return out;
}

/// One notification to schedule.
class PlannedReminder {
  const PlannedReminder(this.when, this.daysBefore);

  final DateTime when;
  final int daysBefore;
}

/// The reminder notifications for [items], at 9 am local time on each
/// reminder day, from [now] on.
List<PlannedReminder> planReminders(Iterable<VaultItem> items, DateTime now) {
  final out = <PlannedReminder>[];
  for (final item in items) {
    if (item.deleted) continue;
    for (final reminder in item.reminders) {
      final date = parseFieldDate(item.fields[reminder.field]);
      if (date == null) continue;
      for (final days in reminder.daysBefore) {
        final day = DateTime(date.year, date.month, date.day - days, 9);
        if (day.isAfter(now)) out.add(PlannedReminder(day, days));
      }
    }
  }
  out.sort((a, b) => a.when.compareTo(b.when));
  return out;
}

/// Schedules reminder notifications on this phone. The text never names
/// the item, so nothing private shows on the lock screen.
class ReminderScheduler {
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  /// Phones limit how many alarms an app may hold; keep well under that.
  static const _maxScheduled = 60;

  Future<void> _init() async {
    if (_ready) return;
    tzdata.initializeTimeZones();
    try {
      final local = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(local.identifier));
    } on Object {
      // Fall back to UTC; reminders may then be a few hours off.
    }
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  Future<void> requestPermission() async {
    await _init();
    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();
    await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, sound: true, badge: false);
  }

  /// Replaces all scheduled reminders with the ones for [items].
  Future<void> reschedule(Iterable<VaultItem> items) async {
    try {
      await _init();
      await _plugin.cancelAll();
      final planned = planReminders(items, DateTime.now()).take(_maxScheduled);
      var id = 0;
      for (final p in planned) {
        await _plugin.zonedSchedule(
          id: id++,
          scheduledDate: tz.TZDateTime.from(p.when, tz.local),
          title: 'Twofold',
          body: p.daysBefore == 0
              ? 'Something in your vault is due today.'
              : 'Something in your vault is due in ${p.daysBefore} '
                    '${p.daysBefore == 1 ? 'day' : 'days'}.',
          notificationDetails: const NotificationDetails(
            android: AndroidNotificationDetails(
              'reminders',
              'Renewal reminders',
              channelDescription: 'Premiums, renewals and other due dates',
              visibility: NotificationVisibility.secret,
            ),
            iOS: DarwinNotificationDetails(),
          ),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      }
    } on Object {
      // Notifications unavailable (for example in tests); nothing to do.
    }
  }
}
