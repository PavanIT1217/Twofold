import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/core/crypto/twofold_crypto.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/data/vault.dart';

import '../helpers.dart';

void main() {
  late TwofoldCrypto crypto;
  late Directory tmp;
  var n = 0;

  setUpAll(() async => crypto = await TwofoldCrypto.init());
  setUp(() async => tmp = await Directory.systemTemp.createTemp('twofold'));
  tearDown(() async => tmp.delete(recursive: true));

  TestPhone phone(String name) =>
      TestPhone(crypto, name, Directory('${tmp.path}/${name}_${n++}'));

  /// Owner adds partner, and partner receives everything the way a joining
  /// phone does: the keyring and records are written, then the vault opens.
  Future<Vault> join(TestPhone owner, TestPhone partner, Role role) async {
    await owner.vault!.addMember(
      id: partner.memberId,
      name: partner.name,
      publicKey: partner.identity.publicKey,
      role: role,
    );
    await partner.store.writeKeyring(owner.vault!.keyring);
    for (final id in owner.vault!.manifest().keys) {
      await partner.store.writeItem(owner.vault!.export(id));
    }
    return (await partner.reopen())!;
  }

  test('create, save and reopen', () async {
    final ravi = phone('Ravi');
    final vault = await ravi.createVault('Family');
    final saved = await vault.save(
      vault
          .draft('life_insurance')
          .copyWith(
            title: 'Term plan',
            fields: {'policy_no': 'T-991', 'next_due': '2027-01-15'},
            whatToDo: 'Call the agent first.',
          ),
    );
    expect(saved.vv.total, 1);

    final reopened = (await ravi.reopen())!;
    expect(reopened.roster.vaultName, 'Family');
    expect(reopened.myRole, Role.owner);
    expect(reopened.items.single.fields['policy_no'], 'T-991');
    expect(reopened.items.single.whatToDo, 'Call the agent first.');
  });

  test('nothing readable is written to disk', () async {
    final ravi = phone('Ravi');
    final vault = await ravi.createVault();
    await vault.save(vault.draft('note').copyWith(title: 'SECRET-TITLE-123'));
    final files = ravi.dir.listSync(recursive: true).whereType<File>();
    for (final f in files) {
      expect(
        String.fromCharCodes(f.readAsBytesSync()).contains('SECRET-TITLE-123'),
        isFalse,
        reason: f.path,
      );
    }
  });

  test('trash, restore and purge', () async {
    final vault = await phone('Ravi').createVault();
    final item = await vault.save(vault.draft('note').copyWith(title: 'Old'));
    await vault.moveToTrash(item.id);
    expect(vault.items, isEmpty);
    expect(vault.trash.single.id, item.id);
    await vault.restore(item.id);
    expect(vault.items.single.id, item.id);
    await vault.moveToTrash(item.id);
    await vault.purge(item.id);
    expect(vault.trash, isEmpty);
    expect(vault.item(item.id)!.type, 'purged');
    expect(vault.item(item.id)!.title, '');
  });

  test('old trash is emptied after 30 days', () async {
    var now = DateTime(2027, 1, 1);
    final ravi = phone('Ravi');
    final vault = await Vault.create(
      crypto: crypto,
      store: ravi.store,
      identity: ravi.identity,
      memberId: ravi.memberId,
      memberName: 'Ravi',
      vaultName: 'v',
      clock: () => now,
    );
    final item = await vault.save(vault.draft('note').copyWith(title: 'x'));
    await vault.moveToTrash(item.id);
    now = now.add(const Duration(days: 29));
    expect(await vault.emptyOldTrash(), 0);
    now = now.add(const Duration(days: 2));
    expect(await vault.emptyOldTrash(), 1);
  });

  test('attachments are encrypted and come back intact', () async {
    final ravi = phone('Ravi');
    final vault = await ravi.createVault();
    final bytes = Uint8List.fromList(List.generate(200000, (i) => i % 251));
    final a = await vault.addAttachment(
      bytes: bytes,
      name: 'deed.pdf',
      mime: 'application/pdf',
    );
    await vault.save(
      vault.draft('property').copyWith(title: 'Flat', attachments: [a]),
    );
    final reopened = (await ravi.reopen())!;
    expect(
      await reopened.readAttachment(reopened.items.single.attachments.single),
      bytes,
    );
  });

  test('a partner joins and opens the same vault', () async {
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    final vault = await ravi.createVault();
    await vault.save(vault.draft('note').copyWith(title: 'Hello'));
    final hers = await join(ravi, priya, Role.editor);
    expect(hers.items.single.title, 'Hello');
    expect(hers.myRole, Role.editor);
    expect(
      hers.roster.active.map((m) => m.name),
      containsAll(['Ravi', 'Priya']),
    );
  });

  test('edits flow both ways', () async {
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    final mine = await ravi.createVault();
    final hers = await join(ravi, priya, Role.editor);

    final note = await hers.save(
      hers.draft('note').copyWith(title: 'From Priya'),
    );
    await syncVaults(mine, hers);
    expect(mine.item(note.id)!.title, 'From Priya');

    await mine.save(mine.item(note.id)!.copyWith(title: 'Edited by Ravi'));
    final (_, toHer) = await syncVaults(mine, hers);
    expect(toHer.updated, 1);
    expect(hers.item(note.id)!.title, 'Edited by Ravi');

    // Nothing new: a second sync moves nothing.
    final (a, b) = await syncVaults(mine, hers);
    expect(a.changedAnything || b.changedAnything, isFalse);
  });

  test('simultaneous edits keep both versions and converge', () async {
    var now = DateTime(2027, 1, 1);
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    ravi.vault = await Vault.create(
      crypto: crypto,
      store: ravi.store,
      identity: ravi.identity,
      memberId: ravi.memberId,
      memberName: 'Ravi',
      vaultName: 'v',
      clock: () => now,
    );
    final hers = await join(ravi, priya, Role.editor);
    final mine = ravi.vault!;
    final item = await mine.save(mine.draft('note').copyWith(title: 'Locker'));
    await syncVaults(mine, hers);

    await mine.save(mine.item(item.id)!.copyWith(notes: 'Ravi version'));
    now = now.add(const Duration(minutes: 1));
    await hers.save(hers.item(item.id)!.copyWith(notes: 'Priya version'));

    final (a, b) = await syncVaults(mine, hers);
    expect(a.conflicts + b.conflicts, greaterThan(0));
    await syncVaults(mine, hers);

    String describe(Vault v) =>
        (v.items.map((i) => '${i.title}|${i.notes}').toList()..sort()).join(
          ';',
        );
    expect(describe(mine), describe(hers));
    expect(describe(mine), contains('Priya version'));
    expect(describe(mine), contains('Ravi version'));
    expect(
      mine.items.where((i) => i.title.contains('conflict copy')),
      hasLength(1),
    );
  });

  test('a viewer cannot change items', () async {
    final ravi = phone('Ravi');
    final amma = phone('Amma');
    await ravi.createVault();
    final hers = await join(ravi, amma, Role.viewer);
    expect(() => hers.save(hers.draft('note')), throwsStateError);
  });

  test('removing a member rotates the key', () async {
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    final guest = phone('Guest');
    final mine = await ravi.createVault();
    final hers = await join(ravi, priya, Role.editor);
    await join(ravi, guest, Role.editor);

    await mine.removeMember(guest.memberId);
    expect(mine.keyVersion, 2);
    expect(mine.keyring.versions[2]!.containsKey(guest.memberId), isFalse);
    expect(mine.keyring.versions[2]!.containsKey(priya.memberId), isTrue);

    final secret = await mine.save(
      mine.draft('note').copyWith(title: 'After removal'),
    );
    await syncVaults(mine, hers);
    expect(hers.keyVersion, 2);
    expect(hers.item(secret.id)!.title, 'After removal');

    // The removed phone gets the new records but cannot read them.
    await guest.store.writeKeyring(mine.keyring);
    await guest.store.writeItem(mine.export(secret.id));
    final reopened = await guest.reopen();
    expect(reopened, isNotNull);
    expect(reopened!.item(secret.id), isNull);
  });

  test('owners cannot leave the vault without an owner', () async {
    final ravi = phone('Ravi');
    final vault = await ravi.createVault();
    expect(
      () => vault.changeRole(ravi.memberId, Role.editor),
      throwsStateError,
    );
  });

  test('at most six members', () async {
    final ravi = phone('Ravi');
    final vault = await ravi.createVault();
    for (var i = 0; i < 5; i++) {
      final p = phone('P$i');
      await vault.addMember(
        id: p.memberId,
        name: p.name,
        publicKey: p.identity.publicKey,
        role: Role.viewer,
      );
    }
    final extra = phone('Extra');
    expect(
      () => vault.addMember(
        id: extra.memberId,
        name: 'x',
        publicKey: extra.identity.publicKey,
        role: Role.viewer,
      ),
      throwsStateError,
    );
  });
}
