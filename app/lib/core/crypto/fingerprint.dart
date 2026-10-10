import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'bytes.dart';

/// Short, human-comparable numbers derived from public keys, shown during
/// pairing so two people can confirm on screen that they hold each other's
/// real keys.
class Fingerprints {
  Fingerprints(this._sodium);

  final SodiumSumo _sodium;

  static const _groupsPerKey = 6;

  /// Six groups of five digits for one public key.
  List<String> forKey(Uint8List publicKey) {
    final hash = _sodium.crypto.genericHash(
      message: concatBytes([utf8Bytes('twofold/v1/fingerprint|'), publicKey]),
      outLen: 32,
    );
    return [
      for (var g = 0; g < _groupsPerKey; g++)
        _fiveDigits(Uint8List.sublistView(hash, g * 5, g * 5 + 5)),
    ];
  }

  /// The pair number both phones show: twelve groups, the same on each side
  /// because the two keys are put in a fixed order first.
  List<String> forPair(Uint8List publicKeyA, Uint8List publicKeyB) {
    final aFirst = _compare(publicKeyA, publicKeyB) <= 0;
    final first = aFirst ? publicKeyA : publicKeyB;
    final second = aFirst ? publicKeyB : publicKeyA;
    return [...forKey(first), ...forKey(second)];
  }

  static String _fiveDigits(Uint8List fiveBytes) {
    var value = 0;
    for (final byte in fiveBytes) {
      value = (value << 8) | byte;
    }
    return (value % 100000).toString().padLeft(5, '0');
  }

  static int _compare(Uint8List a, Uint8List b) {
    for (var i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i] - b[i];
    }
    return a.length - b.length;
  }
}
