import 'dart:convert';
import 'dart:typed_data';

import '../core/crypto/bytes.dart';
import '../core/crypto/twofold_crypto.dart';
import '../data/keyring.dart';
import '../data/vault.dart';
import '../data/vault_store.dart';
import 'secure_channel.dart';

/// What one sync with another phone did.
class SyncResult {
  const SyncResult({
    required this.peerId,
    required this.received,
    required this.sent,
    required this.filesReceived,
    this.report,
  });

  final String peerId;
  final int received;
  final int sent;
  final int filesReceived;

  /// How the received records were merged. Null when this phone was still
  /// joining and simply took the whole vault.
  final MergeReport? report;
}

/// Runs one sync over an authenticated [SecureChannel].
///
/// Both phones run the same steps at the same time:
///
/// 1. `hello`: vault id, keyring, version vectors of every record, file ids
/// 2. `want`: the records and files this phone is missing
/// 3. `records`, then one `file` message per attachment, then `end`
///
/// A phone that is still joining has no vault open; it asks for everything
/// and writes what it receives straight to its store.
class SyncSession {
  SyncSession({required this.channel, required this.store, this.vault});

  final SecureChannel channel;
  final VaultStore store;
  final Vault? vault;

  Future<SyncResult> run() async {
    final vault = this.vault;
    final myFiles = await store.listFiles();
    final sendableFiles = vault == null
        ? <String>{}
        : myFiles.intersection(vault.referencedFiles);

    await channel.send({
      't': 'hello',
      'vaultId': vault?.vaultId,
      'keyring': vault?.keyring.toJson(),
      'manifest': vault?.manifest() ?? const {},
      'files': sendableFiles.toList(),
    });
    final hello = await _expect('hello');
    final theirVault = hello['vaultId'] as String?;
    if (vault != null && theirVault != null && theirVault != vault.vaultId) {
      throw const ChannelException('That phone belongs to a different vault.');
    }
    final theirManifest = {
      for (final e in (hello['manifest']! as Map).entries)
        e.key as String: (e.value as Map).cast<String, int>(),
    };
    final theirFiles = (hello['files']! as List).cast<String>().toSet();
    final theirKeyring = hello['keyring'] == null
        ? null
        : Keyring.fromJson((hello['keyring']! as Map).cast<String, Object?>());

    final wantItems = vault == null
        ? theirManifest.keys.toList()
        : vault.wanted(theirManifest);
    final wantFiles = theirFiles.difference(myFiles).toList();
    await channel.send({'t': 'want', 'items': wantItems, 'files': wantFiles});

    final want = await _expect('want');
    final requestedItems = (want['items']! as List).cast<String>();
    final requestedFiles = (want['files']! as List).cast<String>();

    // Send what they asked for.
    var sent = 0;
    if (vault != null) {
      final manifest = vault.manifest();
      final records = [
        for (final id in requestedItems)
          if (manifest.containsKey(id)) vault.export(id).toJson(),
      ];
      sent = records.length;
      await channel.send({'t': 'records', 'records': records});
      for (final id in requestedFiles) {
        if (!sendableFiles.contains(id)) continue;
        final data = await store.readFile(id);
        if (data == null) continue;
        await channel.send({
          't': 'file',
          'id': id,
          'data': base64.encode(data),
        });
      }
    } else {
      await channel.send({'t': 'records', 'records': const []});
    }
    await channel.send({'t': 'end'});

    // Receive what we asked for.
    final recordsMsg = await _expect('records');
    final records = [
      for (final r in recordsMsg['records']! as List)
        EncryptedItem.fromJson((r as Map).cast<String, Object?>()),
    ];
    var filesReceived = 0;
    final wanted = wantFiles.toSet();
    while (true) {
      final msg = await channel.receive();
      if (msg['t'] == 'end') break;
      if (msg['t'] != 'file') {
        throw const ChannelException('Unexpected message during sync.');
      }
      final id = msg['id']! as String;
      if (!wanted.remove(id)) continue;
      await store.writeFile(
        id,
        Uint8List.fromList(base64.decode(msg['data']! as String)),
      );
      filesReceived++;
    }

    MergeReport? report;
    if (vault != null) {
      report = await vault.applyRemote(keyring: theirKeyring, records: records);
    } else if (theirKeyring != null) {
      // Joining: take the whole vault. It is only usable if the keyring holds
      // a key sealed for this phone, which Vault.open checks afterwards.
      await store.writeKeyring(theirKeyring);
      for (final r in records) {
        if (r.vaultId == theirKeyring.vaultId) await store.writeItem(r);
      }
    }
    return SyncResult(
      peerId: channel.peerId,
      received: records.length,
      sent: sent,
      filesReceived: filesReceived,
      report: report,
    );
  }

  Future<Map<String, Object?>> _expect(String type) async {
    final msg = await channel.receive();
    if (msg['t'] != type) {
      throw ChannelException('Expected "$type" from the other phone.');
    }
    return msg;
  }
}

/// Converts a base64url public key from the roster.
Uint8List? publicKeyOf(String? base64) =>
    base64 == null ? null : fromBase64(base64);
