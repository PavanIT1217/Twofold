import 'dart:convert';
import 'dart:typed_data';

/// Joins byte arrays into one.
Uint8List concatBytes(List<List<int>> parts) {
  final builder = BytesBuilder(copy: false);
  for (final part in parts) {
    builder.add(part);
  }
  return builder.takeBytes();
}

/// UTF-8 encodes [text].
Uint8List utf8Bytes(String text) => Uint8List.fromList(utf8.encode(text));

/// Unpadded base64url, used for every binary value stored in JSON.
String toBase64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');

/// Reverses [toBase64]. Accepts padded or unpadded input.
Uint8List fromBase64(String text) =>
    base64Url.decode(base64Url.normalize(text));

/// Compares two byte arrays without stopping at the first difference.
bool bytesEqual(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Overwrites [bytes] with zeros so a copy of a key doesn't linger in memory.
void wipe(Uint8List bytes) => bytes.fillRange(0, bytes.length, 0);
