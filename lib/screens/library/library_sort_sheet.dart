import 'package:flutter/material.dart';

import '../../utils/library_queries.dart';

/// Shows the library sort bottom sheet; persists via [onOrderSelected].
Future<void> showLibrarySortSheet(
  BuildContext context, {
  required LibrarySortOrder current,
  required Future<void> Function(LibrarySortOrder) onOrderSelected,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (sheetCtx) {
      final theme = Theme.of(sheetCtx);
      final maxHeight = MediaQuery.of(sheetCtx).size.height * 0.75;
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text('Sort by', style: theme.textTheme.titleMedium),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final order in LibrarySortOrder.values)
                      ListTile(
                        title: Text(_sortPillLabel(order)),
                        trailing: order == current
                            ? Icon(Icons.check_rounded,
                                color: theme.colorScheme.primary)
                            : null,
                        onTap: () async {
                          await onOrderSelected(order);
                          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
                        },
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

String _sortPillLabel(LibrarySortOrder order) => switch (order) {
      LibrarySortOrder.lastPlayed => 'Last played',
      LibrarySortOrder.titleAsc => 'Title A–Z',
      LibrarySortOrder.authorAsc => 'Author A–Z',
      LibrarySortOrder.dateAdded => 'Recently added',
      LibrarySortOrder.durationDesc => 'Longest first',
    };
