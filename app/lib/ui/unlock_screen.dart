import 'package:flutter/material.dart';

import 'app_scope.dart';
import 'theme.dart';
import 'widgets/common.dart';

class UnlockScreen extends StatefulWidget {
  const UnlockScreen({super.key});

  @override
  State<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends State<UnlockScreen> {
  final _password = TextEditingController();
  final _recovery = TextEditingController();
  bool _useRecovery = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryBiometrics());
  }

  @override
  void dispose() {
    _password.dispose();
    _recovery.dispose();
    super.dispose();
  }

  Future<void> _tryBiometrics() async {
    final app = AppScope.read(context);
    if (!app.settings.biometrics) return;
    try {
      await app.unlockWithBiometrics();
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  Future<void> _unlock() async {
    final app = AppScope.read(context);
    try {
      if (_useRecovery) {
        await app.unlockWithRecoveryKey(_recovery.text);
      } else {
        await app.unlockWithPassword(_password.text);
      }
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(24),
            children: [
              const Icon(Icons.lock_outline, size: 44, color: Brand.navy),
              const SizedBox(height: 16),
              Text(
                'Welcome back, ${app.myName}',
                style: displaySerif(context, size: 30),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              if (_useRecovery)
                TextField(
                  controller: _recovery,
                  autofocus: true,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  maxLines: 3,
                  minLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Recovery key',
                    helperText: 'From your printed recovery kit. Dashes and spaces are optional.',
                  ),
                )
              else
                PasswordField(
                  controller: _password,
                  autofocus: !app.settings.biometrics,
                  onSubmitted: (_) => _unlock(),
                ),
              const SizedBox(height: 20),
              BusyButton(
                label: 'Unlock',
                icon: Icons.lock_open,
                onPressed: _unlock,
              ),
              if (app.settings.biometrics && !_useRecovery) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _tryBiometrics,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('Use fingerprint or face'),
                ),
              ],
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => _useRecovery = !_useRecovery),
                child: Text(
                  _useRecovery
                      ? 'Use master password instead'
                      : 'Forgot password? Use recovery key',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
