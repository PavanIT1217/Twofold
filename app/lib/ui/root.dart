import 'package:flutter/material.dart';

import '../app/app_controller.dart';
import 'app_scope.dart';
import 'home/home_shell.dart';
import 'onboarding/join_screen.dart';
import 'onboarding/recovery_kit_screen.dart';
import 'onboarding/welcome_screen.dart';
import 'unlock_screen.dart';

/// Picks the screen for the app's current stage, and locks the vault when
/// the app has been in the background longer than the auto-lock time.
class Root extends StatefulWidget {
  const Root({super.key});

  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  late final AppLifecycleListener _lifecycle;
  DateTime? _hiddenAt;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onHide: () {
        if (!AppScope.read(context).awayOnPurpose) _hiddenAt = DateTime.now();
      },
      onShow: _onShow,
    );
  }

  void _onShow() {
    final app = AppScope.read(context);
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    if (hiddenAt == null || app.awayOnPurpose) return;
    final away = DateTime.now().difference(hiddenAt);
    if (away.inSeconds >= app.settings.autoLockSeconds) {
      // Close any open screens so nothing private is left on the stack.
      Navigator.of(context).popUntil((r) => r.isFirst);
      app.lock();
    } else if (app.stage == AppStage.open) {
      app.syncNow();
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    if (app.pendingRecoveryKey != null &&
        (app.stage == AppStage.open || app.stage == AppStage.joining)) {
      return const RecoveryKitScreen(firstTime: true);
    }
    return switch (app.stage) {
      AppStage.loading => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      AppStage.welcome => const WelcomeScreen(),
      AppStage.locked => const UnlockScreen(),
      AppStage.joining => const JoinScreen(),
      AppStage.open => const HomeShell(),
    };
  }
}
