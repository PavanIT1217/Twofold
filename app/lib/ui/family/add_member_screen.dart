import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../sync/pairing.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'pairing_widgets.dart';

/// Owner side of pairing: scan the new phone, compare numbers, choose a
/// role, then let the new phone scan this one.
class AddMemberScreen extends StatefulWidget {
  const AddMemberScreen({super.key});

  @override
  State<AddMemberScreen> createState() => _AddMemberScreenState();
}

class _AddMemberScreenState extends State<AddMemberScreen> {
  PairingCode? _scanned;
  Role _role = Role.editor;
  bool _added = false;

  Future<void> _scan() async {
    final code = await scanPairingCode(context);
    if (code == null || !mounted) return;
    final app = AppScope.read(context);
    if (code.memberId == app.memberId) {
      showMessage(context, 'That\'s this phone\'s own code.');
      return;
    }
    if (code.vaultName != null) {
      showMessage(
        context,
        'That phone already has a vault. On the new phone, choose "Join my family\'s vault".',
      );
      return;
    }
    setState(() => _scanned = code);
  }

  Future<void> _add() async {
    try {
      await AppScope.read(context).addMember(_scanned!, _role);
      setState(() => _added = true);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final scanned = _scanned;
    return Scaffold(
      appBar: AppBar(title: const Text('Add a family member')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text('Pair in person', style: displaySerif(context)),
          const SizedBox(height: 8),
          const Text(
            'Be together, on the same Wi-Fi. On their phone, install Twofold and choose '
            '"Join my family\'s vault". It will show a code.',
          ),
          const SectionHeader('Step 1 · Scan their phone'),
          if (scanned == null)
            FilledButton.icon(
              onPressed: _scan,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Scan their code'),
            )
          else if (!_added) ...[
            Text(
              'Adding ${scanned.name}. Check this number matches the one on their screen once they scan you:',
            ),
            const SizedBox(height: 12),
            PairNumberView(groups: app.pairNumber(scanned)),
            const SectionHeader('Their role'),
            RadioGroup<Role>(
              groupValue: _role,
              onChanged: (r) => setState(() => _role = r!),
              child: Column(
                children: [
                  for (final role in Role.values)
                    RadioListTile<Role>(
                      contentPadding: EdgeInsets.zero,
                      value: role,
                      title: Text(role.label),
                      subtitle: Text(role.description),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            FilledButton(onPressed: _add, child: Text('Add ${scanned.name}')),
            TextButton(
              onPressed: () => setState(() => _scanned = null),
              child: const Text('Scan again'),
            ),
          ] else ...[
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle, color: Colors.green),
              title: Text(
                '${scanned.name} added as ${_role.label.toLowerCase()}',
              ),
            ),
            const SectionHeader('Step 2 · They scan you'),
            const Text(
              'On their phone, tap "Scan their code" and point it here. Keep this screen open until they\'re in.',
            ),
            const SizedBox(height: 12),
            const MyCodeCard(caption: 'This phone\'s Twofold code'),
            const SizedBox(height: 12),
            PairNumberView(groups: app.pairNumber(scanned)),
            const SizedBox(height: 8),
            const Text(
              'Both phones should show this same number.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Done'),
            ),
          ],
        ],
      ),
    );
  }
}
