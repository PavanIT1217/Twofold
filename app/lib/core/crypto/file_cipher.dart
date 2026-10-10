import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import 'errors.dart';
import 'sealed_data.dart';

/// An encrypted attachment: the file bytes and its own key, wrapped with the
/// vault key.
class EncryptedFile {
  const EncryptedFile({required this.wrappedKey, required this.cipherText});

  final Uint8List wrappedKey;
  final Uint8List cipherText;
}

/// Encrypts attachments (scans, PDFs, photos) with libsodium secretstream,
/// in 64 KiB chunks. The stream marks its last chunk, so a truncated file is
/// rejected rather than opened partially.
class FileCipher {
  FileCipher(this._sodium, this._sealed);

  final SodiumSumo _sodium;
  final SealedData _sealed;

  static const chunkSize = 64 * 1024;

  Future<EncryptedFile> encrypt({
    required Uint8List bytes,
    required SecureKey vaultKey,
    required String vaultId,
    required String attachmentId,
    required int keyVersion,
  }) async {
    final fileKey = _sodium.crypto.secretStream.keygen();
    try {
      final cipherText = await _collect(
        _sodium.crypto.secretStream.pushChunked(
          messageStream: Stream.value(bytes),
          key: fileKey,
          chunkSize: chunkSize,
        ),
      );
      return EncryptedFile(
        wrappedKey: _sealed.wrapKey(
          wrappingKey: vaultKey,
          key: fileKey,
          context: _context(vaultId, attachmentId, keyVersion),
        ),
        cipherText: cipherText,
      );
    } finally {
      fileKey.dispose();
    }
  }

  Future<Uint8List> decrypt({
    required EncryptedFile file,
    required SecureKey vaultKey,
    required String vaultId,
    required String attachmentId,
    required int keyVersion,
  }) async {
    final fileKey = _sealed.unwrapKey(
      wrappingKey: vaultKey,
      blob: file.wrappedKey,
      context: _context(vaultId, attachmentId, keyVersion),
    );
    try {
      return await _collect(
        _sodium.crypto.secretStream.pullChunked(
          cipherStream: Stream.value(file.cipherText),
          key: fileKey,
          chunkSize: chunkSize,
        ),
      );
    } on SodiumException {
      throw const TwofoldCryptoException('This file is damaged.');
    } on StateError {
      // Raised by secretstream when the final chunk is missing.
      throw const TwofoldCryptoException('This file is incomplete.');
    } finally {
      fileKey.dispose();
    }
  }

  static Future<Uint8List> _collect(Stream<List<int>> stream) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  static String _context(String vaultId, String attachmentId, int keyVersion) =>
      'file-key|$vaultId|$attachmentId|$keyVersion';
}
