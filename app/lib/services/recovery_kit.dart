import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

/// Builds the printable recovery kit: the recovery key and what to do with
/// it. Generated on the phone and handed straight to the print or share
/// sheet; it is never stored by Twofold.
Future<Uint8List> buildRecoveryKitPdf({
  required String name,
  required String vaultName,
  required String recoveryKey,
  required DateTime created,
}) async {
  final doc = pw.Document(title: 'Twofold recovery kit', author: 'Twofold');
  final ink = PdfColor.fromHex('#0b1220');
  final gold = PdfColor.fromHex('#a87513');
  final groups = recoveryKey.split('-');
  final lines = <String>[
    for (var i = 0; i < groups.length; i += 4)
      groups
          .sublist(i, i + 4 > groups.length ? groups.length : i + 4)
          .join('  '),
  ];
  final date =
      '${created.day.toString().padLeft(2, '0')}-'
      '${created.month.toString().padLeft(2, '0')}-${created.year}';

  doc.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.all(48),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'TWOFOLD',
            style: pw.TextStyle(
              color: gold,
              fontSize: 11,
              letterSpacing: 3,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          pw.Text(
            'Recovery kit',
            style: pw.TextStyle(
              color: ink,
              fontSize: 30,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Text(
            '$name · $vaultName · made on $date',
            style: const pw.TextStyle(fontSize: 11),
          ),
          pw.SizedBox(height: 28),
          pw.Text(
            'Your recovery key',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 10),
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: ink, width: 1.5),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                for (final line in lines)
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 4),
                    child: pw.Text(
                      line,
                      style: pw.TextStyle(
                        font: pw.Font.courierBold(),
                        fontSize: 18,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          pw.SizedBox(height: 28),
          pw.Text(
            'What this is for',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Bullet(
            text: 'If you forget your master password, this key opens your vault instead.',
          ),
          pw.Bullet(
            text: 'If you get a new phone, restore your backup and enter this key or your master password.',
          ),
          pw.Bullet(
            text: 'Twofold cannot recover your vault for you. Without your password, this key, or another paired phone, nobody can open it.',
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            'Keep it safe',
            style: pw.TextStyle(fontSize: 13, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 6),
          pw.Bullet(
            text: 'Keep this page with your important papers, in a bank locker, or with your will.',
          ),
          pw.Bullet(
            text: 'Don\'t photograph it, email it or store it in a notes app.',
          ),
          pw.Bullet(
            text: 'Made a new recovery key in Settings? Destroy this page; it no longer works.',
          ),
          pw.Spacer(),
          pw.Divider(color: PdfColors.grey400),
          pw.Text(
            'twofold.webappslab.com',
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey700),
          ),
        ],
      ),
    ),
  );
  return doc.save();
}
