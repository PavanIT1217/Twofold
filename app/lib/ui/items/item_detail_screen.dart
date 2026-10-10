import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/templates.dart';
import '../../services/reminders.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'attachment_view.dart';
import 'item_edit_screen.dart';

class ItemDetailScreen extends StatelessWidget {
  const ItemDetailScreen({super.key, required this.itemId});

  final String itemId;

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final item = app.vault?.item(itemId);
    if (item == null || item.deleted) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('This item was removed.')),
      );
    }
    final template = item.template;
    final canEdit = app.vault!.myRole.canEdit;
    final author = app.vault!.roster.members[item.updatedBy]?.name ?? 'someone';

    return Scaffold(
      appBar: AppBar(
        actions: [
          if (canEdit) ...[
            IconButton(
              tooltip: item.pinned ? 'Unpin' : 'Pin to the top',
              icon: Icon(
                item.pinned ? Icons.push_pin : Icons.push_pin_outlined,
              ),
              onPressed: () =>
                  app.saveItem(item.copyWith(pinned: !item.pinned)),
            ),
            IconButton(
              tooltip: 'Edit',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => ItemEditScreen(item: item, isNew: false),
                ),
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) async {
                if (v == 'trash') {
                  final ok = await confirm(
                    context,
                    title: 'Move to trash?',
                    message: 'It stays in the trash for 30 days on every family phone, then it\'s deleted.',
                    action: 'Move to trash',
                  );
                  if (ok && context.mounted) {
                    await app.trashItem(item.id);
                    if (context.mounted) Navigator.pop(context);
                  }
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'trash', child: Text('Move to trash')),
              ],
            ),
          ],
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
        children: [
          Text(
            '${template.category.emoji}  ${template.label.toUpperCase()}',
            style: Theme.of(context).textTheme.labelMedium
                ?.copyWith(letterSpacing: 1.2),
          ),
          const SizedBox(height: 6),
          Text(
            item.title.isEmpty ? template.label : item.title,
            style: displaySerif(context, size: 30),
          ),
          const SizedBox(height: 4),
          Text(
            'Updated ${timeAgo(item.updatedAt)} by $author',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (item.whatToDo.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              color: Brand.navy,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'WHAT TO DO',
                      style: TextStyle(
                        color: Brand.gold,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.2,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      item.whatToDo,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (template.fields.any(
                (f) => (item.fields[f.key] ?? '').isNotEmpty,
              ) ||
              item.custom.isNotEmpty) ...[
            const SectionHeader('Details'),
            Card(
              child: Column(
                children: [
                  for (final f in template.fields)
                    if ((item.fields[f.key] ?? '').isNotEmpty)
                      _FieldRow(
                        label: f.label,
                        value: item.fields[f.key]!,
                        kind: f.kind,
                      ),
                  for (final c in item.custom)
                    _FieldRow(
                      label: c.label,
                      value: c.value,
                      kind: c.secret ? FieldKind.secret : FieldKind.text,
                    ),
                ],
              ),
            ),
          ],
          if (item.reminders.isNotEmpty) ...[
            const SectionHeader('Reminders'),
            for (final r in item.reminders) Text('• ${_reminderText(item, r)}'),
          ],
          if (item.notes.isNotEmpty) ...[
            const SectionHeader('Notes'),
            SelectableText(
              item.notes,
              style: const TextStyle(fontSize: 16, height: 1.5),
            ),
          ],
          if (item.attachments.isNotEmpty) ...[
            const SectionHeader('Documents'),
            for (final a in item.attachments) AttachmentTile(attachment: a),
          ],
        ],
      ),
    );
  }

  static String _reminderText(VaultItem item, Reminder r) {
    final label =
        item.template.fields
            .where((f) => f.key == r.field)
            .map((f) => f.label)
            .firstOrNull ??
        r.field;
    final date = parseFieldDate(item.fields[r.field]);
    final days = (r.daysBefore.toList()..sort((a, b) => b.compareTo(a))).join(
      ', ',
    );
    return '$label${date == null ? '' : ' (${formatDate(date)})'}: $days days before';
  }
}

class _FieldRow extends StatefulWidget {
  const _FieldRow({
    required this.label,
    required this.value,
    required this.kind,
  });

  final String label;
  final String value;
  final FieldKind kind;

  @override
  State<_FieldRow> createState() => _FieldRowState();
}

class _FieldRowState extends State<_FieldRow> {
  bool _revealed = false;

  @override
  Widget build(BuildContext context) {
    final secret = widget.kind == FieldKind.secret;
    final shown = switch (widget.kind) {
      FieldKind.secret when !_revealed => '•' * 10,
      FieldKind.date =>
        parseFieldDate(widget.value) == null
            ? widget.value
            : formatDate(parseFieldDate(widget.value)!),
      _ => widget.value,
    };
    return ListTile(
      title: Text(widget.label, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(
        shown,
        style: TextStyle(
          fontSize: 16,
          color: Theme.of(context).colorScheme.onSurface,
          fontFamily: secret && _revealed ? 'monospace' : null,
        ),
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (secret)
            IconButton(
              tooltip: _revealed ? 'Hide' : 'Show',
              icon: Icon(
                _revealed
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
              ),
              onPressed: () => setState(() => _revealed = !_revealed),
            ),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () {
              AppScope.read(context).clipboard.copy(widget.value);
              showMessage(
                context,
                secret
                    ? 'Copied. The clipboard clears in 30 seconds.'
                    : 'Copied.',
              );
            },
          ),
        ],
      ),
    );
  }
}
