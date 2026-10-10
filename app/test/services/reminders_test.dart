import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/services/reminders.dart';

VaultItem _policy(
  Map<String, String> fields, {
  List<Reminder> reminders = const [],
  bool deleted = false,
}) => VaultItem(
  id: 'x',
  type: 'health_insurance',
  title: 'Family floater',
  fields: fields,
  reminders: reminders,
  deleted: deleted,
  createdAt: DateTime(2027),
  updatedAt: DateTime(2027),
  updatedBy: 'm',
);

void main() {
  final today = DateTime(2027, 3, 1, 10);

  test('upcoming dates are listed soonest first', () {
    final items = [
      _policy({'next_due': '2027-03-20', 'expiry': '2027-03-05'}),
      _policy({'next_due': '2027-02-01'}), // already past
      _policy({'next_due': '2027-06-01'}), // too far
      _policy({'next_due': '2027-03-02'}, deleted: true),
    ];
    final upcoming = upcomingDates(items, today);
    expect(upcoming.map((u) => u.daysFrom(today)), [4, 19]);
    expect(upcoming.first.fieldLabel, 'Policy end date');
  });

  test('reminders fire 30, 7 and 1 days before at 9 am', () {
    final item = _policy(
      {'next_due': '2027-04-10'},
      reminders: const [Reminder(field: 'next_due')],
    );
    final planned = planReminders([item], today);
    expect(planned.map((p) => p.when), [
      DateTime(2027, 3, 11, 9),
      DateTime(2027, 4, 3, 9),
      DateTime(2027, 4, 9, 9),
    ]);
    expect(planned.map((p) => p.daysBefore), [30, 7, 1]);
  });

  test('reminders already in the past are skipped', () {
    final item = _policy(
      {'next_due': '2027-03-05'},
      reminders: const [Reminder(field: 'next_due')],
    );
    expect(planReminders([item], today).map((p) => p.daysBefore), [1]);
  });

  test('a cleared date schedules nothing', () {
    final item = _policy({}, reminders: const [Reminder(field: 'next_due')]);
    expect(planReminders([item], today), isEmpty);
  });
}
