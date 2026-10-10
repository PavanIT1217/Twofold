import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../app_scope.dart';
import '../theme.dart';
import '../widgets/common.dart';
import 'add_member_screen.dart';

class FamilyTab extends StatelessWidget {
  const FamilyTab({super.key});

  @override
  Widget build(BuildContext context) {
    final app = AppScope.of(context);
    final vault = app.vault!;
    final isOwner = vault.myRole == Role.owner;
    final members = vault.roster.active.toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    final nearby = {for (final p in app.nearby) p.memberId};
    final canAdd = isOwner && members.length < 6;

    return Scaffold(
      appBar: AppBar(
        title: Text('Family', style: displaySerif(context, size: 26)),
      ),
      floatingActionButton: canAdd
          ? FloatingActionButton.extended(
              heroTag: 'add-member',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AddMemberScreen(),
                ),
              ),
              icon: const Icon(Icons.person_add_alt),
              label: const Text('Add member'),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.wifi),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          app.syncing ? 'Syncing…' : 'Home Wi-Fi sync',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        Text(
                          [
                            if (app.lastSyncAt != null)
                              'Last synced ${timeAgo(app.lastSyncAt!)}'
                            else
                              'Not synced yet',
                            if (nearby.isNotEmpty) '${nearby.length} nearby',
                          ].join(' · '),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonal(
                    onPressed: app.syncing ? null : app.syncNow,
                    child: const Text('Sync'),
                  ),
                ],
              ),
            ),
          ),
          if (app.lastSyncError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                app.lastSyncError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          const SectionHeader('Members'),
          for (final m in members)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: m.id == app.memberId
                        ? Brand.gold
                        : Brand.navy,
                    foregroundColor: m.id == app.memberId
                        ? Brand.ink
                        : Colors.white,
                    child: Text(
                      m.name.isEmpty
                          ? '?'
                          : m.name.characters.first.toUpperCase(),
                    ),
                  ),
                  title: Text(
                    m.id == app.memberId ? '${m.name} (this phone)' : m.name,
                  ),
                  subtitle: Text(
                    [
                      m.role.label,
                      if (nearby.contains(m.id)) 'nearby',
                    ].join(' · '),
                  ),
                  trailing: isOwner && m.id != app.memberId
                      ? const Icon(Icons.more_vert)
                      : null,
                  onTap: isOwner && m.id != app.memberId
                      ? () => _manage(context, m)
                      : null,
                ),
              ),
            ),
          const SizedBox(height: 8),
          Text(
            isOwner
                ? 'Owners add and remove members. Each phone is a member, so someone with two phones is added twice. Up to six members.'
                : 'Only owners can add or remove members.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Future<void> _manage(BuildContext context, Member m) async {
    final app = AppScope.read(context);
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(m.name, style: displaySerif(context, size: 22)),
            ),
            RadioGroup<Role>(
              groupValue: m.role,
              onChanged: (r) => Navigator.pop(context, r),
              child: Column(
                children: [
                  for (final role in Role.values)
                    RadioListTile<Role>(
                      value: role,
                      title: Text(role.label),
                      subtitle: Text(role.description),
                    ),
                ],
              ),
            ),
            const Divider(),
            ListTile(
              leading: Icon(
                Icons.person_remove_outlined,
                color: Theme.of(context).colorScheme.error,
              ),
              title: Text(
                'Remove from vault',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              onTap: () => Navigator.pop(context, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted || choice == null) return;
    try {
      if (choice is Role && choice != m.role) {
        await app.changeRole(m.id, choice);
      } else if (choice == 'remove') {
        final ok = await confirm(
          context,
          title: 'Remove ${m.name}?',
          message:
              'Their phone keeps what it already has, but can\'t open anything '
              'added or changed from now on. The vault moves to a new key.',
          action: 'Remove',
          destructive: true,
        );
        if (ok) await app.removeMember(m.id);
      }
    } on Object catch (e) {
      if (context.mounted) showError(context, e);
    }
  }
}
