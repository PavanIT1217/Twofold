import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../../data/models.dart';
import '../app_scope.dart';
import '../widgets/common.dart';

class AttachmentTile extends StatelessWidget {
  const AttachmentTile({super.key, required this.attachment, this.onRemove});

  final Attachment attachment;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final kb = (attachment.size / 1024).ceil();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Icon(
            attachment.isImage
                ? Icons.image_outlined
                : attachment.isPdf
                ? Icons.picture_as_pdf_outlined
                : Icons.insert_drive_file_outlined,
          ),
          title: Text(
            attachment.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(
            kb > 1024 ? '${(kb / 1024).toStringAsFixed(1)} MB' : '$kb KB',
          ),
          trailing: onRemove == null
              ? const Icon(Icons.chevron_right)
              : IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Remove',
                  onPressed: onRemove,
                ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => AttachmentScreen(attachment: attachment),
            ),
          ),
        ),
      ),
    );
  }
}

/// Decrypts and shows an attachment in memory. Nothing is written to disk
/// unless the user chooses to share or print it.
class AttachmentScreen extends StatelessWidget {
  const AttachmentScreen({super.key, required this.attachment});

  final Attachment attachment;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.read(context);
    return FutureBuilder<Uint8List?>(
      future: app.readAttachment(attachment),
      builder: (context, snapshot) {
        final bytes = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(attachment.name, overflow: TextOverflow.ellipsis),
            actions: [
              if (bytes != null)
                IconButton(
                  tooltip: 'Share or save',
                  icon: const Icon(Icons.ios_share),
                  onPressed: () async {
                    final ok = await confirm(
                      context,
                      title: 'Share a copy?',
                      message: 'The shared copy is not encrypted. Only share it with apps and people you trust.',
                      action: 'Share',
                    );
                    if (!ok) return;
                    await app.whileAway(
                      () => SharePlus.instance.share(
                        ShareParams(
                          files: [
                            XFile.fromData(
                              bytes,
                              mimeType: attachment.mime,
                              name: attachment.name,
                            ),
                          ],
                          fileNameOverrides: [attachment.name],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
          body: switch (snapshot.connectionState) {
            ConnectionState.done when bytes == null => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'This document hasn\'t reached this phone yet. It arrives with the next sync.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            ConnectionState.done when attachment.isImage => InteractiveViewer(
              maxScale: 6,
              child: Center(child: Image.memory(bytes!)),
            ),
            ConnectionState.done when attachment.isPdf => PdfPreview(
              build: (_) async => bytes!,
              canChangeOrientation: false,
              canChangePageFormat: false,
              canDebug: false,
              allowSharing: false,
            ),
            ConnectionState.done => const Center(
              child: Text('Use Share to open this file in another app.'),
            ),
            _ => const Center(child: CircularProgressIndicator()),
          },
        );
      },
    );
  }
}
