import 'dart:convert';
import 'dart:typed_data';

import 'package:sodium/sodium_sumo.dart';
import 'package:uuid/uuid.dart';

import '../core/crypto/bytes.dart';
import '../core/crypto/twofold_crypto.dart';
import 'keyring.dart';
import 'models.dart';
import 'vault_store.dart';
import 'version_vector.dart';

/// Id of the encrypted record that holds the [Roster].
const rosterId = '_roster';

/// How long trashed items stay before their contents are wiped.
const trashRetention = Duration(days: 30);

/// What happened when changes from another phone were applied.
class MergeReport {
  int added = 0;
  int updated = 0;
  int conflicts = 0;
  int rejected = 0;
  bool rosterChanged = false;
  bool keyringChanged = false;

  bool get changedAnything =>
      added + updated + conflicts > 0 || rosterChanged || keyringChanged;
}

/// An open, unlocked vault: decrypted items in memory, encrypted on disk.
class Vault {
  Vault._({
    required this.crypto,
    required this.store,
    required this.identity,
    required this.memberId,
    required Keyring keyring,
    required Map<int, SecureKey> keys,
    required Roster roster,
    required Map<String, VaultItem> items,
    DateTime Function()? clock,
  }) : _keyring = keyring, // ignore: prefer_initializing_formals
       _keys = keys, // ignore: prefer_initializing_formals
       _roster = roster, // ignore: prefer_initializing_formals
       _items = items, // ignore: prefer_initializing_formals
       _clock = clock ?? DateTime.now;

  final TwofoldCrypto crypto;
  final VaultStore store;
  final Identity identity;
  final String memberId;
  final DateTime Function() _clock;

  Keyring _keyring;
  final Map<int, SecureKey> _keys;
  Roster _roster;
  final Map<String, VaultItem> _items;

  static const _uuid = Uuid();

  static String newId() => _uuid.v4();

  String get vaultId => _keyring.vaultId;
  Keyring get keyring => _keyring;
  Roster get roster => _roster;
  int get keyVersion => _keyring.currentVersion;
  Member? get me => _roster.activeMember(memberId);
  Role get myRole => me?.role ?? Role.viewer;

  /// Items not in the trash, newest first.
  List<VaultItem> get items =>
      _items.values.where((i) => !i.deleted).toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

  /// Items in the trash that still have their contents.
  List<VaultItem> get trash =>
      _items.values.where((i) => i.deleted && i.type != 'purged').toList()
        ..sort((a, b) => b.deletedAt!.compareTo(a.deletedAt!));

  VaultItem? item(String id) => _items[id];

  /// Version vectors of every record, sent to other phones while syncing.
  Map<String, Map<String, int>> manifest() => {
    rosterId: _roster.vv.toJson(),
    for (final i in _items.values) i.id: i.vv.toJson(),
  };

  // ---------------------------------------------------------------------------
  // Creating and opening

  /// Creates a new vault with this phone as its owner.
  static Future<Vault> create({
    required TwofoldCrypto crypto,
    required VaultStore store,
    required Identity identity,
    required String memberId,
    required String memberName,
    required String vaultName,
    DateTime Function()? clock,
  }) async {
    final now = (clock ?? DateTime.now)();
    final vaultId = newId();
    final key = crypto.vaultKeys.create();
    final keyring = Keyring(
      vaultId: vaultId,
      versions: {
        1: {
          memberId: toBase64(
            crypto.vaultKeys.sealFor(
              vaultKey: key,
              memberPublicKey: identity.publicKey,
              vaultId: vaultId,
              keyVersion: 1,
            ),
          ),
        },
      },
    );
    final roster = Roster(
      vaultName: vaultName,
      members: {
        memberId: Member(
          id: memberId,
          name: memberName,
          publicKey: toBase64(identity.publicKey),
          role: Role.owner,
          addedAt: now,
        ),
      },
      vv: const VersionVector().bump(memberId),
    );
    final vault = Vault._(
      crypto: crypto,
      store: store,
      identity: identity,
      memberId: memberId,
      keyring: keyring,
      keys: {1: key},
      roster: roster,
      items: {},
      clock: clock,
    );
    await store.writeKeyring(keyring);
    await vault._writeRoster();
    return vault;
  }

