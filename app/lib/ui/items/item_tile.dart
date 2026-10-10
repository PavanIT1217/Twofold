import 'package:flutter/material.dart';

import '../../data/models.dart';
import '../home/vault_tab.dart';

class ItemTile extends StatelessWidget {
  const ItemTile({super.key, required this.item, this.onTap});

  final VaultItem item;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final template = item.template;
    final subtitle = [
      template.label,
      if (item.attachments.isNotEmpty) '📎 ${item.attachments.length}',
    ].join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Card(
        child: ListTile(
          leading: Text(
            template.category.emoji,
            style: const TextStyle(fontSize: 24),
          ),
          title: Text(
            item.title.isEmpty ? template.label : item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: onTap ?? () => openItem(context, item),
        ),
      ),
    );
  }
}
