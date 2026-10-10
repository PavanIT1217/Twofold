import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';

/// Sets up this phone: the user's name and master password, and (when not
/// joining) a name for the new vault.
class CreateVaultScreen extends StatefulWidget {
  const CreateVaultScreen({super.key, required this.joining});

  final bool joining;

  @override
  State<CreateVaultScreen> createState() => _CreateVaultScreenState();
}

class _CreateVaultScreenState extends State<CreateVaultScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _vaultName = TextEditingController(text: 'Our vault');
  final _password = TextEditingController();
  final _confirm = TextEditingController();

  @override
  void dispose() {
    for (final c in [_name, _vaultName, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final app = AppScope.read(context);
    final navigator = Navigator.of(context);
    try {
      if (widget.joining) {
        await app.startJoining(name: _name.text, password: _password.text);
      } else {
        await app.createVault(
          name: _name.text,
          vaultName: _vaultName.text,
          password: _password.text,
        );
      }
      navigator.popUntil((r) => r.isFirst);
    } on Object catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(),
      body: SafeArea(
        child: Form(
          key: _form,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            children: [
              Text(
                widget.joining ? 'Join your family' : 'Create your vault',
                style: displaySerif(context),
              ),
              const SizedBox(height: 8),
              Text(
                widget.joining
                    ? 'First, set up this phone. Then you\'ll pair with the phone that owns the vault.'
                    : 'You\'ll be its owner. You can add your partner and family once it\'s set up.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 28),
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Your name',
                  helperText:
                      'Shown to your family, e.g. "Ravi" or "Ravi\'s phone"',
                ),
                validator: (v) =>
                    (v ?? '').trim().isEmpty ? 'Enter a name' : null,
              ),
              if (!widget.joining) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _vaultName,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Vault name'),
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? 'Enter a name' : null,
                ),
              ],
              const SizedBox(height: 16),
              PasswordField(
                controller: _password,
                validator: validateNewPassword,
                helper:
                    'This password protects the vault on this phone. We can\'t reset it, '
                    'so you\'ll get a printable recovery kit next.',
              ),
              const SizedBox(height: 16),
              PasswordField(
                controller: _confirm,
                label: 'Repeat master password',
                validator: (v) =>
                    v != _password.text ? 'The passwords don\'t match' : null,
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 28),
              BusyButton(
                label: widget.joining ? 'Set up this phone' : 'Create vault',
                onPressed: _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
