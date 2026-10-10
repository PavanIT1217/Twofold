import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../services/recovery_kit.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Shows the recovery key once, offers to print or save it as a PDF, and
/// checks the user copied it down before moving on.
class RecoveryKitScreen extends StatefulWidget {
  const RecoveryKitScreen({
    super.key,
    required this.firstTime,
    this.recoveryKey,
  });

  /// True right after setup; false when a new key was made in Settings.
  final bool firstTime;
  final String? recoveryKey;

  @override
  State<RecoveryKitScreen> createState() => _RecoveryKitScreenState();
}

class _RecoveryKitScreenState extends State<RecoveryKitScreen> {
  final _check = TextEditingController();
  bool _confirmed = false;

  String get _key =>
      widget.recoveryKey ?? AppScope.read(context).pendingRecoveryKey!;
  List<String> get _groups => _key.split('-');

  @override
  void dispose() {
    _check.dispose();
    super.dispose();
  }

  Future<Uint8List> _pdf() async {
    final app = AppScope.read(context);
    return buildRecoveryKitPdf(
      name: app.myName,
      vaultName: app.vault?.roster.vaultName ?? 'Joining a vault',
      recoveryKey: _key,
      created: DateTime.now(),
    );
  }

  Future<void> _print() async {
    final app = AppScope.read(context);
    final bytes = await _pdf();
    await app.whileAway(
      () => Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'Twofold recovery kit',
      ),
    );
  }

  Future<void> _save() async {
    final app = AppScope.read(context);
    final bytes = await _pdf();
    await app.whileAway(
      () =>
          Printing.sharePdf(bytes: bytes, filename: 'twofold-recovery-kit.pdf'),
    );
  }

  void _verify(String value) {
    final cleaned = value.toUpperCase().replaceAll(RegExp(r'\s'), '');
    setState(() => _confirmed = cleaned == _groups.last);
  }

  void _done() {
    if (widget.firstTime) {
      AppScope.read(context).recoveryKitSaved();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: !widget.firstTime),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text('Your recovery kit', style: displaySerif(context)),
            const SizedBox(height: 8),
            Text(
              'If you ever forget your master password, this key is the only other way '
              'into your vault on this phone. Nobody, including us, can reset it.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Brand.ink,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Wrap(
                spacing: 14,
                runSpacing: 10,
                children: [
                  for (final g in _groups)
                    Text(
                      g,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 20,
                        letterSpacing: 2,
                        color: Brand.gold,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _print,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('Print'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.picture_as_pdf_outlined),
                    label: const Text('Save PDF'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Keep it with your property papers, in a bank locker, or with your will. '
              'Don\'t keep a photo of it on your phone.',
              style: theme.textTheme.bodyMedium,
            ),
            const SectionHeader('Check you have it'),
            TextField(
              controller: _check,
              textCapitalization: TextCapitalization.characters,
              autocorrect: false,
              onChanged: _verify,
              decoration: const InputDecoration(
                labelText: 'Type the last group of your key',
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _confirmed ? _done : null,
              child: const Text('I\'ve saved my recovery kit'),
            ),
          ],
        ),
      ),
    );
  }
}
