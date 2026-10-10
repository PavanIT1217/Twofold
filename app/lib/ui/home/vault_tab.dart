import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../../data/templates.dart';
import '../../services/reminders.dart';
import '../app_scope.dart';
import '../items/item_detail_screen.dart';
import '../items/item_edit_screen.dart';
import '../items/item_tile.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'category_screen.dart';

class VaultTab extends StatefulWidget {
  const VaultTab({super.key});

  @override
  State<VaultTab> createState() => _VaultTabState();
}

class _VaultTabState extends State<VaultTab> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final vault = app.vault!;
    final items = vault.items;
    final canEdit = vault.myRole.canEdit;
    final query = _query.trim().toLowerCase();
    final results = query.isEmpty
        ? const <VaultItem>[]
        : items.where((i) => i.searchText.contains(query)).toList();
    final readFirst = items
        .where((i) => i.type == 'read_first' || i.pinned)
        .toList();
    final upcoming = upcomingDates(items, DateTime.now());
    final counts = <Category, int>{};
    for (final i in items) {
      counts.update(i.template.category, (n) => n + 1, ifAbsent: () => 1);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          vault.roster.vaultName,
          style: displaySerif(context, size: 26),
        ),
        actions: [
          IconButton(
            tooltip: 'Sync with family phones',
            onPressed: app.syncing ? null : app.syncNow,
            icon: app.syncing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Lock',
            onPressed: app.lock,
            icon: const Icon(Icons.lock_outline),
          ),
        ],
      ),
      floatingActionButton: canEdit
          ? FloatingActionButton.extended(
              heroTag: 'add-item',
              onPressed: () => addItem(context),
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          SearchBar(
            controller: _search,
            hintText: 'Search the vault',
            leading: const Icon(Icons.search),
            elevation: const WidgetStatePropertyAll(0),
            onChanged: (v) => setState(() => _query = v),
            trailing: [
              if (_query.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() {
                    _search.clear();
                    _query = '';
                  }),
                ),
            ],
          ),
          if (query.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: Text('Nothing matches.')),
              )
            else
              for (final item in results) ItemTile(item: item),
          ] else if (items.isEmpty) ...[
            _EmptyVault(canEdit: canEdit),
          ] else ...[
            for (final item in readFirst) ...[
              const SizedBox(height: 12),
              _PinnedCard(item: item),
            ],
            if (upcoming.isNotEmpty) ...[
              const SectionHeader('Coming up'),
              for (final u in upcoming.take(5)) _UpcomingTile(upcoming: u),
            ],
            const SectionHeader('Categories'),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.9,
              children: [
                for (final c in Category.values)
                  if ((counts[c] ?? 0) > 0)
                    _CategoryCard(category: c, count: counts[c]!),
              ],
            ),
            const SectionHeader('Recently changed'),
            for (final item in items.take(6)) ItemTile(item: item),
          ],
        ],
      ),
    );
  }
}

class _EmptyVault extends StatelessWidget {
  const _EmptyVault({required this.canEdit});

  final bool canEdit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 8),
    child: Column(
      children: [
        const Text('🗂️', style: TextStyle(fontSize: 48)),
        const SizedBox(height: 12),
        Text('Your vault is empty', style: displaySerif(context, size: 26)),
        const SizedBox(height: 8),
        Text(
          canEdit
              ? 'Start with the things your family would need first: health insurance, '
                    'bank accounts, and a "Read this first" note.'
              : 'Items your family adds will appear here after the next sync.',
          textAlign: TextAlign.center,
        ),
        if (canEdit) ...[
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: () => addItem(context, type: 'read_first'),
            icon: const Icon(Icons.push_pin_outlined),
            label: const Text('Write "Read this first"'),
          ),
        ],
      ],
    ),
  );
}

class _PinnedCard extends StatelessWidget {
  const _PinnedCard({required this.item});

  final VaultItem item;

  @override
  Widget build(BuildContext context) => Card(
    color: Brand.navy,
    child: ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: const Icon(Icons.push_pin, color: Brand.gold),
      title: Text(
        item.title.isEmpty ? 'Read this first' : item.title,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        item.notes.isEmpty ? 'Tap to open' : item.notes,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFFC9D6EA)),
      ),
      onTap: () => openItem(context, item),
    ),
  );
}

class _UpcomingTile extends StatelessWidget {
  const _UpcomingTile({required this.upcoming});

  final Upcoming upcoming;

  @override
  Widget build(BuildContext context) {
    final days = upcoming.daysFrom(DateTime.now());
    final when = switch (days) {
      0 => 'today',
      1 => 'tomorrow',
      _ => 'in $days days',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: days <= 7
                ? Brand.gold
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Text(
              '$days',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                color: Brand.ink,
              ),
            ),
          ),
          title: Text(
            upcoming.item.title.isEmpty
                ? upcoming.item.template.label
                : upcoming.item.title,
          ),
          subtitle: Text(
            '${upcoming.fieldLabel} $when · ${formatDate(upcoming.date)}',
          ),
          onTap: () => openItem(context, upcoming.item),
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.count});

  final Category category;
  final int count;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => CategoryScreen(category: category),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Text(category.emoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    category.label,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '$count ${count == 1 ? 'item' : 'items'}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

void openItem(BuildContext context, VaultItem item) => Navigator.push(
  context,
  MaterialPageRoute<void>(builder: (_) => ItemDetailScreen(itemId: item.id)),
);

/// Picks a template (unless [type] is given) and opens the editor.
Future<void> addItem(BuildContext context, {String? type}) async {
  final chosen = type ?? await pickTemplate(context);
  if (chosen == null || !context.mounted) return;
  final draft = AppScope.read(context).vault!.draft(chosen);
  await Navigator.push(
    context,
    MaterialPageRoute<void>(
      builder: (_) => ItemEditScreen(item: draft, isNew: true),
    ),
  );
}

Future<String?> pickTemplate(BuildContext context) =>
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (context, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                'What are you adding?',
                style: displaySerif(context, size: 24),
              ),
            ),
            for (final c in Category.values) ...[
              SectionHeader('${c.emoji}  ${c.label}'),
              for (final t in templates.where((t) => t.category == c))
                ListTile(
                  title: Text(t.label),
                  subtitle: t.titleHint.isEmpty ? null : Text(t.titleHint),
                  onTap: () => Navigator.pop(context, t.type),
                ),
            ],
          ],
        ),
      ),
    );
