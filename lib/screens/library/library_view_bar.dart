import 'package:flutter/material.dart';

import '../../models/audiobook.dart';
import '../../models/availability_filter_state.dart';
import '../../utils/library_queries.dart';

/// Pinned row below the search bar: view-mode toggle, book count with an
/// active filter/sort summary, and the filter/sort entry buttons.
class LibraryViewBar extends StatelessWidget {
  final int count;
  final bool isGridView;
  final VoidCallback onToggleViewMode;
  final BookStatus? statusFilter;
  final AvailabilityFilterState availabilityFilter;
  final LibrarySortOrder sortOrder;
  final String Function(BookStatus) statusLabel;
  final VoidCallback onOpenFilter;
  final VoidCallback onOpenSort;

  const LibraryViewBar({
    super.key,
    required this.count,
    required this.isGridView,
    required this.onToggleViewMode,
    required this.statusFilter,
    required this.availabilityFilter,
    required this.sortOrder,
    required this.statusLabel,
    required this.onOpenFilter,
    required this.onOpenSort,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final hasStatus = statusFilter != null;
    final hasAvailability =
        availabilityFilter != AvailabilityFilterState.all;
    final hasSort = sortOrder != LibrarySortOrder.lastPlayed;

    final summaryParts = <String>[];
    if (hasStatus) summaryParts.add(statusLabel(statusFilter!));
    if (hasAvailability) summaryParts.add(availabilityFilter.label);
    if (hasSort) summaryParts.add(sortOrder.label);
    final summary =
        summaryParts.isEmpty ? null : ' · ${summaryParts.join(' · ')}';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 8, 4),
      child: Row(
        children: [
          IconButton(
            icon: Icon(isGridView
                ? Icons.view_list_rounded
                : Icons.grid_view_rounded),
            onPressed: onToggleViewMode,
            tooltip:
                isGridView ? 'Switch to list view' : 'Switch to grid view',
            visualDensity: VisualDensity.compact,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: count == 1 ? '1 book' : '$count books',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurface.withValues(alpha: 0.8),
                    ),
                  ),
                  if (summary != null)
                    TextSpan(
                      text: summary,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: cs.primary,
                      ),
                    ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          _ViewBarButton(
            icon: Icons.tune_rounded,
            active: hasStatus || hasAvailability,
            tooltip: 'Filter',
            onPressed: onOpenFilter,
          ),
          const SizedBox(width: 4),
          _ViewBarButton(
            icon: Icons.sort_rounded,
            active: hasSort,
            tooltip: 'Sort',
            onPressed: onOpenSort,
          ),
        ],
      ),
    );
  }
}

class _ViewBarButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final String tooltip;
  final VoidCallback onPressed;

  const _ViewBarButton({
    required this.icon,
    required this.active,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color:
          active ? cs.primary.withValues(alpha: 0.14) : Colors.transparent,
      shape: const CircleBorder(),
      child: IconButton(
        icon: Icon(
          icon,
          color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.75),
        ),
        tooltip: tooltip,
        onPressed: onPressed,
      ),
    );
  }
}
