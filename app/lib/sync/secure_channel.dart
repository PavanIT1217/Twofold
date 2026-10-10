import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';

import '../core/crypto/bytes.dart';
import '../core/crypto/twofold_crypto.dart' show Identity, TwofoldCrypto;

/// Thrown when a peer can't be authenticated or breaks the protocol.
class ChannelException implements Exception {
  const ChannelException(this.message);

  final String message;

  @override
  String toString() => 'ChannelException: $message';
}

/// Looks up the public key this phone trusts for a member id, or null if the
/// member is unknown (never paired, or removed).
typedef TrustedKeyLookup = Uint8List? Function(String memberId);

/// An encrypted, mutually authenticated connection between two paired
/// phones over a plain TCP socket.
///
/// The handshake mixes four X25519 results (ephemeral-ephemeral,
/// ephemeral-static both ways, static-static), so only the two phones
/// holding the paired identity keys can derive the session keys, and a fresh
/// session key is used every time. Every frame after the handshake is
/// XChaCha20-Poly1305 with a counter nonce, so frames can't be read,
/// changed, replayed or reordered.
class SecureChannel {
  SecureChannel._(
    this._socket,
    this._reader,
    this._sodium,
    this._sendKey,
    this._receiveKey,
    this.peerId,
  );

  static const _maxFrame = 64 * 1024 * 1024;

  /// Before the other phone is authenticated, only small messages are
  /// accepted, so an unknown device can't make this one buffer much data.
  static const _maxHandshakeFrame = 4 * 1024;
  static const _handshakeTimeout = Duration(seconds: 15);

  final Socket _socket;
  final _FrameReader _reader;
  final SodiumSumo _sodium;
  final SecureKey _sendKey;
  final SecureKey _receiveKey;

  /// The authenticated member id of the other phone.
  final String peerId;

  int _sendCounter = 0;
  int _receiveCounter = 0;

  /// Runs the handshake as the phone that opened the connection.
  static Future<SecureChannel> initiate({
    required Socket socket,
    required TwofoldCrypto crypto,
    required Identity identity,
    required String memberId,
    required TrustedKeyLookup trustedKey,
    String? expectedPeer,
  }) => _handshake(
    socket: socket,
    crypto: crypto,
    identity: identity,
    memberId: memberId,
    trustedKey: trustedKey,
    initiator: true,
    expectedPeer: expectedPeer,
  );

  /// Runs the handshake as the phone that accepted the connection.
  static Future<SecureChannel> accept({
    required Socket socket,
    required TwofoldCrypto crypto,
    required Identity identity,
    required String memberId,
    required TrustedKeyLookup trustedKey,
  }) => _handshake(
    socket: socket,
    crypto: crypto,
    identity: identity,
    memberId: memberId,
    trustedKey: trustedKey,
    initiator: false,
  );

  static Future<SecureChannel> _handshake({
    required Socket socket,
    required TwofoldCrypto crypto,
    required Identity identity,
    required String memberId,
    required TrustedKeyLookup trustedKey,
    required bool initiator,
    String? expectedPeer,
  }) async {
    final sodium = crypto.sodium;
    final reader = _FrameReader(socket, _maxHandshakeFrame);
    final eph = sodium.crypto.box.keyPair();
    try {
      final hello = utf8Bytes(
        jsonEncode({'v': 1, 'id': memberId, 'eph': toBase64(eph.publicKey)}),
      );
      Map<String, Object?> theirs;
      if (initiator) {
        _writeFrame(socket, hello);
        theirs = _decodeHello(await reader.next().timeout(_handshakeTimeout));
      } else {
        theirs = _decodeHello(await reader.next().timeout(_handshakeTimeout));
      }
      final peerId = theirs['id']! as String;
      final peerEph = fromBase64(theirs['eph']! as String);
      if (expectedPeer != null && peerId != expectedPeer) {
        throw const ChannelException('Connected to the wrong phone.');
      }
      final peerStatic = trustedKey(peerId);
      if (peerStatic == null) {
        throw const ChannelException('This phone is not paired with you.');
      }
      if (!initiator) _writeFrame(socket, hello);

      Uint8List dh(SecureKey secret, Uint8List public) {
        final shared = sodium.crypto.scalarmult(n: secret, p: public);
        try {
          return shared.extractBytes();
        } finally {
          shared.dispose();
        }
      }

      final List<Uint8List> parts;
      final String initiatorId;
      final String responderId;
      final Uint8List initiatorEph;
      final Uint8List responderEph;
      if (initiator) {
        parts = [
          dh(eph.secretKey, peerEph),
          dh(eph.secretKey, peerStatic),
          dh(identity.secretKey, peerEph),
          dh(identity.secretKey, peerStatic),
        ];
        (initiatorId, responderId) = (memberId, peerId);
        (initiatorEph, responderEph) = (eph.publicKey, peerEph);
      } else {
        parts = [
          dh(eph.secretKey, peerEph),
          dh(identity.secretKey, peerEph),
          dh(eph.secretKey, peerStatic),
          dh(identity.secretKey, peerStatic),
        ];
        (initiatorId, responderId) = (peerId, memberId);
        (initiatorEph, responderEph) = (peerEph, eph.publicKey);
      }
      final material = concatBytes([
        ...parts,
        utf8Bytes('twofold/v1/channel|$initiatorId|$responderId|'),
        initiatorEph,
        responderEph,
      ]);
      final okm = sodium.crypto.genericHash(message: material, outLen: 64);
      wipe(material);
      for (final p in parts) {
        wipe(p);
      }
      final forward = sodium.secureCopy(Uint8List.sublistView(okm, 0, 32));
      final backward = sodium.secureCopy(Uint8List.sublistView(okm, 32, 64));
      wipe(okm);

      final channel = SecureChannel._(
        socket,
        reader,
        sodium,
        initiator ? forward : backward,
        initiator ? backward : forward,
        peerId,
      );
      // Prove both sides derived the same keys before any data moves.
      reader.max = _maxFrame;
      await channel.send({'t': 'ready'});
      final ready = await channel.receive().timeout(_handshakeTimeout);
      if (ready['t'] != 'ready') {
        throw const ChannelException('Handshake failed.');
      }
      return channel;
    } on TimeoutException {
      socket.destroy();
      throw const ChannelException('The other phone stopped responding.');
    } on ChannelException {
      socket.destroy();
      rethrow;
    } on SodiumException {
      socket.destroy();
      throw const ChannelException('Could not verify the other phone.');
    } on FormatException {
      socket.destroy();
      throw const ChannelException('The other phone sent something invalid.');
    } finally {
      eph.secretKey.dispose();
    }
  }

