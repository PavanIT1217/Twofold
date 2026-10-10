import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Puts a backup back on this phone, from Google Drive or a backup file.
/// After that the user unlocks with the master password or recovery key.
class RestoreScreen extends StatelessWidget {
  const RestoreScreen({super.key});

  Future<void> _fromDrive(BuildContext context) async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    try {
      final bytes = await app.downloadDriveBackup();
      if (bytes == null) {
        if (context.mounted) {
          showMessage(
            context,
            'No Twofold backup found in that Google account.',
          );
        }
        return;
      }
      await app.restoreBackup(bytes);
      navigator.popUntil((r) => r.isFirst);
    } on Object catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  Future<void> _fromFile(BuildContext context) async {
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    try {
      final file = await app.whileAway(
        () => openFile(
          acceptedTypeGroups: const [
            XTypeGroup(
              label: 'Twofold backup',
              extensions: ['json'],
              mimeTypes: ['application/json'],
            ),
          ],
        ),
      );
      if (file == null) return;
      await app.restoreBackup(await file.readAsBytes());
      navigator.popUntil((r) => r.isFirst);
    } on Object catch (e) {
      if (context.mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text('Restore a backup', style: displaySerif(context)),
            const SizedBox(height: 8),
            Text(
              'Your backup is encrypted. After restoring, unlock it with your master password '
              'or the recovery key from your printed kit.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 28),
            BusyButton(
              label: 'From Google Drive',
              icon: Icons.cloud_download_outlined,
              onPressed: () => _fromDrive(context),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => _fromFile(context),
              icon: const Icon(Icons.file_open_outlined),
              label: const Text('From a backup file'),
            ),
            const SizedBox(height: 24),
            Text(
              'Lost your phone but your partner still has theirs? You can also set this phone up '
              'fresh with "Join my family\'s vault" and pair again.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}
