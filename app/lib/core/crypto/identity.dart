import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'bytes.dart';
import 'errors.dart';
import 'password_kdf.dart';
import 'sealed_data.dart';

/// A member's X25519 key pair, unlocked and ready to use.
class Identity {
  Identity({required this.publicKey, required this.secretKey});

  final Uint8List publicKey;
  final SecureKey secretKey;

  void dispose() => secretKey.dispose();
}

/// The form an [Identity] is saved in: the secret key encrypted twice, once
/// with the master password and once with the recovery key. Safe to write to
/// disk and to the personal cloud backup.
class LockedIdentity {
  const LockedIdentity({
    required this.publicKey,
    required this.kdf,
    required this.byPassword,
    required this.byRecoveryKey,
  });

  final Uint8List publicKey;
  final KdfParams kdf;
  final Uint8List byPassword;
  final Uint8List byRecoveryKey;

  Map<String, Object> toJson() => {
    'v': 1,
    'pk': toBase64(publicKey),
    'kdf': kdf.toJson(),
    'byPassword': toBase64(byPassword),
    'byRecoveryKey': toBase64(byRecoveryKey),
  };

  factory LockedIdentity.fromJson(Map<String, Object?> json) {
    if (json['v'] != 1) {
      throw TwofoldCryptoException(
        'Unsupported identity version ${json['v']}.',
      );
    }
    return LockedIdentity(
      publicKey: fromBase64(json['pk']! as String),
      kdf: KdfParams.fromJson((json['kdf']! as Map).cast<String, Object?>()),
      byPassword: fromBase64(json['byPassword']! as String),
      byRecoveryKey: fromBase64(json['byRecoveryKey']! as String),
    );
  }
}

/// Creates, locks and unlocks a member's identity.
class Identities {
  Identities(this._sodium, this._sealed, this._kdf);

  final SodiumSumo _sodium;
  final SealedData _sealed;
  final PasswordKdf _kdf;

  static const _context = 'identity-secret-key';

  /// Makes a new key pair and locks it with [password] and [recoveryKey].
  ({Identity identity, LockedIdentity locked}) create({
    required String password,
    required SecureKey recoveryKey,
    KdfParams? kdfParams,
  }) {
    final keyPair = _sodium.crypto.box.keyPair();
    final identity = Identity(
      publicKey: keyPair.publicKey,
      secretKey: keyPair.secretKey,
    );
    final locked = lock(
      identity,
      password: password,
      recoveryKey: recoveryKey,
      kdfParams: kdfParams ?? _kdf.newParams(),
    );
    return (identity: identity, locked: locked);
  }

  /// Locks [identity]. Also used to change the master password: pass a new
  /// password and fresh [kdfParams].
  LockedIdentity lock(
    Identity identity, {
    required String password,
    required SecureKey recoveryKey,
    required KdfParams kdfParams,
  }) {
    final passwordKey = _kdf.derive(password, kdfParams);
    try {
      return LockedIdentity(
        publicKey: identity.publicKey,
        kdf: kdfParams,
        byPassword: _sealed.wrapKey(
          wrappingKey: passwordKey,
          key: identity.secretKey,
          context: '$_context|password',
        ),
        byRecoveryKey: _sealed.wrapKey(
          wrappingKey: recoveryKey,
          key: identity.secretKey,
          context: '$_context|recovery',
        ),
      );
    } finally {
      passwordKey.dispose();
    }
  }

  /// Locks [identity] with a new master password, keeping the existing
  /// recovery key.
  LockedIdentity changePassword(
    LockedIdentity locked,
    Identity identity, {
    required String newPassword,
    KdfParams? kdfParams,
  }) {
    final params = kdfParams ?? _kdf.newParams();
    final passwordKey = _kdf.derive(newPassword, params);
    try {
      return LockedIdentity(
        publicKey: locked.publicKey,
        kdf: params,
        byPassword: _sealed.wrapKey(
          wrappingKey: passwordKey,
          key: identity.secretKey,
          context: '$_context|password',
        ),
        byRecoveryKey: locked.byRecoveryKey,
      );
    } finally {
      passwordKey.dispose();
    }
  }

  /// Locks [identity] with a new recovery key, keeping the master password.
  /// The old recovery kit stops working.
  LockedIdentity replaceRecoveryKey(
    LockedIdentity locked,
    Identity identity,
    SecureKey newRecoveryKey,
  ) => LockedIdentity(
    publicKey: locked.publicKey,
    kdf: locked.kdf,
    byPassword: locked.byPassword,
    byRecoveryKey: _sealed.wrapKey(
      wrappingKey: newRecoveryKey,
      key: identity.secretKey,
      context: '$_context|recovery',
    ),
  );

  /// Rebuilds an identity from a secret key released by biometrics, checking
  /// it against the stored public key.
  Identity fromSecretKey(LockedIdentity locked, Uint8List secretKey) {
    final key = _sodium.secureCopy(secretKey);
    final derivedPublic = _sodium.crypto.scalarmult.base(n: key);
    if (!bytesEqual(derivedPublic, locked.publicKey)) {
      key.dispose();
      throw const TwofoldCryptoException('Stored key does not match.');
    }
    return Identity(publicKey: locked.publicKey, secretKey: key);
  }

  /// Unlocks with the master password.
  Identity unlockWithPassword(LockedIdentity locked, String password) {
    final passwordKey = _kdf.derive(password, locked.kdf);
    try {
      return _unlock(locked, passwordKey, locked.byPassword, 'password');
    } on TwofoldCryptoException {
      throw const TwofoldCryptoException('Wrong master password.');
    } finally {
      passwordKey.dispose();
    }
  }

  /// Unlocks with the recovery key from the printed kit.
  Identity unlockWithRecoveryKey(LockedIdentity locked, SecureKey recoveryKey) {
    try {
      return _unlock(locked, recoveryKey, locked.byRecoveryKey, 'recovery');
    } on TwofoldCryptoException {
      throw const TwofoldCryptoException('That recovery key does not match.');
    }
  }

  Identity _unlock(
    LockedIdentity locked,
    SecureKey wrappingKey,
    Uint8List blob,
    String kind,
  ) {
    final secretKey = _sealed.unwrapKey(
      wrappingKey: wrappingKey,
      blob: blob,
      context: '$_context|$kind',
    );
    // Check the secret key really belongs to the stored public key, so a
    // swapped public key in a damaged file can't go unnoticed.
    final derivedPublic = _sodium.crypto.scalarmult.base(n: secretKey);
    if (!bytesEqual(derivedPublic, locked.publicKey)) {
      secretKey.dispose();
      throw const TwofoldCryptoException('Identity file is damaged.');
    }
    return Identity(publicKey: locked.publicKey, secretKey: secretKey);
  }
}
