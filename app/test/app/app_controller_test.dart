import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/app/app_controller.dart';
import 'package:twofold/core/crypto/twofold_crypto.dart';
import 'package:twofold/data/vault_store.dart';
import 'package:twofold/services/reminders.dart';

/// Reminders that do nothing, so tests don't need the notifications plugin.
class _NoReminders extends ReminderScheduler {
  @override
  Future<void> reschedule(Iterable items) async {}

  @override
  Future<void> requestPermission() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TwofoldCrypto crypto;
  late Directory tmp;

  setUpAll(() async => crypto = await TwofoldCrypto.init());
  setUp(() async => tmp = await Directory.systemTemp.createTemp('twofold'));
  tearDown(() async => tmp.delete(recursive: true));

  AppController controller(String name) => AppController(
    crypto: crypto,
    store: VaultStore(Directory('${tmp.path}/$name')),
    reminders: _NoReminders(),
    enableLan: false,
  );

  test('create, lock, unlock with password and recovery key', () async {
    final app = controller('phone');
    await app.init();
    expect(app.stage, AppStage.welcome);

    await app.createVault(
      name: 'Ravi',
      vaultName: 'Family',
      password: 'correct horse battery',
    );
    expect(app.stage, AppStage.open);
    final recovery = app.pendingRecoveryKey!;
    app.recoveryKitSaved();
    await app.saveItem(
      app.vault!.draft('note').copyWith(title: 'Locker key is with Amma'),
    );

    app.lock();
    expect(app.stage, AppStage.locked);
    expect(app.vault, isNull);

    await expectLater(
      app.unlockWithPassword('wrong password!'),
      throwsA(isA<TwofoldCryptoException>()),
    );
    await app.unlockWithPassword('correct horse battery');
    expect(app.vault!.items.single.title, 'Locker key is with Amma');

    app.lock();
    await app.unlockWithRecoveryKey(
      recovery.toLowerCase().replaceAll('-', ' '),
    );
    expect(app.stage, AppStage.open);
  });

  test('the state survives a restart', () async {
    final first = controller('phone');
    await first.init();
    await first.createVault(
      name: 'Ravi',
      vaultName: 'Family',
      password: 'correct horse battery',
    );
    await first.saveItem(first.vault!.draft('note').copyWith(title: 'Kept'));
    await first.setAutoLock(300);

    final second = controller('phone');
    await second.init();
    expect(second.stage, AppStage.locked);
    expect(second.myName, 'Ravi');
    expect(second.settings.autoLockSeconds, 300);
    await second.unlockWithPassword('correct horse battery');
    expect(second.vault!.items.single.title, 'Kept');
  });

  test('changing the password and making a new recovery key', () async {
    final app = controller('phone');
    await app.init();
    await app.createVault(
      name: 'Ravi',
      vaultName: 'Family',
      password: 'first password',
    );
    final oldRecovery = app.pendingRecoveryKey!;

    await expectLater(
      app.changePassword('not it at all', 'second password'),
      throwsA(isA<TwofoldCryptoException>()),
    );
    await app.changePassword('first password', 'second password');
    final newRecovery = await app.newRecoveryKey();

    app.lock();
    await expectLater(
      app.unlockWithPassword('first password'),
      throwsA(isA<TwofoldCryptoException>()),
    );
    await expectLater(
      app.unlockWithRecoveryKey(oldRecovery),
      throwsA(isA<TwofoldCryptoException>()),
    );
    await app.unlockWithRecoveryKey(newRecovery);
    app.lock();
    await app.unlockWithPassword('second password');
    expect(app.stage, AppStage.open);
  });

  test('a backup restores on a new phone, attachments included', () async {
    final old = controller('old');
    await old.init();
    await old.createVault(
      name: 'Ravi',
      vaultName: 'Family',
      password: 'correct horse battery',
    );
    final scan = await old.addAttachment(
      Uint8List.fromList(List.generate(3000, (i) => i % 7)),
      'deed.jpg',
      'image/jpeg',
    );
    await old.saveItem(
      old.vault!.draft('property').copyWith(title: 'Flat', attachments: [scan]),
    );
    final backup = await old.backupBytes();

    final fresh = controller('new');
    await fresh.init();
    await fresh.restoreBackup(backup);
    expect(fresh.stage, AppStage.locked);
    expect(fresh.myName, 'Ravi');
    await fresh.unlockWithPassword('correct horse battery');
    final item = fresh.vault!.items.single;
    expect(item.title, 'Flat');
    expect(
      await fresh.readAttachment(item.attachments.single),
      List.generate(3000, (i) => i % 7),
    );
  });

  test('a damaged backup file is rejected', () async {
    final app = controller('phone');
    await app.init();
    await expectLater(
      app.restoreBackup(Uint8List.fromList('not a backup'.codeUnits)),
      throwsA(isA<TwofoldCryptoException>()),
    );
    expect(app.stage, AppStage.welcome);
  });

  test('deleting everything starts over', () async {
    final app = controller('phone');
    await app.init();
    await app.createVault(
      name: 'Ravi',
      vaultName: 'Family',
      password: 'correct horse battery',
    );
    await app.deleteEverything();
    expect(app.stage, AppStage.welcome);
    final again = controller('phone');
    await again.init();
    expect(again.stage, AppStage.welcome);
  });
}
