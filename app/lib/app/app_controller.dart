import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backup/backup_bundle.dart';
import '../backup/drive_backup.dart';
import '../core/crypto/twofold_crypto.dart';
import '../data/models.dart';
import '../data/vault.dart';
import '../data/vault_store.dart';
import '../services/biometric_unlock.dart';
import '../services/clipboard_guard.dart';
import '../services/reminders.dart';
import '../sync/lan_sync.dart';
import '../sync/pairing.dart';
import '../sync/sync_session.dart';

enum AppStage {
  /// Reading the phone's storage.
  loading,

  /// Nothing set up yet.
  welcome,

  /// Set up, waiting for the master password or fingerprint.
  locked,

  /// Unlocked, but this phone is still joining a vault.
  joining,

  /// Unlocked with the vault open.
  open,
}

/// Settings stored on this phone (never synced, nothing secret).
class AppSettings {
  const AppSettings({
    this.autoLockSeconds = 60,
    this.biometrics = false,
    this.driveBackup = false,
    this.lastBackupAt,
  });

  factory AppSettings.fromJson(Map<String, Object?> json) => AppSettings(
    autoLockSeconds: json['autoLockSeconds'] as int? ?? 60,
    biometrics: json['biometrics'] as bool? ?? false,
    driveBackup: json['driveBackup'] as bool? ?? false,
    lastBackupAt: json['lastBackupAt'] == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(json['lastBackupAt']! as int),
  );

  final int autoLockSeconds;
  final bool biometrics;
  final bool driveBackup;
  final DateTime? lastBackupAt;

  AppSettings copyWith({
    int? autoLockSeconds,
    bool? biometrics,
    bool? driveBackup,
    DateTime? lastBackupAt,
  }) => AppSettings(
    autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
    biometrics: biometrics ?? this.biometrics,
    driveBackup: driveBackup ?? this.driveBackup,
    lastBackupAt: lastBackupAt ?? this.lastBackupAt,
  );

  Map<String, Object?> toJson() => {
    'autoLockSeconds': autoLockSeconds,
    'biometrics': biometrics,
    'driveBackup': driveBackup,
    if (lastBackupAt != null)
      'lastBackupAt': lastBackupAt!.millisecondsSinceEpoch,
  };
}

/// The app's state: who this phone is, whether it's unlocked, the open
/// vault, and the background services around it.
class AppController extends ChangeNotifier {
  AppController({
    required this.crypto,
    required this.store,
    BiometricUnlock? biometrics,
    ReminderScheduler? reminders,
    DriveBackup? drive,
    this.enableLan = true,
  }) : biometrics = biometrics ?? BiometricUnlock(),
       reminders = reminders ?? ReminderScheduler(),
       drive = drive ?? DriveBackup();

  final TwofoldCrypto crypto;
  final VaultStore store;
  final BiometricUnlock biometrics;
  final ReminderScheduler reminders;
  final DriveBackup drive;
  final ClipboardGuard clipboard = ClipboardGuard();

  /// Off in tests, which have no network plugins.
  final bool enableLan;

  AppStage stage = AppStage.loading;
  AppSettings settings = const AppSettings();
  IdentityRecord? identityRecord;
  Identity? _identity;
  Vault? vault;
  LanSync? _lan;

  /// Shown once, right after setup, so it can be printed.
  String? pendingRecoveryKey;

  int _awayTasks = 0;

  /// True while Twofold has sent the user to another screen on purpose
  /// (camera, photo picker, file picker, share or print sheet), so leaving
  /// the app doesn't trigger auto-lock.
  bool get awayOnPurpose => _awayTasks > 0;

  /// Runs [task], which opens another app's screen, without auto-locking.
  Future<T> whileAway<T>(Future<T> Function() task) async {
    _awayTasks++;
    try {
      return await task();
    } finally {
      // Let the app become visible again before auto-lock is re-armed.
      Future<void>.delayed(const Duration(seconds: 1), () => _awayTasks--);
    }
  }