  static Map<String, Object?> _decodeHello(Uint8List frame) {
    final json = (jsonDecode(utf8.decode(frame)) as Map)
        .cast<String, Object?>();
    if (json['v'] != 1 || json['id'] is! String || json['eph'] is! String) {
      throw const FormatException('bad hello');
    }
    return json;
  }

  Aead get _aead => _sodium.crypto.aeadXChaCha20Poly1305IETF;

  Uint8List _nonce(int counter) {
    final nonce = Uint8List(_aead.nonceBytes);
    var c = counter;
    for (var i = 0; i < 8; i++) {
      nonce[i] = c & 0xff;
      c >>= 8;
    }
    return nonce;
  }

  static final _frameAd = utf8Bytes('twofold/v1/frame');

  Future<void> send(Map<String, Object?> message) async {
    final plain = utf8Bytes(jsonEncode(message));
    final sealed = _aead.encrypt(
      message: plain,
      nonce: _nonce(_sendCounter++),
      key: _sendKey,
      additionalData: _frameAd,
    );
    wipe(plain);
    _writeFrame(_socket, sealed);
    await _socket.flush();
  }

  Future<Map<String, Object?>> receive() async {
    final frame = await _reader.next();
    final Uint8List plain;
    try {
      plain = _aead.decrypt(
        cipherText: frame,
        nonce: _nonce(_receiveCounter++),
        key: _receiveKey,
        additionalData: _frameAd,
      );
    } on SodiumException {
      throw const ChannelException(
        'A message from the other phone was tampered with.',
      );
    }
    try {
      return (jsonDecode(utf8.decode(plain)) as Map).cast<String, Object?>();
    } finally {
      wipe(plain);
    }
  }

  Future<void> close() async {
    _sendKey.dispose();
    _receiveKey.dispose();
    await _reader.cancel();
    try {
      await _socket.close();
    } on SocketException {
      // Already closed by the other side.
    }
    _socket.destroy();
  }

  static void _writeFrame(Socket socket, Uint8List payload) {
    final header = ByteData(4)..setUint32(0, payload.length);
    socket.add(header.buffer.asUint8List());
    socket.add(payload);
  }
}

/// Splits the socket's byte stream into length-prefixed frames.
class _FrameReader {
  _FrameReader(Socket socket, this.max) {
    _subscription = socket.listen(
      _onData,
      onError: (Object e) => _fail(ChannelException('Connection error: $e')),
      onDone: () => _fail(const ChannelException('The other phone hung up.')),
      cancelOnError: true,
    );
  }

  int max;
  late final StreamSubscription<Uint8List> _subscription;
  final _buffer = BytesBuilder(copy: false);
  final _frames = <Uint8List>[];
  final _waiters = <Completer<Uint8List>>[];
  Object? _error;

  void _onData(Uint8List data) {
    _buffer.add(data);
    var bytes = _buffer.takeBytes();
    var offset = 0;
    while (bytes.length - offset >= 4) {
      final length = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0);
      if (length > max) {
        _fail(const ChannelException('Message too large.'));
        return;
      }
      if (bytes.length - offset - 4 < length) break;
      _deliver(
        Uint8List.fromList(
          Uint8List.sublistView(bytes, offset + 4, offset + 4 + length),
        ),
      );
      offset += 4 + length;
    }
    if (offset < bytes.length) {
      _buffer.add(Uint8List.sublistView(bytes, offset));
    }
    bytes = Uint8List(0);
  }

  void _deliver(Uint8List frame) {
    if (_waiters.isNotEmpty) {
      _waiters.removeAt(0).complete(frame);
    } else {
      _frames.add(frame);
    }
  }

  void _fail(Object error) {
    _error ??= error;
    for (final w in _waiters) {
      w.completeError(error);
    }
    _waiters.clear();
  }

  Future<Uint8List> next() {
    if (_frames.isNotEmpty) return Future.value(_frames.removeAt(0));
    if (_error != null) return Future.error(_error!);
    final completer = Completer<Uint8List>();
    _waiters.add(completer);
    return completer.future;
  }

  Future<void> cancel() => _subscription.cancel();
}
