import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'bytes.dart';
import 'errors.dart';

/// Argon2id settings stored next to a vault so they can be raised later
/// without breaking older vaults.
class KdfParams {
  const KdfParams({
    required this.opsLimit,
    required this.memLimit,
    required this.salt,
  });

  /// Default cost: 3 passes over 64 MiB. Takes well under a second on a
  /// mid-range phone while making each password guess expensive.
  static const int defaultOpsLimit = 3;
  static const int defaultMemLimit = 64 * 1024 * 1024;

  final int opsLimit;
  final int memLimit;
  final Uint8List salt;

  Map<String, Object> toJson() => {
    'alg': 'argon2id13',
    'ops': opsLimit,
    'mem': memLimit,
    'salt': toBase64(salt),
  };

  factory KdfParams.fromJson(Map<String, Object?> json) {
    if (json['alg'] != 'argon2id13') {
      throw TwofoldCryptoException(
        'Unsupported key derivation ${json['alg']}.',
      );
    }
    return KdfParams(
      opsLimit: json['ops']! as int,
      memLimit: json['mem']! as int,
      salt: fromBase64(json['salt']! as String),
    );
  }
}

/// Turns the master password into a 32-byte key with Argon2id.
class PasswordKdf {
  PasswordKdf(this._sodium);

  final SodiumSumo _sodium;

  /// New parameters with a fresh random salt.
  KdfParams newParams({
    int opsLimit = KdfParams.defaultOpsLimit,
    int memLimit = KdfParams.defaultMemLimit,
  }) => KdfParams(
    opsLimit: opsLimit,
    memLimit: memLimit,
    salt: _sodium.randombytes.buf(_sodium.crypto.pwhash.saltBytes),
  );

  /// Derives the password key. This is deliberately slow; call it off the
  /// UI thread (for example through `Sodium.runIsolated`).
  SecureKey derive(String password, KdfParams params) {
    if (password.isEmpty) {
      throw const TwofoldCryptoException('Password must not be empty.');
    }
    return _sodium.crypto.pwhash.callStr(
      outLen: _sodium.crypto.aeadXChaCha20Poly1305IETF.keyBytes,
      password: password,
      salt: params.salt,
      opsLimit: params.opsLimit,
      memLimit: params.memLimit,
      alg: CryptoPwhashAlgorithm.argon2id13,
    );
  }
}
