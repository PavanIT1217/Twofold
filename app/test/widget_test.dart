import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/main.dart';

void main() {
  testWidgets('shows the welcome screen', (tester) async {
    await tester.pumpWidget(MaterialApp(home: const WelcomeScreen()));
    expect(find.text('Twofold'), findsOneWidget);
  });
}
