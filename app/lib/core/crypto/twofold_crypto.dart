import 'package:sodium/sodium_sumo.dart';

import 'file_cipher.dart';
import 'fingerprint.dart';
import 'identity.dart';
import 'item_cipher.dart';
import 'password_kdf.dart';
import 'recovery_key.dart';
import 'sealed_data.dart';
import 'vault_key.dart';

export 'errors.dart';
export 'file_cipher.dart';
export 'fingerprint.dart';
export 'identity.dart';
export 'item_cipher.dart';
export 'password_kdf.dart';
export 'recovery_key.dart';
export 'vault_key.dart';

/// Everything Twofold encrypts goes through here.
///
/// ```text
/// master password ──Argon2id──▶ password key ─┐
/// recovery key ───────────────────────────────┴─▶ unlocks identity (X25519)
/// identity ──opens──▶ vault key (sealed per member)
/// vault key ──wraps──▶ item keys / file keys ──▶ items / attachments
/// ```
class TwofoldCrypto {
  TwofoldCrypto(this.sodium)
    : _sealed = SealedData(sodium),
      kdf = PasswordKdf(sodium) {
    recoveryKeys = RecoveryKey(sodium);
    identities = Identities(sodium, _sealed, kdf);
    vaultKeys = VaultKeys(sodium, _sealed);
    items = ItemCipher(_sealed);
    files = FileCipher(sodium, _sealed);
    fingerprints = Fingerprints(sodium);
  }

  /// Loads the libsodium bundled with the app.
  static Future<TwofoldCrypto> init() async =>
      TwofoldCrypto(await SodiumSumoInit.init());

  final SodiumSumo sodium;
  final SealedData _sealed;
  final PasswordKdf kdf;
  late final RecoveryKey recoveryKeys;
  late final Identities identities;
  late final VaultKeys vaultKeys;
  late final ItemCipher items;
  late final FileCipher files;
  late final Fingerprints fingerprints;
}