  /// Opens the vault stored on this phone. Returns null when there is no
  /// vault yet, or none of its keys were sealed for this phone (for example
  /// while still joining).
  static Future<Vault?> open({
    required TwofoldCrypto crypto,
    required VaultStore store,
    required Identity identity,
    required String memberId,
    DateTime Function()? clock,
  }) async {
    final keyring = await store.readKeyring();
    if (keyring == null) return null;
    final keys = _openKeys(crypto, keyring, identity, memberId);
    if (keys.isEmpty) return null;

    Roster? roster;
    final items = <String, VaultItem>{};
    for (final record in await store.readItems()) {
      final key = keys[record.keyVersion];
      if (key == null || record.vaultId != keyring.vaultId) continue;
      final json = crypto.items.decrypt(record, key);
      if (record.itemId == rosterId) {
        roster = Roster.fromJson(json);
      } else {
        final item = VaultItem.fromJson(json);
        items[item.id] = item;
      }
    }
    if (roster == null) return null;
    return Vault._(
      crypto: crypto,
      store: store,
      identity: identity,
      memberId: memberId,
      keyring: keyring,
      keys: keys,
      roster: roster,
      items: items,
      clock: clock,
    );
  }

  static Map<int, SecureKey> _openKeys(
    TwofoldCrypto crypto,
    Keyring keyring,
    Identity identity,
    String memberId,
  ) {
    final keys = <int, SecureKey>{};
    keyring.versions.forEach((version, sealed) {
      final mine = sealed[memberId];
      if (mine == null) return;
      try {
        keys[version] = crypto.vaultKeys.open(
          sealed: fromBase64(mine),
          identity: identity,
          vaultId: keyring.vaultId,
          keyVersion: version,
        );
      } on TwofoldCryptoException {
        // A key sealed for someone else under our id; ignore it.
      }
    });
    return keys;
  }

  /// Forgets the keys held in memory. The vault must not be used afterwards.
  void close() {
    for (final key in _keys.values) {
      key.dispose();
    }
    _keys.clear();
    _items.clear();
  }

  // ---------------------------------------------------------------------------
  // Items

  /// Starts a new, unsaved item.
  VaultItem draft(String type) {
    final now = _clock();
    return VaultItem(
      id: newId(),
      type: type,
      title: '',
      createdAt: now,
      updatedAt: now,
      updatedBy: memberId,
    );
  }

  /// Saves a new or edited item.
  Future<VaultItem> save(VaultItem edited) async {
    _requireEditor();
    final previous = _items[edited.id];
    final saved = edited.copyWith(
      updatedAt: _clock(),
      updatedBy: memberId,
      vv: (previous?.vv ?? edited.vv).bump(memberId),
    );
    await _writeItem(saved);
    return saved;
  }

  Future<void> moveToTrash(String id) async {
    final item = _items[id];
    if (item == null || item.deleted) return;
    await save(
      item.copyWith(deleted: true, deletedAt: _clock(), pinned: false),
    );
  }

  Future<void> restore(String id) async {
    final item = _items[id];
    if (item == null || !item.deleted || item.type == 'purged') return;
    await save(item.copyWith(deleted: false, clearDeletedAt: true));
  }

  /// Wipes an item's contents for good. A small record stays behind so the
  /// deletion reaches the other phones.
  Future<void> purge(String id) async {
    _requireEditor();
    final item = _items[id];
    if (item == null) return;
    for (final a in item.attachments) {
      await store.deleteFile(a.id);
    }
    final now = _clock();
    final tombstone = VaultItem(
      id: item.id,
      type: 'purged',
      title: '',
      deleted: true,
      deletedAt: item.deletedAt ?? now,
      createdAt: item.createdAt,
      updatedAt: now,
      updatedBy: memberId,
      vv: item.vv.bump(memberId),
    );
    await _writeItem(tombstone);
  }

