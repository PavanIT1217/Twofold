import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../core/crypto/bytes.dart';

/// Keeps this phone's identity secret key in the phone's secure hardware
/// (Android Keystore / iOS Keychain), released only after a fingerprint or
/// face check. Enrolling a new fingerprint invalidates it, and the master
/// password is needed again.
class BiometricUnlock {
  static const _key = 'twofold_identity_key';

  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions.biometric(
      enforceBiometrics: true,
      requireBiometricsPerOperation: true,
      biometricType: AndroidBiometricType.strongBiometricOnly,
      biometricPromptTitle: 'Unlock Twofold',
      biometricPromptNegativeButton: 'Use master password',
    ),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.unlocked_this_device,
      accessControlFlags: [AccessControlFlag.biometryCurrentSet],
    ),
  );

  Future<bool> get available async {
    try {
      final auth = LocalAuthentication();
      return await auth.isDeviceSupported() && await auth.canCheckBiometrics;
    } on Object {
      return false;
    }
  }

  /// Stores the secret key behind biometrics.
  Future<void> enable(List<int> secretKey) =>
      _storage.write(key: _key, value: toBase64(Uint8List.fromList(secretKey)));

  /// Returns the secret key after a successful check, or null if the user
  /// cancelled, biometrics changed, or nothing is stored.
  Future<Uint8List?> read() async {
    try {
      final value = await _storage.read(key: _key);
      return value == null ? null : fromBase64(value);
    } on Object {
      return null;
    }
  }

  Future<void> disable() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      // Nothing stored.
    }
  }
}
