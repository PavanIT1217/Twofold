import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../core/crypto/bytes.dart';

/// What a phone shows as a QR code while pairing: who it is, its public
/// key, and where on the Wi-Fi it can be reached.
class PairingCode {
  const PairingCode({
    required this.memberId,
    required this.name,
    required this.publicKey,
    this.addresses = const [],
    this.port,
    this.vaultName,
  });

  static const _prefix = 'twofold:pair:1:';

  final String memberId;
  final String name;
  final Uint8List publicKey;
  final List<String> addresses;
  final int? port;

  /// Set when the phone already has a vault (the one others will join).
  final String? vaultName;

  String encode() =>
      _prefix +
      toBase64(
        utf8Bytes(
          jsonEncode({
            'id': memberId,
            'name': name,
            'pk': toBase64(publicKey),
            if (addresses.isNotEmpty) 'addrs': addresses,
            if (port != null) 'port': port,
            if (vaultName != null) 'vault': vaultName,
          }),
        ),
      );

  /// Reads a scanned code. Returns null for anything that isn't a Twofold
  /// pairing code.
  static PairingCode? tryParse(String text) {
    if (!text.startsWith(_prefix)) return null;
    try {
      final json = (jsonDecode(
        utf8.decode(fromBase64(text.substring(_prefix.length))),
      ) as Map).cast<String, Object?>();
      final pk = fromBase64(json['pk']! as String);
      if (pk.length != 32) return null;
      return PairingCode(
        memberId: json['id']! as String,
        name: (json['name']! as String).trim(),
        publicKey: pk,
        addresses: (json['addrs'] as List? ?? const []).cast<String>(),
        port: json['port'] as int?,
        vaultName: json['vault'] as String?,
      );
    } on Object {
      return null;
    }
  }
}

/// This phone's addresses on the local network, for the pairing QR code.
Future<List<String>> localAddresses() async {
  final interfaces = await NetworkInterface.list(
    type: InternetAddressType.IPv4,
  );
  return [
    for (final i in interfaces)
      for (final a in i.addresses)
        if (!a.isLoopback && !a.isLinkLocal) a.address,
  ];
}