  /// Purges trashed items older than [trashRetention].
  Future<int> emptyOldTrash() async {
    if (!myRole.canEdit) return 0;
    final cutoff = _clock().subtract(trashRetention);
    final old = trash.where((i) => i.deletedAt!.isBefore(cutoff)).toList();
    for (final item in old) {
      await purge(item.id);
    }
    return old.length;
  }

  // ---------------------------------------------------------------------------
  // Attachments

  Future<Attachment> addAttachment({
    required Uint8List bytes,
    required String name,
    required String mime,
  }) async {
    _requireEditor();
    final id = newId();
    final encrypted = await crypto.files.encrypt(
      bytes: bytes,
      vaultKey: _currentKey,
      vaultId: vaultId,
      attachmentId: id,
      keyVersion: keyVersion,
    );
    await store.writeFile(id, encrypted.cipherText);
    return Attachment(
      id: id,
      name: name,
      mime: mime,
      size: bytes.length,
      keyVersion: keyVersion,
      wrappedKey: toBase64(encrypted.wrappedKey),
    );
  }

  /// Decrypts an attachment, or returns null if this phone doesn't have the
  /// file yet (it arrives with the next sync).
  Future<Uint8List?> readAttachment(Attachment attachment) async {
    final cipherText = await store.readFile(attachment.id);
    final key = _keys[attachment.keyVersion];
    if (cipherText == null || key == null) return null;
    return crypto.files.decrypt(
      file: EncryptedFile(
        wrappedKey: fromBase64(attachment.wrappedKey),
        cipherText: cipherText,
      ),
      vaultKey: key,
      vaultId: vaultId,
      attachmentId: attachment.id,
      keyVersion: attachment.keyVersion,
    );
  }

  /// Deletes attachment files no item refers to any more (for example a
  /// photo added to an edit that was then discarded).
  Future<int> deleteUnreferencedFiles() async {
    final keep = referencedFiles;
    var deleted = 0;
    for (final id in await store.listFiles()) {
      if (!keep.contains(id)) {
        await store.deleteFile(id);
        deleted++;
      }
    }
    return deleted;
  }

  /// Attachment ids referenced by live items.
  Set<String> get referencedFiles => {
    for (final i in _items.values)
      if (i.type != 'purged') ...i.attachments.map((a) => a.id),
  };

  // ---------------------------------------------------------------------------
  // Members

  Future<void> renameVault(String name) async {
    _requireOwner();
    await _saveRoster(_roster.copyWith(vaultName: name));
  }

  /// Adds a paired phone and seals the current vault key for it.
  Future<void> addMember({
    required String id,
    required String name,
    required Uint8List publicKey,
    required Role role,
  }) async {
    _requireOwner();
    if (_roster.active.length >= Roster.maxMembers &&
        _roster.activeMember(id) == null) {
      throw StateError(
        'A vault can have at most ${Roster.maxMembers} members.',
      );
    }
    final existing = _roster.members[id];
    if (existing != null && existing.removed) {
      throw StateError('That phone was removed. Set it up again to re-add it.');
    }
    final member = Member(
      id: id,
      name: name,
      publicKey: toBase64(publicKey),
      role: role,
      addedAt: _clock(),
    );
    await _sealCurrentKeyFor(member);
    await _saveRoster(
      _roster.copyWith(members: {..._roster.members, id: member}),
    );
  }

  Future<void> changeRole(String id, Role role) async {
    _requireOwner();
    final member = _roster.activeMember(id);
    if (member == null) return;
    if (member.role == Role.owner && role != Role.owner && _ownerCount == 1) {
      throw StateError('A vault needs at least one owner.');
    }
    await _saveRoster(
      _roster.copyWith(
        members: {
          ..._roster.members,
          id: member.copyWith(role: role),
        },
      ),
    );
  }

