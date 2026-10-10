import 'package:flutter/material.dart';

import '../../core/crypto/errors.dart';

/// A password field with a show/hide toggle.
class PasswordField extends StatefulWidget {
  const PasswordField({
    super.key,
    required this.controller,
    this.label = 'Master password',
    this.autofocus = false,
    this.onSubmitted,
    this.validator,
    this.helper,
  });

  final TextEditingController controller;
  final String label;
  final bool autofocus;
  final ValueChanged<String>? onSubmitted;
  final FormFieldValidator<String>? validator;
  final String? helper;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _hidden = true;

  @override
  Widget build(BuildContext context) => TextFormField(
    controller: widget.controller,
    obscureText: _hidden,
    autofocus: widget.autofocus,
    autocorrect: false,
    enableSuggestions: false,
    keyboardType: TextInputType.visiblePassword,
    onFieldSubmitted: widget.onSubmitted,
    validator: widget.validator,
    decoration: InputDecoration(
      labelText: widget.label,
      helperText: widget.helper,
      helperMaxLines: 3,
      suffixIcon: IconButton(
        tooltip: _hidden ? 'Show' : 'Hide',
        icon: Icon(
          _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
        ),
        onPressed: () => setState(() => _hidden = !_hidden),
      ),
    ),
  );
}

/// Checks a new master password: long enough to resist guessing.
String? validateNewPassword(String? value) {
  final v = value ?? '';
  if (v.length < 10) {
    return 'Use at least 10 characters. A short sentence works well.';
  }
  if (RegExp(r'^(.)\1*$').hasMatch(v)) {
    return 'Pick something less predictable.';
  }
  return null;
}

/// A button that shows a spinner while [onPressed] runs.
class BusyButton extends StatefulWidget {
  const BusyButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
  });

  final String label;
  final Future<void> Function()? onPressed;
  final IconData? icon;

  @override
  State<BusyButton> createState() => _BusyButtonState();
}

class _BusyButtonState extends State<BusyButton> {
  bool _busy = false;

  Future<void> _run() async {
    setState(() => _busy = true);
    // Let the spinner paint before slow work (key derivation) starts.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      await widget.onPressed!();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => FilledButton.icon(
    onPressed: widget.onPressed == null || _busy ? null : _run,
    icon: _busy
        ? const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : Icon(widget.icon ?? Icons.arrow_forward),
    label: Text(widget.label),
  );
}

/// A small heading above a group of settings or fields.
class SectionHeader extends StatelessWidget {
  const SectionHeader(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.secondary,
      ),
    ),
  );
}

/// Shows an error in a snack bar with a readable message.
void showError(BuildContext context, Object error) {
  final message = switch (error) {
    TwofoldCryptoException(:final message) => message,
    StateError(:final message) => message,
    _ => '$error',
  };
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

void showMessage(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<bool> confirm(
  BuildContext context, {
  required String title,
  required String message,
  required String action,
  bool destructive = false,
}) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: destructive
                ? FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  )
                : null,
            onPressed: () => Navigator.pop(context, true),
            child: Text(action),
          ),
        ],
      ),
    ) ??
    false;

/// Formats a date as e.g. "15 Mar 2027".
String formatDate(DateTime d) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String timeAgo(DateTime t, [DateTime? now]) {
  final d = (now ?? DateTime.now()).difference(t);
  if (d.inMinutes < 1) return 'just now';
  if (d.inHours < 1) return '${d.inMinutes} min ago';
  if (d.inDays < 1) return '${d.inHours} h ago';
  if (d.inDays < 30) return '${d.inDays} days ago';
  return formatDate(t);
}
