import 'dart:convert';
import 'dart:typed_data';

import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;

import 'backup_bundle.dart';

/// Thrown when Google Drive can't be reached or the user cancels sign-in.
class DriveBackupException implements Exception {
  const DriveBackupException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Saves the encrypted backup in the hidden app-data folder of the user's
/// own Google Drive. Only Twofold can see that folder, and Twofold asks for
/// access to nothing else in the Drive.
class DriveBackup {
  DriveBackup({http.Client? client}) : _client = client ?? http.Client();

  static const _scopes = ['https://www.googleapis.com/auth/drive.appdata'];
  static const _api = 'https://www.googleapis.com/drive/v3/files';
  static const _upload = 'https://www.googleapis.com/upload/drive/v3/files';

  /// The Google OAuth "web" client id, passed at build time with
  /// `--dart-define=GOOGLE_SERVER_CLIENT_ID=...`. Android needs it to issue
  /// tokens; see the README.
  static const _serverClientId = String.fromEnvironment(
    'GOOGLE_SERVER_CLIENT_ID',
  );

  final http.Client _client;
  bool _initialized = false;

  Future<Map<String, String>> _headers({required bool interactive}) async {
    try {
      if (!_initialized) {
        await GoogleSignIn.instance.initialize(
          serverClientId: _serverClientId.isEmpty ? null : _serverClientId,
        );
        _initialized = true;
      }
      final headers = await GoogleSignIn.instance.authorizationClient
          .authorizationHeaders(_scopes, promptIfNecessary: interactive);
      if (headers == null) {
        throw const DriveBackupException('Sign in to Google Drive to back up.');
      }
      return headers;
    } on GoogleSignInException catch (e) {
      throw DriveBackupException(
        e.code == GoogleSignInExceptionCode.canceled
            ? 'Google sign-in was cancelled.'
            : 'Google sign-in failed: ${e.description ?? e.code.name}',
      );
    }
  }

  /// Asks the user to allow Drive backups (shows Google's sign-in).
  Future<void> connect() => _headers(interactive: true);

  Future<String?> _findFileId(Map<String, String> headers) async {
    final uri = Uri.parse(_api).replace(
      queryParameters: {
        'spaces': 'appDataFolder',
        'q': "name = '${BackupBundle.fileName}' and trashed = false",
        'fields': 'files(id, modifiedTime)',
        'orderBy': 'modifiedTime desc',
      },
    );
    final response = await _client.get(uri, headers: headers);
    _check(response);
    final files = (jsonDecode(response.body) as Map)['files'] as List;
    return files.isEmpty ? null : (files.first as Map)['id'] as String;
  }

  /// Uploads the backup, replacing the previous one.
  Future<void> upload(Uint8List bytes, {bool interactive = false}) async {
    final headers = await _headers(interactive: interactive);
    final existing = await _findFileId(headers);
    if (existing != null) {
      final response = await _client.patch(
        Uri.parse('$_upload/$existing?uploadType=media'),
        headers: {...headers, 'Content-Type': 'application/json'},
        body: bytes,
      );
      _check(response);
      return;
    }
    const boundary = 'twofold-backup-boundary';
    final metadata = jsonEncode({
      'name': BackupBundle.fileName,
      'parents': ['appDataFolder'],
      'mimeType': 'application/json',
    });
    final body = BytesBuilder()
      ..add(
        utf8.encode(
          '--$boundary\r\nContent-Type: application/json; charset=UTF-8\r\n\r\n$metadata\r\n',
        ),
      )
      ..add(
        utf8.encode('--$boundary\r\nContent-Type: application/json\r\n\r\n'),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));
    final response = await _client.post(
      Uri.parse('$_upload?uploadType=multipart'),
      headers: {
        ...headers,
        'Content-Type': 'multipart/related; boundary=$boundary',
      },
      body: body.takeBytes(),
    );
    _check(response);
  }

  /// Downloads the latest backup, or null if there isn't one.
  Future<Uint8List?> download() async {
    final headers = await _headers(interactive: true);
    final id = await _findFileId(headers);
    if (id == null) return null;
    final response = await _client.get(
      Uri.parse('$_api/$id?alt=media'),
      headers: headers,
    );
    _check(response);
    return response.bodyBytes;
  }

  Future<void> disconnect() async {
    try {
      await GoogleSignIn.instance.disconnect();
    } on Object {
      // Already signed out.
    }
  }

  static void _check(http.Response response) {
    if (response.statusCode >= 300) {
      throw DriveBackupException(
        'Google Drive returned an error (${response.statusCode}).',
      );
    }
  }
}
