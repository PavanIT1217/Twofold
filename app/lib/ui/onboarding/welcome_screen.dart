import 'package:flutter/material.dart';

import '../theme.dart';
import 'create_vault_screen.dart';
import 'restore_screen.dart';

class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Brand.ink,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - 48,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 32),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Brand.gold,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: const Icon(
                          Icons.lock_outline,
                          color: Brand.ink,
                          size: 30,
                        ),
                      ),
                      const SizedBox(height: 32),
                      Text(
                        'Fold it away.',
                        style: displaySerif(
                          context,
                          size: 44,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Together.',
                        style: displaySerif(
                          context,
                          size: 44,
                          color: Brand.gold,
                        ).copyWith(fontStyle: FontStyle.italic),
                      ),
                      const SizedBox(height: 20),
                      const Text(
                        'Passwords, policies, property papers and "who do I call" notes, '
                        'encrypted on this phone and shared only with the family you pair with.',
                        style: TextStyle(
                          color: Color(0xFFB7C1D6),
                          fontSize: 17,
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: Brand.gold,
                          foregroundColor: Brand.ink,
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const CreateVaultScreen(joining: false),
                          ),
                        ),
                        child: const Text('Create a family vault'),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Color(0x55FFFFFF)),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                const CreateVaultScreen(joining: true),
                          ),
                        ),
                        child: const Text('Join my family\'s vault'),
                      ),
                      const SizedBox(height: 4),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB7C1D6),
                        ),
                        onPressed: () => Navigator.push(
                          context,
                          MaterialPageRoute<void>(
                            builder: (_) => const RestoreScreen(),
                          ),
                        ),
                        child: const Text('Restore from a backup'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
