import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

import '../locator.dart';
import '../models/bookmark.dart';
import '../services/position_service.dart';

/// Deletes [bookmark] immediately and offers a short Undo snackbar.
///
/// Undo re-inserts the bookmark with all fields preserved (label, notes,
/// chapter, position, created-at) — it receives a new row id, which is fine
/// because nothing else keys off bookmark ids.
///
/// Used by both bookmark surfaces (player sheet and book details) so deletion
/// behaviour stays identical everywhere.
Future<void> deleteBookmarkWithUndo(
  BuildContext context,
  Bookmark bookmark,
) async {
  await locator<PositionService>().deleteBookmark(bookmark.id!);

  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text('Bookmark "${bookmark.label}" deleted'),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () =>
              unawaited(locator<PositionService>().addBookmark(bookmark)),
        ),
      ),
    );
}
