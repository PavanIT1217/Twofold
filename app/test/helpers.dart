import 'dart:io';

import 'package:twofold/core/crypto/twofold_crypto.dart';
import 'package:twofold/data/vault.dart';
import 'package:twofold/data/vault_store.dart';

/// A simulated phone: its own folder, identity and (once set up) vault.
class TestPhone {
  TestPhone(this.crypto, this.name, this.dir)
    : store = VaultStore(dir),
      memberId = Vault.newId() {
    identity = crypto.identities
        .create(
          password: 'pw-$name',
          recoveryKey: crypto.recoveryKeys.generate(),
          kdfParams: crypto.kdf.newParams(
            opsLimit: 1,
            memLimit: 8 * 1024 * 1024,
          ),
        )
        .identity;
  }

  final TwofoldCrypto crypto;
  final String name;
  final Directory dir;
  final VaultStore store;
  final String memberId;
  late final Identity identity;
  Vault? vault;

  Future<Vault> createVault([String vaultName = 'Our vault']) async =>
      vault = await Vault.create(
        crypto: crypto,
        store: store,
        identity: identity,
        memberId: memberId,
        memberName: name,
        vaultName: vaultName,
      );

  Future<Vault?> reopen() async => vault = await Vault.open(
    crypto: crypto,
    store: store,
    identity: identity,
    memberId: memberId,
  );
}

/// Syncs two open vaults the way two phones do over Wi-Fi.
Future<(MergeReport, MergeReport)> syncVaults(Vault a, Vault b) async {
  final aWants = a.wanted(b.manifest());
  final bWants = b.wanted(a.manifest());
  final toA = [for (final id in aWants) b.export(id)];
  final toB = [for (final id in bWants) a.export(id)];
  final ra = await a.applyRemote(keyring: b.keyring, records: toA);
  final rb = await b.applyRemote(keyring: a.keyring, records: toB);
  return (ra, rb);
}
