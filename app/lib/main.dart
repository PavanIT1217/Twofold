import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'app/app_controller.dart';
import 'core/crypto/twofold_crypto.dart';
import 'data/vault_store.dart';
import 'services/screen_guard.dart';
import 'ui/app_scope.dart';
import 'ui/root.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ScreenGuard().enable();
  final crypto = await TwofoldCrypto.init();
  final support = await getApplicationSupportDirectory();
  final controller = AppController(
    crypto: crypto,
    store: VaultStore(Directory(p.join(support.path, 'twofold'))),
  );
  runApp(TwofoldApp(controller: controller));
  await controller.init();
}

class TwofoldApp extends StatelessWidget {
  const TwofoldApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return AppScope(
      controller: controller,
      child: MaterialApp(
        title: 'Twofold',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(Brightness.light),
        darkTheme: buildTheme(Brightness.dark),
        home: const Root(),
      ),
    );
  }
}
