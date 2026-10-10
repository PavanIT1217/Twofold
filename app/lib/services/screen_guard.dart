import 'package:no_screenshot/no_screenshot.dart';

/// Blocks screenshots and screen recording, and hides the app's contents in
/// the recent-apps switcher.
class ScreenGuard {
  Future<void> enable() async {
    try {
      await NoScreenshot.instance.screenshotOff();
    } on Object {
      // Not supported on this platform (for example in tests).
    }
  }
}
