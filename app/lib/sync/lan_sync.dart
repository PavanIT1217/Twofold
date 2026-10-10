import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:bonsoir/bonsoir.dart';

import '../core/crypto/bytes.dart';
import '../core/crypto/twofold_crypto.dart';
import '../data/vault.dart';
import '../data/vault_store.dart';
import 'secure_channel.dart';
import 'sync_session.dart';

/// A paired phone seen on the same Wi-Fi.
class NearbyPeer {
  const NearbyPeer({
    required this.memberId,
    required this.host,
    required this.port,
  });

  final String memberId;
  final String host;
  final int port;
}

/// Keeps paired phones in sync while the app is open and unlocked:
/// listens for connections, announces itself on the local network with
/// Bonjour/mDNS, and syncs with every paired phone it finds.
class LanSync {
  LanSync({
    required this.crypto,
    required this.store,
    required this.identity,
    required this.memberId,
    required this.vault,
    required this.onSynced,
    this.onError,
  });

  static const serviceType = '_twofold._tcp';

  final TwofoldCrypto crypto;
  final VaultStore store;
  final Identity identity;
  final String memberId;

  /// The open vault, or null while this phone is still joining.
  Vault? Function() vault;
  final void Function(SyncResult result) onSynced;
  final void Function(Object error)? onError;

  ServerSocket? _server;
  BonsoirBroadcast? _broadcast;
  BonsoirDiscovery? _discovery;
  final Map<String, NearbyPeer> _nearby = {};
  Future<void> _queue = Future.value();
  Map<String, String> _trusted = {};

  int? get port => _server?.port;
  Iterable<NearbyPeer> get nearby => _nearby.values;

  /// Starts listening. Discovery is optional so tests can run without the
  /// platform plugin.
  Future<void> start({bool discover = true}) async {
    _trusted = await store.readTrusted();
    _server ??= await ServerSocket.bind(InternetAddress.anyIPv4, 0);
    _server!.listen(_onConnection, onError: (Object e) => onError?.call(e));
    if (discover) await _startDiscovery();
  }

  Future<void> stop() async {
    await _broadcast?.stop();
    await _discovery?.stop();
    _broadcast = null;
    _discovery = null;
    await _server?.close();
    _server = null;
    _nearby.clear();
  }

  /// Trusts a phone whose QR code was scanned while pairing.
  Future<void> trust(String memberId, Uint8List publicKey) async {
    _trusted = {..._trusted, memberId: toBase64(publicKey)};
    await store.writeTrusted(_trusted);
  }

  Uint8List? _trustedKey(String id) {
    final member = vault()?.roster.activeMember(id);
    if (member != null) return fromBase64(member.publicKey);
    if (vault() == null) {
      final scanned = _trusted[id];
      if (scanned != null) return fromBase64(scanned);
    }
    return null;
  }

  /// Syncs with every paired phone currently nearby.
  Future<List<SyncResult>> syncAll() async {
    final results = <SyncResult>[];
    for (final peer in _nearby.values.toList()) {
      try {
        results.add(
          await syncWith(peer.host, peer.port, expectedPeer: peer.memberId),
        );
      } on Object catch (e) {
        onError?.call(e);
      }
    }
    return results;
  }

  /// Connects to a phone at [host]:[port] and syncs.
  Future<SyncResult> syncWith(String host, int port, {String? expectedPeer}) =>
      _serialized(() async {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 8),
        );
        final channel = await SecureChannel.initiate(
          socket: socket,
          crypto: crypto,
          identity: identity,
          memberId: memberId,
          trustedKey: _trustedKey,
          expectedPeer: expectedPeer,
        );
        return _run(channel);
      });

  void _onConnection(Socket socket) {
    _serialized(() async {
      final channel = await SecureChannel.accept(
        socket: socket,
        crypto: crypto,
        identity: identity,
        memberId: memberId,
        trustedKey: _trustedKey,
      );
      return _run(channel);
    }).catchError((Object e) {
      onError?.call(e);
      return const SyncResult(
        peerId: '',
        received: 0,
        sent: 0,
        filesReceived: 0,
      );
    });
  }

  Future<SyncResult> _run(SecureChannel channel) async {
    try {
      final result = await SyncSession(
        channel: channel,
        store: store,
        vault: vault(),
      ).run();
      onSynced(result);
      return result;
    } finally {
      await channel.close();
    }
  }

  /// Runs one sync at a time, so two sessions never merge into the vault at
  /// once.
  Future<T> _serialized<T>(Future<T> Function() task) {
    final next = _queue.then((_) => task());
    _queue = next.then((_) {}, onError: (_) {});
    return next;
  }

  String get _vaultTag {
    final id = vault()?.vaultId;
    if (id == null) return 'joining';
    final hash = crypto.sodium.crypto.genericHash(
      message: utf8Bytes('twofold/v1/lan-tag|$id'),
      outLen: 16,
    );
    return toBase64(hash).substring(0, 12);
  }

  Future<void> _startDiscovery() async {
    final port = _server!.port;
    final service = BonsoirService(
      name: 'Twofold ${memberId.substring(0, 8)}',
      type: serviceType,
      port: port,
      attributes: {'m': memberId, 'v': _vaultTag},
    );
    _broadcast = BonsoirBroadcast(service: service);
    await _broadcast!.initialize();
    await _broadcast!.start();

    final discovery = BonsoirDiscovery(type: serviceType);
    _discovery = discovery;
    await discovery.initialize();
    discovery.eventStream?.listen((event) {
      switch (event) {
        case BonsoirDiscoveryServiceFoundEvent(:final service):
          if (service.attributes['m'] != memberId) {
            discovery.serviceResolver.resolveService(service);
          }
        case BonsoirDiscoveryServiceResolvedEvent(:final service):
          _onResolved(service);
        case BonsoirDiscoveryServiceLostEvent(:final service):
          _nearby.remove(service.attributes['m']);
        default:
          break;
      }
    });
    await discovery.start();
  }

  void _onResolved(BonsoirService service) {
    final peerId = service.attributes['m'];
    final host = service.hostAddress ?? service.hostname;
    if (peerId == null || host == null || peerId == memberId) return;
    if (service.attributes['v'] != _vaultTag) return;
    if (vault()?.roster.activeMember(peerId) == null) return;
    final peer = NearbyPeer(memberId: peerId, host: host, port: service.port);
    _nearby[peerId] = peer;
    // Only one side starts the sync, so the two phones don't both dial.
    if (memberId.compareTo(peerId) < 0) {
      syncWith(peer.host, peer.port, expectedPeer: peerId).catchError((
        Object e,
      ) {
        onError?.call(e);
        return const SyncResult(
          peerId: '',
          received: 0,
          sent: 0,
          filesReceived: 0,
        );
      });
    }
  }
}