  DateTime? lastSyncAt;
  String? lastSyncError;
  bool syncing = false;
  bool backingUp = false;
  String? lastBackupError;

  String get myName => identityRecord?.name ?? '';
  String get memberId => identityRecord!.memberId;
  Iterable<NearbyPeer> get nearby => _lan?.nearby ?? const [];
  int? get lanPort => _lan?.port;

  Future<void> init() async {
    identityRecord = await store.readIdentity();
    settings = AppSettings.fromJson(await store.readSettings());
    stage = identityRecord == null ? AppStage.welcome : AppStage.locked;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Setting up

  Future<IdentityRecord> _createIdentity(String name, String password) async {
    final recoveryKey = crypto.recoveryKeys.generate();
    final created = crypto.identities.create(
      password: password,
      recoveryKey: recoveryKey,
    );
    pendingRecoveryKey = crypto.recoveryKeys.format(recoveryKey);
    recoveryKey.dispose();
    final record = IdentityRecord(
      memberId: Vault.newId(),
      name: name.trim(),
      locked: created.locked,
    );
    await store.writeIdentity(record);
    identityRecord = record;
    _identity = created.identity;
    return record;
  }

  /// Sets this phone up as the owner of a new vault.
  Future<void> createVault({
    required String name,
    required String vaultName,
    required String password,
  }) async {
    final record = await _createIdentity(name, password);
    vault = await Vault.create(
      crypto: crypto,
      store: store,
      identity: _identity!,
      memberId: record.memberId,
      memberName: record.name,
      vaultName: vaultName.trim(),
    );
    await _afterUnlock();
  }

  /// Sets this phone up to join someone else's vault.
  Future<void> startJoining({
    required String name,
    required String password,
  }) async {
    await _createIdentity(name, password);
    await _afterUnlock();
  }

  void recoveryKitSaved() {
    pendingRecoveryKey = null;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Locking and unlocking

  Future<void> unlockWithPassword(String password) async {
    _identity = crypto.identities.unlockWithPassword(
      identityRecord!.locked,
      password,
    );
    await _afterUnlock();
  }

  Future<void> unlockWithRecoveryKey(String text) async {
    final key = crypto.recoveryKeys.parse(text);
    try {
      _identity = crypto.identities.unlockWithRecoveryKey(
        identityRecord!.locked,
        key,
      );
    } finally {
      key.dispose();
    }
    await _afterUnlock();
  }

  /// Returns false if the user cancelled the fingerprint prompt.
  Future<bool> unlockWithBiometrics() async {
    final secret = await biometrics.read();
    if (secret == null) return false;
    try {
      _identity = crypto.identities.fromSecretKey(
        identityRecord!.locked,
        secret,
      );
    } on TwofoldCryptoException {
      await setBiometrics(false);
      return false;
    }
    await _afterUnlock();
    return true;
  }

  Future<void> _afterUnlock() async {
    vault ??= await Vault.open(
      crypto: crypto,
      store: store,
      identity: _identity!,
      memberId: identityRecord!.memberId,
    );
    stage = vault == null ? AppStage.joining : AppStage.open;
    notifyListeners();
    await _startLan();
    if (vault != null) {
      unawaited(_afterVaultChange());
      if (vault!.myRole.canEdit) unawaited(vault!.emptyOldTrash());
      unawaited(vault!.deleteUnreferencedFiles());
      unawaited(_autoBackup());
    }
  }

  void lock() {
    if (stage != AppStage.open && stage != AppStage.joining) return;
    unawaited(_lan?.stop());
    _lan = null;
    vault?.close();
    vault = null;
    _identity?.dispose();
    _identity = null;
    unawaited(clipboard.clear());
    stage = AppStage.locked;
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Settings

  Future<void> _saveSettings(AppSettings next) async {
    settings = next;
    await store.writeSettings(next.toJson());
    notifyListeners();
  }

  Future<void> setAutoLock(int seconds) =>
      _saveSettings(settings.copyWith(autoLockSeconds: seconds));

  Future<bool> biometricsAvailable() => biometrics.available;

  Future<void> setBiometrics(bool on) async {
    if (on) {
      await biometrics.enable(_identity!.secretKey.extractBytes());
    } else {
      await biometrics.disable();
    }
    await _saveSettings(settings.copyWith(biometrics: on));
  }

  Future<void> changePassword(String current, String next) async {
    // Re-check the current password before replacing it.
    crypto.identities
        .unlockWithPassword(identityRecord!.locked, current)
        .dispose();
    final locked = crypto.identities.changePassword(
      identityRecord!.locked,
      _identity!,
      newPassword: next,
    );
    identityRecord = identityRecord!.withLocked(locked);
    await store.writeIdentity(identityRecord!);
    notifyListeners();
  }

  /// Makes a new recovery key; the old printed kit stops working.
  Future<String> newRecoveryKey() async {
    final key = crypto.recoveryKeys.generate();
    final locked = crypto.identities.replaceRecoveryKey(
      identityRecord!.locked,
      _identity!,
      key,
    );
    final text = crypto.recoveryKeys.format(key);
    key.dispose();
    identityRecord = identityRecord!.withLocked(locked);
    await store.writeIdentity(identityRecord!);
    notifyListeners();
    return text;
  }

  // ---------------------------------------------------------------------------
  // Items (thin wrappers so the UI refreshes)

  Future<VaultItem> saveItem(VaultItem item) async {
    final saved = await vault!.save(item);
    await _afterVaultChange();
    _syncSoon();
    return saved;
  }

  Future<void> trashItem(String id) async {
    await vault!.moveToTrash(id);
    await _afterVaultChange();
    _syncSoon();
  }

  Future<void> restoreItem(String id) async {
    await vault!.restore(id);
    await _afterVaultChange();
    _syncSoon();
  }

  Future<void> purgeItem(String id) async {
    await vault!.purge(id);
    await _afterVaultChange();
    _syncSoon();
  }

  Future<Attachment> addAttachment(Uint8List bytes, String name, String mime) =>
      vault!.addAttachment(bytes: bytes, name: name, mime: mime);

  Future<Uint8List?> readAttachment(Attachment a) => vault!.readAttachment(a);

  Future<void> _afterVaultChange() async {
    notifyListeners();
    if (vault != null) await reminders.reschedule(vault!.items);
  }

  // ---------------------------------------------------------------------------
  // Family and sync

  Future<PairingCode> myPairingCode() async => PairingCode(
    memberId: identityRecord!.memberId,
    name: myName,
    publicKey: identityRecord!.locked.publicKey,
    addresses: enableLan ? await localAddresses() : const [],
    port: _lan?.port,
    vaultName: vault?.roster.vaultName,
  );

  /// The numbers both phones show while pairing.
  List<String> pairNumber(PairingCode other) => crypto.fingerprints.forPair(
    identityRecord!.locked.publicKey,
    other.publicKey,
  );

  /// Owner: adds the phone whose code was scanned.
  Future<void> addMember(PairingCode code, Role role) async {
    await vault!.addMember(
      id: code.memberId,
      name: code.name,
      publicKey: code.publicKey,
      role: role,
    );
    notifyListeners();
  }

  Future<void> changeRole(String memberId, Role role) async {
    await vault!.changeRole(memberId, role);
    notifyListeners();
    _syncSoon();
  }

  Future<void> removeMember(String memberId) async {
    await vault!.removeMember(memberId);
    notifyListeners();
    _syncSoon();
  }

  Future<void> renameVault(String name) async {
    await vault!.renameVault(name);
    notifyListeners();
    _syncSoon();
  }

  /// Joining phone: trusts the scanned owner's phone and fetches the vault.
  Future<void> joinFrom(PairingCode owner) async {
    await _lan!.trust(owner.memberId, owner.publicKey);
    if (owner.port == null || owner.addresses.isEmpty) {
      throw StateError(
        'That code has no Wi-Fi address. Make sure both phones are on the same Wi-Fi.',
      );
    }
    Object? lastError;
    for (final address in owner.addresses) {
      try {
        await _lan!.syncWith(
          address,
          owner.port!,
          expectedPeer: owner.memberId,
        );
        lastError = null;
        break;
      } on Object catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    vault = await Vault.open(
      crypto: crypto,
      store: store,
      identity: _identity!,
      memberId: identityRecord!.memberId,
    );
    if (vault == null) {
      throw StateError(
        'Connected, but you haven\'t been added yet. Ask the owner to scan your code first.',
      );
    }
    stage = AppStage.open;
    notifyListeners();
    // Restart Wi-Fi sync so it announces the vault it now belongs to.
    await _lan!.stop();
    _lan = null;
    await _startLan();
    await _afterVaultChange();
  }

  Future<void> syncNow() async {
    if (_lan == null || syncing) return;
    syncing = true;
    lastSyncError = null;
    notifyListeners();
    try {
      final results = await _lan!.syncAll();
      if (results.isNotEmpty) lastSyncAt = DateTime.now();
    } on Object catch (e) {
      lastSyncError = '$e';
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  Timer? _syncTimer;

  void _syncSoon() {
    _syncTimer?.cancel();
    _syncTimer = Timer(const Duration(seconds: 3), syncNow);
  }

  Future<void> _startLan() async {
    if (!enableLan || _lan != null || _identity == null) return;
    _lan = LanSync(
      crypto: crypto,
      store: store,
      identity: _identity!,
      memberId: identityRecord!.memberId,
      vault: () => vault,
      onSynced: _onSynced,
      onError: (e) {
        lastSyncError = '$e';
        notifyListeners();
      },
    );
    try {
      await _lan!.start();
    } on Object catch (e) {
      lastSyncError = 'Wi-Fi sync is unavailable: $e';
      notifyListeners();
    }
  }

  void _onSynced(SyncResult result) {
    lastSyncAt = DateTime.now();
    if (result.report?.changedAnything ?? false) {
      unawaited(_afterVaultChange());
    } else {
      notifyListeners();
    }
  }

  // ---------------------------------------------------------------------------
  // Backup and restore

  Future<Uint8List> backupBytes() async =>
      (await BackupBundle.collect(vault!, store)).encode();

  Future<void> setDriveBackup(bool on) async {
    if (on) {
      await drive.connect();
      await _saveSettings(settings.copyWith(driveBackup: true));
      await backupNow();
    } else {
      await drive.disconnect();
      await _saveSettings(settings.copyWith(driveBackup: false));
    }
  }

  Future<void> backupNow({bool interactive = true}) async {
    if (vault == null || backingUp) return;
    backingUp = true;
    lastBackupError = null;
    notifyListeners();
    try {
      await drive.upload(await backupBytes(), interactive: interactive);
      await _saveSettings(settings.copyWith(lastBackupAt: DateTime.now()));
    } on Object catch (e) {
      lastBackupError = '$e';
    } finally {
      backingUp = false;
      notifyListeners();
    }
  }

  /// Backs up once a day while the app is used.
  Future<void> _autoBackup() async {
    if (!settings.driveBackup) return;
    final last = settings.lastBackupAt;
    if (last != null &&
        DateTime.now().difference(last) < const Duration(hours: 20)) {
      return;
    }
    await backupNow(interactive: false);
  }

  /// Restores a backup onto this phone. Afterwards the user unlocks with the
  /// master password or recovery key from that backup.
  Future<void> restoreBackup(Uint8List bytes) async {
    final bundle = BackupBundle.decode(bytes);
    await bundle.restoreInto(store);
    identityRecord = bundle.identity;
    stage = AppStage.locked;
    notifyListeners();
  }

  Future<Uint8List?> downloadDriveBackup() => drive.download();

  /// Removes everything Twofold stored on this phone.
  Future<void> deleteEverything() async {
    lock();
    await biometrics.disable();
    await reminders.reschedule(const []);
    await store.deleteAll();
    identityRecord = null;
    settings = const AppSettings();
    stage = AppStage.welcome;
    notifyListeners();
  }
}
