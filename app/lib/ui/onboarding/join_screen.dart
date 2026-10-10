import 'package:flutter/material.dart';

import '../../sync/pairing.dart';
import '../app_scope.dart';
import '../family/pairing_widgets.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// A set-up phone that hasn't got the vault yet: pair with the owner's
/// phone in two scans, then fetch the vault over Wi-Fi.
class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  PairingCode? _owner;
  bool _connecting = false;

  Future<void> _scan() async {
    final code = await scanPairingCode(context);
    if (code == null || !mounted) return;
    if (code.vaultName == null) {
      showMessage(
        context,
        'That phone hasn\'t got a vault yet. Scan the owner\'s code from Family → Add member.',
      );
      return;
    }
    setState(() => _owner = code);
  }

  Future<void> _connect() async {
    setState(() => _connecting = true);
    try {
      await AppScope.read(context).joinFrom(_owner!);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final owner = _owner;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            tooltip: 'Lock',
            icon: const Icon(Icons.lock_outline),
            onPressed: app.lock,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
          children: [
            Text('Pair with your family', style: displaySerif(context)),
            const SizedBox(height: 8),
            const Text(
              'Be together, on the same Wi-Fi, with the phone that owns the vault.',
            ),
            const SectionHeader('Step 1 · They scan you'),
            const Text(
              'On their phone: Family → Add member → Scan. Point it at this code.',
            ),
            const SizedBox(height: 12),
            const MyCodeCard(caption: 'This phone\'s Twofold code'),
            const SectionHeader('Step 2 · You scan them'),
            if (owner == null) ...[
              const Text(
                'Once they\'ve added you, their phone shows its own code. Scan it here.',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.qr_code_scanner),
                label: const Text('Scan their code'),
              ),
            ] else ...[
              Text(
                'Joining "${owner.vaultName}" from ${owner.name}. Check this number matches the one on their screen:',
              ),
              const SizedBox(height: 12),
              PairNumberView(groups: app.pairNumber(owner)),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _connecting ? null : _connect,
                icon: _connecting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi),
                label: Text(
                  _connecting
                      ? 'Fetching the vault…'
                      : 'The numbers match – join',
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _owner = null),
                child: const Text('Scan again'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
