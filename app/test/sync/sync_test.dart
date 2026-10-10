import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/core/crypto/bytes.dart';
import 'package:twofold/core/crypto/twofold_crypto.dart';
import 'package:twofold/data/models.dart';
import 'package:twofold/sync/secure_channel.dart';
import 'package:twofold/sync/sync_session.dart';

import '../helpers.dart';

void main() {
  late TwofoldCrypto crypto;
  late Directory tmp;
  var n = 0;

  setUpAll(() async => crypto = await TwofoldCrypto.init());
  setUp(() async => tmp = await Directory.systemTemp.createTemp('twofold'));
  tearDown(() async => tmp.delete(recursive: true));

  TestPhone phone(String name) =>
      TestPhone(crypto, name, Directory('${tmp.path}/${name}_${n++}'));

  Uint8List? rosterKey(TestPhone p, String id) =>
      publicKeyOf(p.vault?.roster.activeMember(id)?.publicKey);

  /// Connects two phones over a real localhost socket and runs [server] and
  /// [client] on each end.
  Future<(A, B)> overSocket<A, B>(
    Future<A> Function(Socket) server,
    Future<B> Function(Socket) client,
  ) async {
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final serverDone = listener.first.then(server);
    final socket = await Socket.connect(
      InternetAddress.loopbackIPv4,
      listener.port,
    );
    try {
      // Wait for both ends; if either fails, report that failure.
      final results = await Future.wait<Object?>([
        serverDone,
        client(socket),
      ], eagerError: false).catchError((Object e) => throw e);
      return (results[0] as A, results[1] as B);
    } finally {
      await listener.close();
    }
  }

  Future<(SyncResult, SyncResult)> syncOverWifi(
    TestPhone a,
    TestPhone b, {
    Uint8List? Function(String)? aTrusts,
    Uint8List? Function(String)? bTrusts,
  }) => overSocket(
    (s) async {
      final ch = await SecureChannel.accept(
        socket: s,
        crypto: crypto,
        identity: a.identity,
        memberId: a.memberId,
        trustedKey: aTrusts ?? (id) => rosterKey(a, id),
      );
      try {
        return await SyncSession(
          channel: ch,
          store: a.store,
          vault: a.vault,
        ).run();
      } finally {
        await ch.close();
      }
    },
    (s) async {
      final ch = await SecureChannel.initiate(
        socket: s,
        crypto: crypto,
        identity: b.identity,
        memberId: b.memberId,
        trustedKey: bTrusts ?? (id) => rosterKey(b, id),
      );
      try {
        return await SyncSession(
          channel: ch,
          store: b.store,
          vault: b.vault,
        ).run();
      } finally {
        await ch.close();
      }
    },
  );

  test('a new phone joins over Wi-Fi and gets everything', () async {
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    final vault = await ravi.createVault();
    final scan = await vault.addAttachment(
      bytes: Uint8List.fromList(List.filled(5000, 7)),
      name: 'policy.jpg',
      mime: 'image/jpeg',
    );
    await vault.save(
      vault
          .draft('health_insurance')
          .copyWith(title: 'Family floater', attachments: [scan]),
    );

    // Pairing: Ravi scanned Priya's QR and added her; Priya scanned Ravi's.
    await vault.addMember(
      id: priya.memberId,
      name: 'Priya',
      publicKey: priya.identity.publicKey,
      role: Role.editor,
    );
    final priyaTrusts = {ravi.memberId: ravi.identity.publicKey};

    final (toRavi, toPriya) = await syncOverWifi(
      ravi,
      priya,
      bTrusts: (id) => priyaTrusts[id],
    );
    expect(toPriya.received, greaterThanOrEqualTo(2));
    expect(toPriya.filesReceived, 1);
    expect(toRavi.received, 0);

    final hers = (await priya.reopen())!;
    expect(hers.items.single.title, 'Family floater');
    expect(
      await hers.readAttachment(hers.items.single.attachments.single),
      List.filled(5000, 7),
    );
  });

  test('two paired phones exchange edits', () async {
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    final mine = await ravi.createVault();
    await mine.addMember(
      id: priya.memberId,
      name: 'Priya',
      publicKey: priya.identity.publicKey,
      role: Role.editor,
    );
    await syncOverWifi(
      ravi,
      priya,
      bTrusts: (id) => id == ravi.memberId ? ravi.identity.publicKey : null,
    );
    final hers = (await priya.reopen())!;

    await mine.save(mine.draft('note').copyWith(title: 'From Ravi'));
    await hers.save(hers.draft('note').copyWith(title: 'From Priya'));
    await syncOverWifi(ravi, priya);

    expect(
      mine.items.map((i) => i.title),
      containsAll(['From Ravi', 'From Priya']),
    );
    expect(
      hers.items.map((i) => i.title),
      containsAll(['From Ravi', 'From Priya']),
    );
  });

  test('an unpaired phone is refused', () async {
    final ravi = phone('Ravi');
    final stranger = phone('Stranger');
    await ravi.createVault();
    final strangerVault = await stranger.createVault();
    expect(strangerVault, isNotNull);
    await expectLater(
      syncOverWifi(ravi, stranger, bTrusts: (id) => ravi.identity.publicKey),
      throwsA(isA<ChannelException>()),
    );
  });

  test('a phone pretending to be a member is refused', () async {
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    final impostor = phone('Impostor');
    final mine = await ravi.createVault();
    await mine.addMember(
      id: priya.memberId,
      name: 'Priya',
      publicKey: priya.identity.publicKey,
      role: Role.editor,
    );

    // The impostor claims Priya's member id but has a different key.
    final fake = TestPhone(crypto, 'Impostor', impostor.dir);
    final fakeId = priya.memberId;
    await expectLater(
      overSocket(
        (s) => SecureChannel.accept(
          socket: s,
          crypto: crypto,
          identity: ravi.identity,
          memberId: ravi.memberId,
          trustedKey: (id) => rosterKey(ravi, id),
        ),
        (s) => SecureChannel.initiate(
          socket: s,
          crypto: crypto,
          identity: fake.identity,
          memberId: fakeId,
          trustedKey: (id) => ravi.identity.publicKey,
        ),
      ),
      throwsA(isA<ChannelException>()),
    );
  });

  test('frames are encrypted on the wire', () async {
    final ravi = phone('Ravi');
    final priya = phone('Priya');
    final mine = await ravi.createVault();
    await mine.save(mine.draft('note').copyWith(title: 'WIRE-SECRET-42'));
    await mine.addMember(
      id: priya.memberId,
      name: 'Priya',
      publicKey: priya.identity.publicKey,
      role: Role.editor,
    );

    // A relay in the middle records every byte.
    final captured = BytesBuilder();
    final listener = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final relay = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    relay.listen((client) async {
      final upstream = await Socket.connect(
        InternetAddress.loopbackIPv4,
        listener.port,
      );
      client.listen((d) {
        captured.add(d);
        upstream.add(d);
      }, onDone: upstream.destroy);
      upstream.listen((d) {
        captured.add(d);
        client.add(d);
      }, onDone: client.destroy);
    });
    final serverDone = listener.first.then((s) async {
      final ch = await SecureChannel.accept(
        socket: s,
        crypto: crypto,
        identity: ravi.identity,
        memberId: ravi.memberId,
        trustedKey: (id) => rosterKey(ravi, id),
      );
      await SyncSession(channel: ch, store: ravi.store, vault: mine).run();
      await ch.close();
    });
    final s = await Socket.connect(InternetAddress.loopbackIPv4, relay.port);
    final ch = await SecureChannel.initiate(
      socket: s,
      crypto: crypto,
      identity: priya.identity,
      memberId: priya.memberId,
      trustedKey: (id) => ravi.identity.publicKey,
    );
    await SyncSession(channel: ch, store: priya.store).run();
    await ch.close();
    await serverDone;
    await listener.close();
    await relay.close();

    final wire = String.fromCharCodes(captured.takeBytes());
    expect(wire.contains('WIRE-SECRET-42'), isFalse);
    expect(wire.contains('Ravi'), isFalse);
    expect((await priya.reopen())!.items.single.title, 'WIRE-SECRET-42');
    expect(toBase64(ravi.identity.publicKey), isNotEmpty);
  });
}