  /// Removes a member and moves the vault to a new key that their phone
  /// never receives.
  Future<void> removeMember(String id) async {
    _requireOwner();
    final member = _roster.activeMember(id);
    if (member == null) return;
    if (id == memberId) throw StateError('You cannot remove yourself.');
    if (member.role == Role.owner && _ownerCount == 1) {
      throw StateError('A vault needs at least one owner.');
    }
    final updated = _roster.copyWith(
      members: {..._roster.members, id: member.copyWith(removed: true)},
    );
    await _rotateKey(updated.active);
    await _saveRoster(updated);
  }

  int get _ownerCount =>
      _roster.active.where((m) => m.role == Role.owner).length;

  Future<void> _sealCurrentKeyFor(Member member) async {
    _keyring = _keyring.withSealed(keyVersion, {
      member.id: toBase64(
        crypto.vaultKeys.sealFor(
          vaultKey: _currentKey,
          memberPublicKey: fromBase64(member.publicKey),
          vaultId: vaultId,
          keyVersion: keyVersion,
        ),
      ),
    });
    await store.writeKeyring(_keyring);
  }

  Future<void> _rotateKey(Iterable<Member> members) async {
    final oldVersion = keyVersion;
    final newVersion = oldVersion + 1;
    final newKey = crypto.vaultKeys.create();
    _keyring = _keyring.withSealed(newVersion, {
      for (final m in members)
        m.id: toBase64(
          crypto.vaultKeys.sealFor(
            vaultKey: newKey,
            memberPublicKey: fromBase64(m.publicKey),
            vaultId: vaultId,
            keyVersion: newVersion,
          ),
        ),
    });
    _keys[newVersion] = newKey;
    await store.writeKeyring(_keyring);
    // Re-encrypt every item under the new key. The removed phone keeps what
    // it already had, but can't read anything written from now on.
    for (final item in _items.values) {
      await _writeItem(item);
    }
  }

  // ---------------------------------------------------------------------------
  // Syncing

  /// Which of [remote]'s records this phone should ask for: ones it doesn't
  /// have, and ones edited elsewhere that it hasn't seen.
  List<String> wanted(Map<String, Map<String, int>> remote) => [
    for (final e in remote.entries)
      if (_wants(e.key, VersionVector(e.value))) e.key,
  ];

  bool _wants(String id, VersionVector theirs) {
    final mine = id == rosterId ? _roster.vv : _items[id]?.vv;
    if (mine == null) return true;
    final order = mine.compare(theirs);
    return order == Order.before || order == Order.concurrent;
  }

  /// The encrypted form of one record, to send to another phone.
  EncryptedItem export(String id) {
    if (id == rosterId) return _encrypt(rosterId, _roster.toJson(), _roster.vv);
    final item = _items[id];
    if (item == null) throw ArgumentError('No item $id');
    return _encrypt(id, item.toJson(), item.vv);
  }

  /// Applies a keyring and records received from another phone. Each record
  /// is decrypted and checked before anything is written.
  Future<MergeReport> applyRemote({
    Keyring? keyring,
    required List<EncryptedItem> records,
  }) async {
    final report = MergeReport();
    if (keyring != null && keyring.vaultId == vaultId) {
      final merged = _keyring.merge(keyring);
      if (merged.canonical() != _keyring.canonical()) {
        _keyring = merged;
        _keys.addAll(
          _openKeys(crypto, merged, identity, memberId)
            ..removeWhere((v, _) => _keys.containsKey(v)),
        );
        await store.writeKeyring(_keyring);
        report.keyringChanged = true;
      }
    }

    // The roster first, so roles are known when checking item edits.
    final ordered = [
      ...records.where((r) => r.itemId == rosterId),
      ...records.where((r) => r.itemId != rosterId),
    ];
    for (final record in ordered) {
      final key = _keys[record.keyVersion];
      if (record.vaultId != vaultId || key == null) {
        report.rejected++;
        continue;
      }
      final Map<String, Object?> json;
      try {
        json = crypto.items.decrypt(record, key);
      } on TwofoldCryptoException {
        report.rejected++;
        continue;
      }
      if (record.itemId == rosterId) {
        await _mergeRoster(Roster.fromJson(json), record, report);
      } else {
        await _mergeItem(VaultItem.fromJson(json), record, report);
      }
    }
    return report;
  }

