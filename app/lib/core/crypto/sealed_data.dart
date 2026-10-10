import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'bytes.dart';
import 'errors.dart';

/// Format version written as the first byte of every [SealedData] blob.
const int sealedDataVersion = 1;

/// Encrypts small values (keys, item JSON) with XChaCha20-Poly1305.
///
/// Blob layout: `[version:1][nonce:24][ciphertext + tag]`.
///
/// Every call takes a [context] string that is fed in as additional
/// authenticated data. It names what the blob is and what it belongs to
/// (for example `item|<vaultId>|<itemId>|3`), so a blob copied from one place
/// to another fails to decrypt instead of being silently accepted.
class SealedData {
  SealedData(this._sodium);

  final SodiumSumo _sodium;

  Aead get _aead => _sodium.crypto.aeadXChaCha20Poly1305IETF;

  /// Size of a symmetric key in bytes (32).
  int get keyBytes => _aead.keyBytes;

  /// Makes a new random symmetric key.
  SecureKey newKey() => _aead.keygen();

  Uint8List seal({
    required SecureKey key,
    required Uint8List plaintext,
    required String context,
  }) {
    final nonce = _sodium.randombytes.buf(_aead.nonceBytes);
    final cipherText = _aead.encrypt(
      message: plaintext,
      nonce: nonce,
      key: key,
      additionalData: _ad(context),
    );
    return concatBytes([
      [sealedDataVersion],
      nonce,
      cipherText,
    ]);
  }

  Uint8List open({
    required SecureKey key,
    required Uint8List blob,
    required String context,
  }) {
    final nonceBytes = _aead.nonceBytes;
    if (blob.length < 1 + nonceBytes + _aead.aBytes) {
      throw const TwofoldCryptoException('Data is too short to be valid.');
    }
    if (blob[0] != sealedDataVersion) {
      throw TwofoldCryptoException('Unsupported data version ${blob[0]}.');
    }
    final nonce = Uint8List.sublistView(blob, 1, 1 + nonceBytes);
    final cipherText = Uint8List.sublistView(blob, 1 + nonceBytes);
    try {
      return _aead.decrypt(
        cipherText: cipherText,
        nonce: nonce,
        key: key,
        additionalData: _ad(context),
      );
    } on SodiumException {
      throw const TwofoldCryptoException(
        'Could not decrypt: wrong key or damaged data.',
      );
    }
  }

  /// Encrypts one key with another.
  Uint8List wrapKey({
    required SecureKey wrappingKey,
    required SecureKey key,
    required String context,
  }) {
    final raw = key.extractBytes();
    try {
      return seal(key: wrappingKey, plaintext: raw, context: context);
    } finally {
      wipe(raw);
    }
  }

  /// Reverses [wrapKey].
  SecureKey unwrapKey({
    required SecureKey wrappingKey,
    required Uint8List blob,
    required String context,
  }) {
    final raw = open(key: wrappingKey, blob: blob, context: context);
    try {
      return _sodium.secureCopy(raw);
    } finally {
      wipe(raw);
    }
  }

  static Uint8List _ad(String context) => utf8Bytes('twofold/v1/$context');
}
