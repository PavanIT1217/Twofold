import 'package:flutter/material.dart';

import 'core/crypto/twofold_crypto.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final crypto = await TwofoldCrypto.init();
  runApp(TwofoldApp(crypto: crypto));
}

class TwofoldApp extends StatelessWidget {
  const TwofoldApp({super.key, required this.crypto});

  final TwofoldCrypto crypto;

  static const _brand = Color(0xFF1F3A5F);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Twofold',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: _brand),
        scaffoldBackgroundColor: const Color(0xFFFBF8F2),
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: _brand,
          brightness: Brightness.dark,
        ),
      ),
      home: const WelcomeScreen(),
    );
  }
}

/// Placeholder until onboarding (milestone 2) lands.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.lock_outline,
                size: 48,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(height: 24),
              Text('Twofold', style: theme.textTheme.displaySmall),
              const SizedBox(height: 12),
              Text(
                'Your family vault. Encrypted on your phone, shared only with '
                'the people you pair with.',
                style: theme.textTheme.titleMedium,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
