import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models.dart';
import '../app_scope.dart';
import '../onboarding/recovery_kit_screen.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'trash_screen.dart';

class SettingsTab extends StatelessWidget {
  const SettingsTab({super.key});

  static const _lockChoices = {
    0: 'Immediately',
    30: 'After 30 seconds',
    60: 'After 1 minute',
    300: 'After 5 minutes',
    900: 'After 15 minutes',
  };

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final vault = app.vault!;
    final s = app.settings;
    return Scaffold(
      appBar: AppBar(
        title: Text('Settings', style: displaySerif(context, size: 26)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 40),
        children: [
          const SectionHeader('Security'),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Lock when I leave the app'),
                  subtitle: Text(
                    _lockChoices[s.autoLockSeconds] ??
                        '${s.autoLockSeconds} seconds',
                  ),
                  onTap: () => _pickAutoLock(context),
                ),
                FutureBuilder<bool>(
                  future: app.biometricsAvailable(),
                  builder: (context, snap) => SwitchListTile(
                    secondary: const Icon(Icons.fingerprint),
                    title: const Text('Unlock with fingerprint or face'),
                    subtitle: Text(
                      snap.data == false
                          ? 'Not set up on this phone'
                          : 'Your master password still works too',
                    ),
                    value: s.biometrics,
                    onChanged: snap.data == true
                        ? (on) async {
                            try {
                              await app.setBiometrics(on);
                            } on Object catch (e) {
                              if (context.mounted) showError(context, e);
                            }
                          }
                        : null,
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.password),
                  title: const Text('Change master password'),
                  onTap: () => _changePassword(context),
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('Make a new recovery kit'),
                  subtitle: const Text('Your old printed kit stops working'),
                  onTap: () => _newRecoveryKit(context),
                ),
              ],
            ),
          ),
          const SectionHeader('Backup'),
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: const Icon(Icons.cloud_outlined),
                  title: const Text('Back up to my Google Drive'),
                  subtitle: Text(
                    s.driveBackup
                        ? (s.lastBackupAt == null
                              ? 'Not backed up yet'
                              : 'Last backup ${timeAgo(s.lastBackupAt!)}')
                        : 'Encrypted, in a private app folder only Twofold can see',
                  ),
                  value: s.driveBackup,
                  onChanged: (on) async {
                    try {
                      await app.setDriveBackup(on);
                    } on Object catch (e) {
                      if (context.mounted) showError(context, e);
                    }
                  },
                ),
                if (s.driveBackup)
                  ListTile(
                    leading: app.backingUp
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.backup_outlined),
                    title: const Text('Back up now'),
                    subtitle: app.lastBackupError == null
                        ? null
                        : Text(
                            app.lastBackupError!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                    onTap: app.backingUp ? null : () => app.backupNow(),
                  ),
                ListTile(
                  leading: const Icon(Icons.save_alt),
                  title: const Text('Save a backup file'),
                  subtitle: const Text(
                    'Encrypted. Keep it somewhere safe, like a USB drive.',
                  ),
                  onTap: () => _exportBackup(context),
                ),
              ],
            ),
          ),
          const SectionHeader('Vault'),
          Card(
            child: Column(
              children: [
                if (vault.myRole == Role.owner)
                  ListTile(
                    leading: const Icon(Icons.drive_file_rename_outline),
                    title: const Text('Rename vault'),
                    subtitle: Text(vault.roster.vaultName),
                    onTap: () => _rename(context),
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline),
                  title: const Text('Trash'),
                  subtitle: Text(
                    '${vault.trash.length} ${vault.trash.length == 1 ? 'item' : 'items'} · emptied after 30 days',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const TrashScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('About'),
          Card(
            child: Column(
              children: [
                const ListTile(
                  leading: Icon(Icons.public),
                  title: Text('twofold.webappslab.com'),
                  subtitle: Text(
                    'How Twofold works, privacy policy and support',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.description_outlined),
                  title: const Text('Open-source licences'),
                  onTap: () => showLicensePage(
                    context: context,
                    applicationName: 'Twofold',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => _deleteEverything(context),
            child: const Text('Remove Twofold from this phone'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickAutoLock(BuildContext context) async {
    final app = AppScope.read(context);
    final picked = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Lock when I leave the app'),
        children: [
          RadioGroup<int>(
            groupValue: app.settings.autoLockSeconds,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(
              children: [
                for (final e in _lockChoices.entries)
                  RadioListTile<int>(value: e.key, title: Text(e.value)),
              ],
            ),
          ),
        ],
      ),
    );
    if (picked != null) await app.setAutoLock(picked);
  }

  Future<void> _changePassword(BuildContext context) async {
    final app = AppScope.read(context);
    final current = TextEditingController();
    final next = TextEditingController();
    final form = GlobalKey<FormState>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change master password'),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PasswordField(controller: current, label: 'Current password'),
              const SizedBox(height: 12),
              PasswordField(
                controller: next,
                label: 'New password',
                validator: validateNewPassword,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (form.currentState!.validate()) Navigator.pop(context, true);
            },
            child: const Text('Change'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await app.changePassword(current.text, next.text);
      if (context.mounted) showMessage(context, 'Master password changed.');
    } on Object catch (e) {
      if (context.mounted) showError(context, e);
    } finally {
      current.dispose();
      next.dispose();
    }
  }

  Future<void> _newRecoveryKit(BuildContext context) async {
    final app = AppScope.read(context);
    final ok = await confirm(
      context,
      title: 'Make a new recovery kit?',
      message: 'Your old printed recovery key will stop working. Print the new one before you leave the next screen.',
      action: 'Make new kit',
    );
    if (!ok || !context.mounted) return;
    final key = await app.newRecoveryKey();
    if (context.mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => RecoveryKitScreen(firstTime: false, recoveryKey: key),
        ),
      );
    }
  }

  Future<void> _exportBackup(BuildContext context) async {
    final app = AppScope.read(context);
    try {
      final bytes = await app.backupBytes();
      final now = DateTime.now();
      final name =
          'twofold-backup-${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}.json';
      await app.whileAway(
        () => SharePlus.instance.share(
          ShareParams(
            files: [
              XFile.fromData(bytes, mimeType: 'application/json', name: name),
            ],
            fileNameOverrides: [name],
          ),
        ),
      );
    } on Object catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _rename(BuildContext context) async {
    final app = AppScope.read(context);
    final controller = TextEditingController(text: app.vault!.roster.vaultName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename vault'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name != null && name.isNotEmpty) await app.renameVault(name);
  }

  Future<void> _deleteEverything(BuildContext context) async {
    final app = AppScope.read(context);
    final ok = await confirm(
      context,
      title: 'Remove Twofold from this phone?',
      message:
          'This deletes the vault, your keys and settings from this phone. Other family phones keep their copy. '
          'Without a backup or another paired phone, this can\'t be undone.',
      action: 'Remove everything',
      destructive: true,
    );
    if (ok) await app.deleteEverything();
  }
}
