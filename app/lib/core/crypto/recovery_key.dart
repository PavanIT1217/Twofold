import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'bytes.dart';
import 'errors.dart';

/// The 32-byte random key printed on the recovery kit.
///
/// It's shown as Crockford base32 in groups of four characters, with a
/// two-byte checksum so a typo is caught before we try to decrypt anything.
/// Crockford's alphabet has no I, L, O or U, and decoding treats I and L as 1
/// and O as 0, so handwriting mistakes are forgiven.
class RecoveryKey {
  RecoveryKey(this._sodium);

  final SodiumSumo _sodium;

  static const _alphabet = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
  static const _keyBytes = 32;
  static const _checksumBytes = 2;
  static const _groupSize = 4;

  /// Makes a new recovery key.
  SecureKey generate() => _sodium.secureRandom(_keyBytes);

  /// Formats [key] for printing, e.g. `7Q2M-K8ZD-…`.
  String format(SecureKey key) {
    final raw = key.extractBytes();
    try {
      final payload = concatBytes([raw, _checksum(raw)]);
      final encoded = _encode(payload);
      wipe(payload);
      final groups = <String>[];
      for (var i = 0; i < encoded.length; i += _groupSize) {
        final end = i + _groupSize;
        groups.add(
          encoded.substring(i, end > encoded.length ? encoded.length : end),
        );
      }
      return groups.join('-');
    } finally {
      wipe(raw);
    }
  }

  /// Reads a typed or scanned recovery key. Spaces, dashes and case are
  /// ignored.
  SecureKey parse(String text) {
    final cleaned = text
        .toUpperCase()
        .replaceAll(RegExp(r'[\s-]'), '')
        .replaceAll(RegExp('[IL]'), '1')
        .replaceAll('O', '0');
    final payload = _decode(cleaned);
    if (payload == null || payload.length != _keyBytes + _checksumBytes) {
      throw const TwofoldCryptoException(
        'That recovery key is not the right length.',
      );
    }
    final raw = Uint8List.sublistView(payload, 0, _keyBytes);
    final checksum = Uint8List.sublistView(payload, _keyBytes);
    try {
      if (!bytesEqual(checksum, _checksum(raw))) {
        throw const TwofoldCryptoException(
          'That recovery key has a typo. Check each group again.',
        );
      }
      return _sodium.secureCopy(raw);
    } finally {
      wipe(payload);
    }
  }

  Uint8List _checksum(Uint8List raw) => _sodium.crypto
      .genericHash(
        message: concatBytes([utf8Bytes('twofold/v1/recovery-checksum'), raw]),
        outLen: 16,
      )
      .sublist(0, _checksumBytes);

  static String _encode(Uint8List bytes) {
    final out = StringBuffer();
    var buffer = 0;
    var bits = 0;
    for (final byte in bytes) {
      buffer = (buffer << 8) | byte;
      bits += 8;
      while (bits >= 5) {
        bits -= 5;
        out.write(_alphabet[(buffer >> bits) & 31]);
      }
      buffer &= (1 << bits) - 1;
    }
    if (bits > 0) {
      out.write(_alphabet[(buffer << (5 - bits)) & 31]);
    }
    return out.toString();
  }

  static Uint8List? _decode(String text) {
    final out = BytesBuilder();
    var buffer = 0;
    var bits = 0;
    for (final char in text.split('')) {
      final value = _alphabet.indexOf(char);
      if (value < 0) return null;
      buffer = (buffer << 5) | value;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.addByte((buffer >> bits) & 0xff);
      }
      buffer &= (1 << bits) - 1;
    }
    // Leftover bits are padding from encoding and must be zero.
    if (buffer != 0) return null;
    return out.takeBytes();
  }
}
