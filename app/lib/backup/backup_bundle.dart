import 'dart:convert';
import 'dart:typed_data';

import '../core/crypto/twofold_crypto.dart';
import '../data/keyring.dart';
import '../data/vault.dart';
import '../data/vault_store.dart';

/// A single file holding everything needed to set this phone's vault up
/// again: the locked identity, the keyring, every encrypted record and every
/// encrypted attachment. Nothing in it is readable without the master
/// password or the recovery key.
class BackupBundle {
  const BackupBundle({
    required this.createdAt,
    required this.identity,
    required this.keyring,
    required this.records,
    required this.files,
  });

  static const format = 'twofold-backup';
  static const fileName = 'twofold-backup.json';

  final DateTime createdAt;
  final IdentityRecord identity;
  final Keyring keyring;
  final List<EncryptedItem> records;
  final Map<String, Uint8List> files;

  /// Collects a backup of the open [vault].
  static Future<BackupBundle> collect(Vault vault, VaultStore store) async {
    final identity = await store.readIdentity();
    if (identity == null) throw StateError('No identity on this phone.');
    final files = <String, Uint8List>{};
    for (final id in vault.referencedFiles) {
      final data = await store.readFile(id);
      if (data != null) files[id] = data;
    }
    return BackupBundle(
      createdAt: DateTime.now(),
      identity: identity,
      keyring: vault.keyring,
      records: [for (final id in vault.manifest().keys) vault.export(id)],
      files: files,
    );
  }

  Uint8List encode() => utf8.encode(
    jsonEncode({
      'format': format,
      'v': 1,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'identity': identity.toJson(),
      'keyring': keyring.toJson(),
      'records': [for (final r in records) r.toJson()],
      'files': {for (final e in files.entries) e.key: base64.encode(e.value)},
    }),
  );

  static BackupBundle decode(List<int> bytes) {
    final Map<String, Object?> json;
    try {
      json = (jsonDecode(utf8.decode(bytes)) as Map).cast<String, Object?>();
    } on FormatException {
      throw const TwofoldCryptoException('This is not a Twofold backup file.');
    }
    if (json['format'] != format) {
      throw const TwofoldCryptoException('This is not a Twofold backup file.');
    }
    if (json['v'] != 1) {
      throw const TwofoldCryptoException(
        'This backup is from a newer version of Twofold.',
      );
    }
    return BackupBundle(
      createdAt: DateTime.parse(json['createdAt']! as String).toLocal(),
      identity: IdentityRecord.fromJson(
        (json['identity']! as Map).cast<String, Object?>(),
      ),
      keyring: Keyring.fromJson(
        (json['keyring']! as Map).cast<String, Object?>(),
      ),
      records: [
        for (final r in json['records']! as List)
          EncryptedItem.fromJson((r as Map).cast<String, Object?>()),
      ],
      files: {
        for (final e in (json['files']! as Map).entries)
          e.key as String: base64.decode(e.value as String),
      },
    );
  }

  /// Writes the backup into an empty store, ready to be unlocked.
  Future<void> restoreInto(VaultStore store) async {
    await store.deleteVault();
    await store.writeIdentity(identity);
    await store.writeKeyring(keyring);
    for (final r in records) {
      if (r.vaultId == keyring.vaultId) await store.writeItem(r);
    }
    for (final e in files.entries) {
      await store.writeFile(e.key, e.value);
    }
  }
}
