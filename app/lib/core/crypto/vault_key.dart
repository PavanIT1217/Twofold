import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'bytes.dart';
import 'errors.dart';
import 'identity.dart';
import 'sealed_data.dart';

/// The shared key of one vault, sealed separately for each member.
///
/// A sealed copy is `crypto_box_seal` of `label || key`, where the label names
/// the vault and key version. Opening checks the label, so a sealed key from
/// another vault (or an old key version) can't be passed off as this one.
class VaultKeys {
  VaultKeys(this._sodium, this._sealed);

  final SodiumSumo _sodium;
  final SealedData _sealed;

  /// Makes a new random vault key.
  SecureKey create() => _sealed.newKey();

  /// Seals [vaultKey] so only the owner of [memberPublicKey] can open it.
  Uint8List sealFor({
    required SecureKey vaultKey,
    required Uint8List memberPublicKey,
    required String vaultId,
    required int keyVersion,
  }) {
    final raw = vaultKey.extractBytes();
    final message = concatBytes([_label(vaultId, keyVersion), raw]);
    try {
      return _sodium.crypto.box.seal(
        message: message,
        publicKey: memberPublicKey,
      );
    } finally {
      wipe(raw);
      wipe(message);
    }
  }

  /// Opens a sealed vault key with the member's own [identity].
  SecureKey open({
    required Uint8List sealed,
    required Identity identity,
    required String vaultId,
    required int keyVersion,
  }) {
    final Uint8List message;
    try {
      message = _sodium.crypto.box.sealOpen(
        cipherText: sealed,
        publicKey: identity.publicKey,
        secretKey: identity.secretKey,
      );
    } on SodiumException {
      throw const TwofoldCryptoException(
        'This vault key was not sealed for you.',
      );
    }
    try {
      final label = _label(vaultId, keyVersion);
      if (message.length != label.length + _sealed.keyBytes ||
          !bytesEqual(Uint8List.sublistView(message, 0, label.length), label)) {
        throw const TwofoldCryptoException(
          'This vault key belongs to a different vault or version.',
        );
      }
      return _sodium.secureCopy(Uint8List.sublistView(message, label.length));
    } finally {
      wipe(message);
    }
  }

  static Uint8List _label(String vaultId, int keyVersion) =>
      utf8Bytes('twofold/v1/vault-key|$vaultId|$keyVersion|');
}