  Future<void> _mergeRoster(
    Roster theirs,
    EncryptedItem record,
    MergeReport report,
  ) async {
    switch (_roster.vv.compare(theirs.vv)) {
      case Order.same || Order.after:
        return;
      case Order.before:
        _roster = theirs;
        await store.writeItem(record);
      case Order.concurrent:
        await _writeRoster(_roster.mergeWith(theirs));
    }
    report.rosterChanged = true;
  }

  Future<void> _mergeItem(
    VaultItem theirs,
    EncryptedItem record,
    MergeReport report,
  ) async {
    if (theirs.id != record.itemId) {
      report.rejected++;
      return;
    }
    // Only editors and owners may change items.
    final author = _roster.members[theirs.updatedBy];
    if (author == null || author.role == Role.viewer) {
      report.rejected++;
      return;
    }
    final mine = _items[theirs.id];
    if (mine == null) {
      _items[theirs.id] = theirs;
      await store.writeItem(record);
      report.added++;
      return;
    }
    switch (mine.vv.compare(theirs.vv)) {
      case Order.same || Order.after:
        return;
      case Order.before:
        _items[theirs.id] = theirs;
        await store.writeItem(record);
        report.updated++;
      case Order.concurrent:
        await _resolveConflict(mine, theirs);
        report.conflicts++;
    }
  }

  /// Two phones edited the same item. Every phone picks the same winner (the
  /// later edit), keeps it under the original id, and keeps the other
  /// version as a separate conflict copy so nothing is lost.
  Future<void> _resolveConflict(VaultItem a, VaultItem b) async {
    final aWins = _beats(a, b);
    final winner = aWins ? a : b;
    final loser = aWins ? b : a;
    await _writeItem(winner.copyWith(vv: a.vv.merge(b.vv)));
    if (loser.type == 'purged' || loser.deleted) return;
    final copyId = _conflictCopyId(loser);
    if (_items.containsKey(copyId)) return;
    await _writeItem(
      loser.copyWith(
        id: copyId,
        title: '${loser.title} (conflict copy)',
        pinned: false,
        vv: const VersionVector(),
      ),
    );
  }

  static bool _beats(VaultItem a, VaultItem b) {
    if (a.updatedAt != b.updatedAt) return a.updatedAt.isAfter(b.updatedAt);
    if (a.updatedBy != b.updatedBy) {
      return a.updatedBy.compareTo(b.updatedBy) > 0;
    }
    return jsonEncode(a.toJson()).compareTo(jsonEncode(b.toJson())) > 0;
  }

  String _conflictCopyId(VaultItem loser) {
    final hash = crypto.sodium.crypto.genericHash(
      message: utf8Bytes('${loser.id}|${jsonEncode(loser.vv.toJson())}'),
      outLen: 16,
    );
    return 'c-${toBase64(hash)}';
  }

  // ---------------------------------------------------------------------------
  // Internals

  SecureKey get _currentKey => _keys[keyVersion]!;

  void _requireEditor() {
    if (!myRole.canEdit) throw StateError('Viewers cannot change the vault.');
  }

  void _requireOwner() {
    if (myRole != Role.owner) {
      throw StateError('Only owners can manage the family.');
    }
  }

  EncryptedItem _encrypt(
    String id,
    Map<String, Object?> json,
    VersionVector vv,
  ) => crypto.items.encrypt(
    vaultKey: _currentKey,
    keyVersion: keyVersion,
    vaultId: vaultId,
    itemId: id,
    version: vv.total,
    item: json,
  );

  Future<void> _writeItem(VaultItem item) async {
    _items[item.id] = item;
    await store.writeItem(_encrypt(item.id, item.toJson(), item.vv));
  }

  Future<void> _saveRoster(Roster roster) =>
      _writeRoster(roster.copyWith(vv: roster.vv.bump(memberId)));

  Future<void> _writeRoster([Roster? roster]) async {
    if (roster != null) _roster = roster;
    await store.writeItem(_encrypt(rosterId, _roster.toJson(), _roster.vv));
  }
}
