import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/core/crypto/twofold_crypto.dart';

void main() {
  late TwofoldCrypto crypto;
  late KdfParams fastKdf;

  setUpAll(() async {
    crypto = await TwofoldCrypto.init();
    // Real vaults use the slow defaults; tests use the minimum so they run fast.
    fastKdf = crypto.kdf.newParams(opsLimit: 1, memLimit: 8 * 1024 * 1024);
  });

  Uint8List flipByte(Uint8List data, int index) {
    final copy = Uint8List.fromList(data);
    copy[index] ^= 0x01;
    return copy;
  }

  group('password key', () {
    test('same password and salt give the same key', () {
      final a = crypto.kdf.derive('correct horse', fastKdf);
      final b = crypto.kdf.derive('correct horse', fastKdf);
      expect(a.extractBytes(), b.extractBytes());
    });

    test('different salt gives a different key', () {
      final other = crypto.kdf.newParams(
        opsLimit: 1,
        memLimit: 8 * 1024 * 1024,
      );
      final a = crypto.kdf.derive('correct horse', fastKdf);
      final b = crypto.kdf.derive('correct horse', other);
      expect(a.extractBytes(), isNot(b.extractBytes()));
    });

    test('rejects an empty password', () {
      expect(
        () => crypto.kdf.derive('', fastKdf),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('params survive JSON', () {
      final back = KdfParams.fromJson(fastKdf.toJson());
      expect(back.opsLimit, fastKdf.opsLimit);
      expect(back.memLimit, fastKdf.memLimit);
      expect(back.salt, fastKdf.salt);
    });
  });

  group('recovery key', () {
    test('format and parse round-trip', () {
      final key = crypto.recoveryKeys.generate();
      final text = crypto.recoveryKeys.format(key);
      expect(text, matches(RegExp(r'^([0-9A-Z]{4}-)+[0-9A-Z]{1,4}$')));
      expect(
        crypto.recoveryKeys.parse(text).extractBytes(),
        key.extractBytes(),
      );
    });

    test('forgives case, spaces and look-alike letters', () {
      final key = crypto.recoveryKeys.generate();
      final text = crypto.recoveryKeys.format(key);
      final messy = text
          .toLowerCase()
          .replaceAll('-', ' ')
          .replaceAll('1', 'l')
          .replaceAll('0', 'o');
      expect(
        crypto.recoveryKeys.parse(messy).extractBytes(),
        key.extractBytes(),
      );
    });

    test('catches a typo', () {
      final text = crypto.recoveryKeys.format(crypto.recoveryKeys.generate());
      final typo = (text[0] == 'A' ? 'B' : 'A') + text.substring(1);
      expect(
        () => crypto.recoveryKeys.parse(typo),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('rejects the wrong length', () {
      expect(
        () => crypto.recoveryKeys.parse('ABCD-EFGH'),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });
  });

  group('identity', () {
    test('unlocks with password and with recovery key', () {
      final recovery = crypto.recoveryKeys.generate();
      final created = crypto.identities.create(
        password: 'pw-123',
        recoveryKey: recovery,
        kdfParams: fastKdf,
      );
      final locked = LockedIdentity.fromJson(created.locked.toJson());

      final byPassword = crypto.identities.unlockWithPassword(locked, 'pw-123');
      expect(
        byPassword.secretKey.extractBytes(),
        created.identity.secretKey.extractBytes(),
      );

      final byRecovery = crypto.identities.unlockWithRecoveryKey(
        locked,
        recovery,
      );
      expect(
        byRecovery.secretKey.extractBytes(),
        created.identity.secretKey.extractBytes(),
      );
    });

    test('wrong password fails', () {
      final created = crypto.identities.create(
        password: 'pw-123',
        recoveryKey: crypto.recoveryKeys.generate(),
        kdfParams: fastKdf,
      );
      expect(
        () => crypto.identities.unlockWithPassword(created.locked, 'pw-124'),
        throwsA(
          isA<TwofoldCryptoException>().having(
            (e) => e.message,
            'message',
            'Wrong master password.',
          ),
        ),
      );
    });

    test('wrong recovery key fails', () {
      final created = crypto.identities.create(
        password: 'pw-123',
        recoveryKey: crypto.recoveryKeys.generate(),
        kdfParams: fastKdf,
      );
      expect(
        () => crypto.identities.unlockWithRecoveryKey(
          created.locked,
          crypto.recoveryKeys.generate(),
        ),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('a swapped public key is detected', () {
      final recovery = crypto.recoveryKeys.generate();
      final created = crypto.identities.create(
        password: 'pw',
        recoveryKey: recovery,
        kdfParams: fastKdf,
      );
      final other = crypto.identities.create(
        password: 'pw',
        recoveryKey: recovery,
        kdfParams: fastKdf,
      );
      final tampered = LockedIdentity(
        publicKey: other.identity.publicKey,
        kdf: created.locked.kdf,
        byPassword: created.locked.byPassword,
        byRecoveryKey: created.locked.byRecoveryKey,
      );
      expect(
        () => crypto.identities.unlockWithPassword(tampered, 'pw'),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('changing the password keeps the same identity', () {
      final recovery = crypto.recoveryKeys.generate();
      final created = crypto.identities.create(
        password: 'old',
        recoveryKey: recovery,
        kdfParams: fastKdf,
      );
      final relocked = crypto.identities.lock(
        created.identity,
        password: 'new',
        recoveryKey: recovery,
        kdfParams: crypto.kdf.newParams(opsLimit: 1, memLimit: 8 * 1024 * 1024),
      );
      expect(
        () => crypto.identities.unlockWithPassword(relocked, 'old'),
        throwsA(isA<TwofoldCryptoException>()),
      );
      expect(
        crypto.identities.unlockWithPassword(relocked, 'new').publicKey,
        created.identity.publicKey,
      );
    });
  });

  group('password and recovery key changes', () {
    test('changing the password keeps the recovery key working', () {
      final recovery = crypto.recoveryKeys.generate();
      final created = crypto.identities.create(
        password: 'old',
        recoveryKey: recovery,
        kdfParams: fastKdf,
      );
      final changed = crypto.identities.changePassword(
        created.locked,
        created.identity,
        newPassword: 'new',
        kdfParams: crypto.kdf.newParams(opsLimit: 1, memLimit: 8 * 1024 * 1024),
      );
      expect(
        () => crypto.identities.unlockWithPassword(changed, 'old'),
        throwsA(isA<TwofoldCryptoException>()),
      );
      expect(
        crypto.identities.unlockWithPassword(changed, 'new').publicKey,
        created.identity.publicKey,
      );
      expect(
        crypto.identities.unlockWithRecoveryKey(changed, recovery).publicKey,
        created.identity.publicKey,
      );
    });

    test('a new recovery key replaces the old one', () {
      final oldKey = crypto.recoveryKeys.generate();
      final newKey = crypto.recoveryKeys.generate();
      final created = crypto.identities.create(
        password: 'pw',
        recoveryKey: oldKey,
        kdfParams: fastKdf,
      );
      final replaced = crypto.identities.replaceRecoveryKey(
        created.locked,
        created.identity,
        newKey,
      );
      expect(
        () => crypto.identities.unlockWithRecoveryKey(replaced, oldKey),
        throwsA(isA<TwofoldCryptoException>()),
      );
      expect(
        crypto.identities.unlockWithRecoveryKey(replaced, newKey).publicKey,
        created.identity.publicKey,
      );
      expect(
        crypto.identities.unlockWithPassword(replaced, 'pw').publicKey,
        created.identity.publicKey,
      );
    });

    test('a biometric key must match the identity', () {
      final created = crypto.identities.create(
        password: 'pw',
        recoveryKey: crypto.recoveryKeys.generate(),
        kdfParams: fastKdf,
      );
      final raw = created.identity.secretKey.extractBytes();
      expect(
        crypto.identities.fromSecretKey(created.locked, raw).publicKey,
        created.identity.publicKey,
      );
      final other = crypto.sodium.crypto.box.keyPair().secretKey.extractBytes();
      expect(
        () => crypto.identities.fromSecretKey(created.locked, other),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });
  });

  group('vault key sharing', () {
    late Identity me;
    late Identity partner;

    setUp(() {
      me = crypto.identities
          .create(
            password: 'a',
            recoveryKey: crypto.recoveryKeys.generate(),
            kdfParams: fastKdf,
          )
          .identity;
      partner = crypto.identities
          .create(
            password: 'b',
            recoveryKey: crypto.recoveryKeys.generate(),
            kdfParams: fastKdf,
          )
          .identity;
    });

    test('each member opens the same vault key', () {
      final vaultKey = crypto.vaultKeys.create();
      for (final member in [me, partner]) {
        final sealed = crypto.vaultKeys.sealFor(
          vaultKey: vaultKey,
          memberPublicKey: member.publicKey,
          vaultId: 'v1',
          keyVersion: 1,
        );
        final opened = crypto.vaultKeys.open(
          sealed: sealed,
          identity: member,
          vaultId: 'v1',
          keyVersion: 1,
        );
        expect(opened.extractBytes(), vaultKey.extractBytes());
      }
    });

    test('a key sealed for someone else cannot be opened', () {
      final sealed = crypto.vaultKeys.sealFor(
        vaultKey: crypto.vaultKeys.create(),
        memberPublicKey: partner.publicKey,
        vaultId: 'v1',
        keyVersion: 1,
      );
      expect(
        () => crypto.vaultKeys.open(
          sealed: sealed,
          identity: me,
          vaultId: 'v1',
          keyVersion: 1,
        ),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('a key from another vault or version is rejected', () {
      final sealed = crypto.vaultKeys.sealFor(
        vaultKey: crypto.vaultKeys.create(),
        memberPublicKey: me.publicKey,
        vaultId: 'v1',
        keyVersion: 1,
      );
      expect(
        () => crypto.vaultKeys.open(
          sealed: sealed,
          identity: me,
          vaultId: 'v2',
          keyVersion: 1,
        ),
        throwsA(isA<TwofoldCryptoException>()),
      );
      expect(
        () => crypto.vaultKeys.open(
          sealed: sealed,
          identity: me,
          vaultId: 'v1',
          keyVersion: 2,
        ),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });
  });

  group('items', () {
    final policy = <String, Object?>{
      'type': 'insurance',
      'title': 'Family health cover',
      'fields': {
        'insurer': 'Example Insurance',
        'policy_no': 'HX-2231',
        'next_due': '2027-03-15',
      },
    };

    EncryptedItem encrypt(dynamic vaultKey, {int version = 1}) =>
        crypto.items.encrypt(
          vaultKey: vaultKey,
          keyVersion: 1,
          vaultId: 'vault-1',
          itemId: 'item-1',
          version: version,
          item: policy,
        );

    test('round-trips through JSON', () {
      final key = crypto.vaultKeys.create();
      final stored = EncryptedItem.fromJson(encrypt(key).toJson());
      expect(crypto.items.decrypt(stored, key), policy);
    });

    test('ciphertext does not contain the plaintext', () {
      final item = encrypt(crypto.vaultKeys.create());
      expect(String.fromCharCodes(item.content).contains('HX-2231'), isFalse);
    });

    test('wrong vault key fails', () {
      final item = encrypt(crypto.vaultKeys.create());
      expect(
        () => crypto.items.decrypt(item, crypto.vaultKeys.create()),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('any flipped byte is rejected', () {
      final key = crypto.vaultKeys.create();
      final item = encrypt(key);
      for (final index in [0, 1, 30, item.content.length - 1]) {
        final tampered = EncryptedItem(
          vaultId: item.vaultId,
          itemId: item.itemId,
          version: item.version,
          keyVersion: item.keyVersion,
          itemKey: item.itemKey,
          content: flipByte(item.content, index),
        );
        expect(
          () => crypto.items.decrypt(tampered, key),
          throwsA(isA<TwofoldCryptoException>()),
        );
      }
    });

    test('content moved to another item id is rejected', () {
      final key = crypto.vaultKeys.create();
      final item = encrypt(key);
      final moved = EncryptedItem(
        vaultId: item.vaultId,
        itemId: 'item-2',
        version: item.version,
        keyVersion: item.keyVersion,
        itemKey: item.itemKey,
        content: item.content,
      );
      expect(
        () => crypto.items.decrypt(moved, key),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('an old version replayed under a newer number is rejected', () {
      final key = crypto.vaultKeys.create();
      final v1 = encrypt(key);
      final replayed = EncryptedItem(
        vaultId: v1.vaultId,
        itemId: v1.itemId,
        version: 2,
        keyVersion: v1.keyVersion,
        itemKey: v1.itemKey,
        content: v1.content,
      );
      expect(
        () => crypto.items.decrypt(replayed, key),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('rewrap moves an item to a new vault key', () {
      final oldKey = crypto.vaultKeys.create();
      final newKey = crypto.vaultKeys.create();
      final rewrapped = crypto.items.rewrap(
        item: encrypt(oldKey),
        oldVaultKey: oldKey,
        newVaultKey: newKey,
        newKeyVersion: 2,
      );
      expect(rewrapped.keyVersion, 2);
      expect(crypto.items.decrypt(rewrapped, newKey), policy);
      expect(
        () => crypto.items.decrypt(rewrapped, oldKey),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });
  });

  group('files', () {
    Uint8List sampleBytes(int length) =>
        Uint8List.fromList(List.generate(length, (i) => (i * 31) & 0xff));

    for (final size in [
      0,
      10,
      FileCipher.chunkSize,
      FileCipher.chunkSize * 3 + 17,
    ]) {
      test('round-trips $size bytes', () async {
        final key = crypto.vaultKeys.create();
        final bytes = sampleBytes(size);
        final encrypted = await crypto.files.encrypt(
          bytes: bytes,
          vaultKey: key,
          vaultId: 'v',
          attachmentId: 'a',
          keyVersion: 1,
        );
        final decrypted = await crypto.files.decrypt(
          file: encrypted,
          vaultKey: key,
          vaultId: 'v',
          attachmentId: 'a',
          keyVersion: 1,
        );
        expect(decrypted, bytes);
      });
    }

    test('a damaged file is rejected', () async {
      final key = crypto.vaultKeys.create();
      final encrypted = await crypto.files.encrypt(
        bytes: sampleBytes(1000),
        vaultKey: key,
        vaultId: 'v',
        attachmentId: 'a',
        keyVersion: 1,
      );
      final damaged = EncryptedFile(
        wrappedKey: encrypted.wrappedKey,
        cipherText: flipByte(
          encrypted.cipherText,
          encrypted.cipherText.length - 5,
        ),
      );
      await expectLater(
        crypto.files.decrypt(
          file: damaged,
          vaultKey: key,
          vaultId: 'v',
          attachmentId: 'a',
          keyVersion: 1,
        ),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('a truncated file is rejected', () async {
      final key = crypto.vaultKeys.create();
      final encrypted = await crypto.files.encrypt(
        bytes: sampleBytes(FileCipher.chunkSize * 2 + 10),
        vaultKey: key,
        vaultId: 'v',
        attachmentId: 'a',
        keyVersion: 1,
      );
      final cut = EncryptedFile(
        wrappedKey: encrypted.wrappedKey,
        cipherText: Uint8List.sublistView(
          encrypted.cipherText,
          0,
          encrypted.cipherText.length - 40,
        ),
      );
      await expectLater(
        crypto.files.decrypt(
          file: cut,
          vaultKey: key,
          vaultId: 'v',
          attachmentId: 'a',
          keyVersion: 1,
        ),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });

    test('a file key bound to another attachment is rejected', () async {
      final key = crypto.vaultKeys.create();
      final encrypted = await crypto.files.encrypt(
        bytes: sampleBytes(10),
        vaultKey: key,
        vaultId: 'v',
        attachmentId: 'a',
        keyVersion: 1,
      );
      await expectLater(
        crypto.files.decrypt(
          file: encrypted,
          vaultKey: key,
          vaultId: 'v',
          attachmentId: 'b',
          keyVersion: 1,
        ),
        throwsA(isA<TwofoldCryptoException>()),
      );
    });
  });

  group('fingerprints', () {
    test('both phones see the same pair number', () {
      final a = crypto.sodium.crypto.box.keyPair().publicKey;
      final b = crypto.sodium.crypto.box.keyPair().publicKey;
      final onA = crypto.fingerprints.forPair(a, b);
      final onB = crypto.fingerprints.forPair(b, a);
      expect(onA, onB);
      expect(onA, hasLength(12));
      expect(onA.every((g) => RegExp(r'^\d{5}$').hasMatch(g)), isTrue);
    });

    test('different keys give different numbers', () {
      final a = crypto.sodium.crypto.box.keyPair().publicKey;
      final b = crypto.sodium.crypto.box.keyPair().publicKey;
      expect(
        crypto.fingerprints.forKey(a),
        isNot(crypto.fingerprints.forKey(b)),
      );
    });
  });
}
