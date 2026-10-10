import 'package:flutter/material.dart';

import '../../data/templates.dart';
import '../app_scope.dart';
import '../items/item_tile.dart';

class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.category});

  final Category category;

  @override
  Widget build(BuildContext context) {
    final items =
        AppScope.of(context).vault!.items
            .where((i) => i.template.category == category)
            .toList()
          ..sort(
            (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
          );
    return Scaffold(
      appBar: AppBar(title: Text('${category.emoji}  ${category.label}')),
      body: items.isEmpty
          ? const Center(child: Text('Nothing here yet.'))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [for (final item in items) ItemTile(item: item)],
            ),
    );
  }
}
