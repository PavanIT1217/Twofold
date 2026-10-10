import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../widgets/common.dart';

class TrashScreen extends StatelessWidget {
  const TrashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final trash = app.vault!.trash;
    final canEdit = app.vault!.myRole.canEdit;
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: trash.isEmpty
          ? const Center(child: Text('The trash is empty.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                for (final item in trash)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Card(
                      child: ListTile(
                        leading: Text(
                          item.template.category.emoji,
                          style: const TextStyle(fontSize: 22),
                        ),
                        title: Text(
                          item.title.isEmpty ? item.template.label : item.title,
                        ),
                        subtitle: Text('Deleted ${timeAgo(item.deletedAt!)}'),
                        trailing: canEdit
                            ? PopupMenuButton<String>(
                                onSelected: (v) async {
                                  if (v == 'restore') {
                                    await app.restoreItem(item.id);
                                  }
                                  if (v == 'delete' && context.mounted) {
                                    final ok = await confirm(
                                      context,
                                      title: 'Delete for good?',
                                      message: 'It will be deleted from every family phone.',
                                      action: 'Delete',
                                      destructive: true,
                                    );
                                    if (ok) await app.purgeItem(item.id);
                                  }
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(
                                    value: 'restore',
                                    child: Text('Restore'),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: Text('Delete for good'),
                                  ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
