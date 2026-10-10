/// Thrown when something can't be decrypted or verified.
///
/// The message is safe to show to the user: it never contains key material
/// or vault contents. Wrong passwords, wrong keys and tampered data all look
/// the same on purpose.
class TwofoldCryptoException implements Exception {
  const TwofoldCryptoException(this.message);

  final String message;

  @override
  String toString() => 'TwofoldCryptoException: $message';
}
