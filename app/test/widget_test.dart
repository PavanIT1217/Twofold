import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/app/app_controller.dart';
import 'package:twofold/core/crypto/twofold_crypto.dart';
import 'package:twofold/data/vault_store.dart';
import 'package:twofold/main.dart';

void main() {
  late TwofoldCrypto crypto;
  late Directory tmp;

  setUpAll(() async => crypto = await TwofoldCrypto.init());
  setUp(() async => tmp = await Directory.systemTemp.createTemp('twofold'));
  tearDown(() async => tmp.delete(recursive: true));

  testWidgets('a fresh install shows the welcome screen', (tester) async {
    final controller = AppController(
      crypto: crypto,
      store: VaultStore(tmp),
      enableLan: false,
    );
    await tester.runAsync(controller.init);
    await tester.pumpWidget(TwofoldApp(controller: controller));
    await tester.pumpAndSettle();
    expect(find.text('Fold it away.'), findsOneWidget);
    expect(find.text('Create a family vault'), findsOneWidget);
    expect(find.text('Join my family\'s vault'), findsOneWidget);
  });
}
