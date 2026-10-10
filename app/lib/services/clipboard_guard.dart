import 'dart:async';

import 'package:flutter/services.dart';

/// Copies text and clears the clipboard again after [clearAfter], so a copied
/// password doesn't linger.
class ClipboardGuard {
  ClipboardGuard({this.clearAfter = const Duration(seconds: 30)});

  final Duration clearAfter;
  Timer? _timer;

  Future<void> copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    _timer?.cancel();
    _timer = Timer(clearAfter, clear);
  }

  Future<void> clear() async {
    _timer?.cancel();
    _timer = null;
    await Clipboard.setData(const ClipboardData(text: ''));
  }
}
