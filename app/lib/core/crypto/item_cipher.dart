import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'bytes.dart';
import 'errors.dart';
import 'sealed_data.dart';

/// One vault item as it is stored and synced: everything readable (type,
/// title, fields, dates, notes) is inside [content].
class EncryptedItem {
  const EncryptedItem({
    required this.vaultId,
    required this.itemId,
    required this.version,
    required this.keyVersion,
    required this.itemKey,
    required this.content,
  });

  final String vaultId;
  final String itemId;

  /// Goes up by one on every edit. Bound into the encryption, so an old
  /// version can't be replayed under a newer version number.
  final int version;

  /// Which vault key [itemKey] is wrapped with.
  final int keyVersion;

  /// This item's own key, wrapped with the vault key.
  final Uint8List itemKey;

  /// The item JSON, encrypted with the item key.
  final Uint8List content;

  Map<String, Object> toJson() => {
    'v': 1,
    'vault': vaultId,
    'id': itemId,
    'ver': version,
    'kv': keyVersion,
    'key': toBase64(itemKey),
    'data': toBase64(content),
  };

  factory EncryptedItem.fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw TwofoldCryptoException('Unsupported item version ${json['v']}.');
    }
    return EncryptedItem(
      vaultId: json['vault']! as String,
      itemId: json['id']! as String,
      version: json['ver']! as int,
      keyVersion: json['kv']! as int,
      itemKey: fromBase64(json['key']! as String),
      content: fromBase64(json['data']! as String),
    );
  }
}

/// Encrypts and decrypts vault items.
class ItemCipher {
  ItemCipher(this._sealed);

  final SealedData _sealed;

  EncryptedItem encrypt({
    required SecureKey vaultKey,
    required int keyVersion,
    required String vaultId,
    required String itemId,
    required int version,
    required Map<String, Object?> item,
  }) {
    final itemKey = _sealed.newKey();
    final plaintext = utf8Bytes(jsonEncode(item));
    try {
      return EncryptedItem(
        vaultId: vaultId,
        itemId: itemId,
        version: version,
        keyVersion: keyVersion,
        itemKey: _sealed.wrapKey(
          wrappingKey: vaultKey,
          key: itemKey,
          context: _keyContext(vaultId, itemId, keyVersion),
        ),
        content: _sealed.seal(
          key: itemKey,
          plaintext: plaintext,
          context: _contentContext(vaultId, itemId, version),
        ),
      );
    } finally {
      itemKey.dispose();
      wipe(plaintext);
    }
  }

  Map<String, Object?> decrypt(EncryptedItem item, SecureKey vaultKey) {
    final itemKey = _sealed.unwrapKey(
      wrappingKey: vaultKey,
      blob: item.itemKey,
      context: _keyContext(item.vaultId, item.itemId, item.keyVersion),
    );
    try {
      final plaintext = _sealed.open(
        key: itemKey,
        blob: item.content,
        context: _contentContext(item.vaultId, item.itemId, item.version),
      );
      try {
        return (jsonDecode(utf8.decode(plaintext)) as Map)
            .cast<String, Object?>();
      } finally {
        wipe(plaintext);
      }
    } finally {
      itemKey.dispose();
    }
  }

  /// Moves an item to a new vault key (after a member is removed) without
  /// touching its content: only the small item key is re-wrapped.
  EncryptedItem rewrap({
    required EncryptedItem item,
    required SecureKey oldVaultKey,
    required SecureKey newVaultKey,
    required int newKeyVersion,
  }) {
    final itemKey = _sealed.unwrapKey(
      wrappingKey: oldVaultKey,
      blob: item.itemKey,
      context: _keyContext(item.vaultId, item.itemId, item.keyVersion),
    );
    try {
      return EncryptedItem(
        vaultId: item.vaultId,
        itemId: item.itemId,
        version: item.version,
        keyVersion: newKeyVersion,
        itemKey: _sealed.wrapKey(
          wrappingKey: newVaultKey,
          key: itemKey,
          context: _keyContext(item.vaultId, item.itemId, newKeyVersion),
        ),
        content: item.content,
      );
    } finally {
      itemKey.dispose();
    }
  }

  static String _keyContext(String vaultId, String itemId, int keyVersion) =>
      'item-key|$vaultId|$itemId|$keyVersion';

  static String _contentContext(String vaultId, String itemId, int version) =>
      'item|$vaultId|$itemId|$version';
}
