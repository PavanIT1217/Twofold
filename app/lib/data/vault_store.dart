import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/crypto/twofold_crypto.dart';
import 'keyring.dart';

/// This phone's own identity: its member id, display name and the locked
/// key pair.
class IdentityRecord {
  const IdentityRecord({
    required this.memberId,
    required this.name,
    required this.locked,
  });

  factory IdentityRecord.fromJson(Map<String, Object?> json) => IdentityRecord(
    memberId: json['memberId']! as String,
    name: json['name']! as String,
    locked: LockedIdentity.fromJson(
      (json['locked']! as Map).cast<String, Object?>(),
    ),
  );

  final String memberId;
  final String name;
  final LockedIdentity locked;

  IdentityRecord withLocked(LockedIdentity locked) =>
      IdentityRecord(memberId: memberId, name: name, locked: locked);

  Map<String, Object?> toJson() => {
    'memberId': memberId,
    'name': name,
    'locked': locked.toJson(),
  };
}

/// Everything Twofold keeps on disk. Only encrypted data and harmless
/// settings are ever written here.
///
/// ```text
/// <root>/identity.json      locked key pair
/// <root>/settings.json      auto-lock, backup and other preferences
/// <root>/trusted.json       peers scanned while pairing
/// <root>/vault/keyring.json sealed vault keys
/// <root>/vault/items/*.json encrypted items
/// <root>/vault/files/*.bin  encrypted attachments
/// ```
class VaultStore {
  VaultStore(this.root);

  final Directory root;

  File get _identity => File(p.join(root.path, 'identity.json'));
  File get _settings => File(p.join(root.path, 'settings.json'));
  File get _trusted => File(p.join(root.path, 'trusted.json'));
  File get _keyring => File(p.join(root.path, 'vault', 'keyring.json'));
  Directory get _items => Directory(p.join(root.path, 'vault', 'items'));
  Directory get _files => Directory(p.join(root.path, 'vault', 'files'));

  Future<IdentityRecord?> readIdentity() async {
    final json = await _readJson(_identity);
    return json == null ? null : IdentityRecord.fromJson(json);
  }

  Future<void> writeIdentity(IdentityRecord record) =>
      _writeJson(_identity, record.toJson());

  Future<Map<String, Object?>> readSettings() async =>
      await _readJson(_settings) ?? {};

  Future<void> writeSettings(Map<String, Object?> settings) =>
      _writeJson(_settings, settings);

  /// Public keys of peers scanned during pairing, by member id.
  Future<Map<String, String>> readTrusted() async =>
      (await _readJson(_trusted) ?? {}).cast<String, String>();

  Future<void> writeTrusted(Map<String, String> trusted) =>
      _writeJson(_trusted, trusted);

  Future<Keyring?> readKeyring() async {
    final json = await _readJson(_keyring);
    return json == null ? null : Keyring.fromJson(json);
  }

  Future<void> writeKeyring(Keyring keyring) =>
      _writeJson(_keyring, keyring.toJson());

  Future<List<EncryptedItem>> readItems() async {
    if (!await _items.exists()) return [];
    final out = <EncryptedItem>[];
    await for (final entity in _items.list()) {
      if (entity is File && entity.path.endsWith('.json')) {
        final json = await _readJson(entity);
        if (json != null) out.add(EncryptedItem.fromJson(json));
      }
    }
    return out;
  }

  Future<void> writeItem(EncryptedItem item) => _writeJson(
    File(p.join(_items.path, '${_safe(item.itemId)}.json')),
    item.toJson(),
  );

  Future<Set<String>> listFiles() async {
    if (!await _files.exists()) return {};
    return {
      await for (final entity in _files.list())
        if (entity is File && entity.path.endsWith('.bin'))
          p.basenameWithoutExtension(entity.path),
    };
  }

  Future<Uint8List?> readFile(String id) async {
    final file = File(p.join(_files.path, '${_safe(id)}.bin'));
    return await file.exists() ? file.readAsBytes() : null;
  }

  Future<void> writeFile(String id, Uint8List cipherText) =>
      _writeAtomic(File(p.join(_files.path, '${_safe(id)}.bin')), cipherText);

  Future<void> deleteFile(String id) async {
    final file = File(p.join(_files.path, '${_safe(id)}.bin'));
    if (await file.exists()) await file.delete();
  }

  /// Removes the vault (keeps the identity and settings).
  Future<void> deleteVault() async {
    final dir = Directory(p.join(root.path, 'vault'));
    if (await dir.exists()) await dir.delete(recursive: true);
  }

  /// Removes everything Twofold stored on this phone.
  Future<void> deleteAll() async {
    if (await root.exists()) await root.delete(recursive: true);
  }

  static String _safe(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(id)) {
      throw ArgumentError('Invalid id: $id');
    }
    return id;
  }

  static Future<Map<String, Object?>?> _readJson(File file) async {
    if (!await file.exists()) return null;
    return (jsonDecode(await file.readAsString()) as Map)
        .cast<String, Object?>();
  }

  static Future<void> _writeJson(File file, Map<String, Object?> json) =>
      _writeAtomic(file, utf8.encode(jsonEncode(json)));

  /// Writes to a temporary file first, so a crash never leaves half a file.
  static Future<void> _writeAtomic(File file, List<int> bytes) async {
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }
}
