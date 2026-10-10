import 'dart:convert';

/// Every version of the vault key, each sealed separately for the members
/// who may open it. Holds no secrets in the clear.
class Keyring {
  const Keyring({required this.vaultId, required this.versions});

  factory Keyring.fromJson(Map<String, Object?> json) => Keyring(
    vaultId: json['vaultId']! as String,
    versions: {
      for (final e in (json['versions']! as Map).entries)
        int.parse(e.key as String): (e.value as Map).cast<String, String>(),
    },
  );

  final String vaultId;

  /// key version -> member id -> sealed vault key (base64url).
  final Map<int, Map<String, String>> versions;

  int get currentVersion => versions.keys.fold(0, (a, b) => a > b ? a : b);

  Keyring withSealed(int version, Map<String, String> sealed) => Keyring(
    vaultId: vaultId,
    versions: {
      ...versions,
      version: {...?versions[version], ...sealed},
    },
  );

  /// Union of both keyrings. A member missing from a newer version (because
  /// they were removed) stays missing.
  Keyring merge(Keyring other) {
    if (other.vaultId != vaultId) {
      throw ArgumentError('Keyrings belong to different vaults.');
    }
    var out = this;
    other.versions.forEach((v, sealed) => out = out.withSealed(v, sealed));
    return out;
  }

  Map<String, Object?> toJson() => {
    'vaultId': vaultId,
    'versions': {for (final e in versions.entries) '${e.key}': e.value},
  };

  /// Stable text form, used to tell whether two phones' keyrings differ.
  String canonical() {
    final keys = versions.keys.toList()..sort();
    return jsonEncode([
      vaultId,
      for (final k in keys)
        [
          k,
          for (final m in (versions[k]!.keys.toList()..sort()))
            [m, versions[k]![m]],
        ],
    ]);
  }
}
