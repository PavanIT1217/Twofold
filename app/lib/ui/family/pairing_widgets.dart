import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../sync/pairing.dart';
import '../app_scope.dart';
import '../theme.dart';

/// This phone's pairing QR code.
class MyCodeCard extends StatelessWidget {
  const MyCodeCard({super.key, required this.caption});

  final String caption;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    return FutureBuilder<PairingCode>(
      // Rebuilt when the controller changes, so the Wi-Fi port is current.
      future: app.myPairingCode(),
      builder: (context, snapshot) {
        final code = snapshot.data;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: code == null
                      ? const SizedBox(
                          width: 220,
                          height: 220,
                          child: Center(child: CircularProgressIndicator()),
                        )
                      : QrImageView(
                          data: code.encode(),
                          size: 220,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: Brand.ink,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: Brand.ink,
                          ),
                        ),
                ),
                const SizedBox(height: 12),
                Text(caption, textAlign: TextAlign.center),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Opens the camera and returns the first Twofold pairing code it sees.
Future<PairingCode?> scanPairingCode(BuildContext context) =>
    Navigator.push<PairingCode>(
      context,
      MaterialPageRoute(builder: (_) => const _ScanScreen()),
    );

class _ScanScreen extends StatefulWidget {
  const _ScanScreen();

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final barcode in capture.barcodes) {
      final code = PairingCode.tryParse(barcode.rawValue ?? '');
      if (code != null) {
        _done = true;
        Navigator.pop(context, code);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Scan their Twofold code')),
    body: MobileScanner(onDetect: _onDetect),
  );
}

/// The pair number both phones show. If the two screens match, nobody has
/// swapped a key in between.
class PairNumberView extends StatelessWidget {
  const PairNumberView({super.key, required this.groups});

  final List<String> groups;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Brand.ink,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Wrap(
      spacing: 16,
      runSpacing: 8,
      alignment: WrapAlignment.center,
      children: [
        for (final g in groups)
          Text(
            g,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 18,
              color: Brand.gold,
              letterSpacing: 1.5,
            ),
          ),
      ],
    ),
  );
}
