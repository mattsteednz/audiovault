import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/models/audiobook.dart';
import 'package:audiovault/services/drive_removal_scheduler.dart';

Audiobook _driveBook({
  String path = '/drive/book',
  String? folderId = 'folder-1',
}) =>
    Audiobook(
      title: 'Drive Book',
      path: path,
      audioFiles: const [],
      source: AudiobookSource.drive,
      driveMetadata: folderId == null
          ? null
          : DriveBookMeta(
              folderId: folderId,
              folderName: 'Drive Book',
              isShared: false,
              totalFileCount: 1,
            ),
    );

Audiobook _localBook({String path = '/local/book'}) =>
    Audiobook(title: 'Local', path: path, audioFiles: const []);

/// Builds a scheduler with lambda stubs. [onDelete] is called with the
/// folderId the scheduler tried to delete; unused by tests that just need
/// "nothing ran".
DriveRemovalScheduler _make({
  BookStatus statusAtFire = BookStatus.finished,
  bool removeWhenFinished = true,
  required List<String> deletedFolders,
  Duration delay = const Duration(minutes: 1),
}) =>
    DriveRemovalScheduler(
      getBookStatus: (_) async => statusAtFire,
      deleteFiles: (f) async => deletedFolders.add(f),
      isRemoveWhenFinishedEnabled: () async => removeWhenFinished,
      delay: delay,
    );

void main() {
  group('DriveRemovalScheduler.scheduleForBook', () {
    test('schedules delete for a Drive book with preference enabled', () {
      fakeAsync((async) {
        final deleted = <String>[];
        final s = _make(deletedFolders: deleted);
        s.scheduleForBook(_driveBook());
        async.flushMicrotasks();
        expect(s.isPending, isTrue);
        async.elapse(const Duration(minutes: 1));
        expect(deleted, ['folder-1']);
        expect(s.isPending, isFalse);
      });
    });

    test('does NOT schedule for a local book', () {
      fakeAsync((async) {
        final deleted = <String>[];
        final s = _make(deletedFolders: deleted);
        s.scheduleForBook(_localBook());
        async.flushMicrotasks();
        expect(s.isPending, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(deleted, isEmpty);
      });
    });

    test('does NOT schedule when folderId is null', () {
      fakeAsync((async) {
        final deleted = <String>[];
        final s = _make(deletedFolders: deleted);
        s.scheduleForBook(_driveBook(folderId: null));
        async.flushMicrotasks();
        expect(s.isPending, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(deleted, isEmpty);
      });
    });

    test('does NOT schedule when preference is disabled', () {
      fakeAsync((async) {
        final deleted = <String>[];
        final s = _make(
          deletedFolders: deleted,
          removeWhenFinished: false,
        );
        s.scheduleForBook(_driveBook());
        async.flushMicrotasks();
        expect(s.isPending, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(deleted, isEmpty);
      });
    });

    test('skips delete if the book is no longer finished at fire time', () {
      fakeAsync((async) {
        final deleted = <String>[];
        final s = _make(
          deletedFolders: deleted,
          statusAtFire: BookStatus.inProgress,
        );
        s.scheduleForBook(_driveBook());
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        expect(deleted, isEmpty);
        expect(s.isPending, isFalse);
      });
    });

    test('a second schedule replaces the first', () {
      fakeAsync((async) {
        final deleted = <String>[];
        final s = _make(deletedFolders: deleted);
        s.scheduleForBook(_driveBook(path: '/a', folderId: 'folder-a'));
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        s.scheduleForBook(_driveBook(path: '/b', folderId: 'folder-b'));
        async.flushMicrotasks();
        async.elapse(const Duration(minutes: 1));
        // Only the second book's folder should be deleted.
        expect(deleted, ['folder-b']);
      });
    });
  });

  group('DriveRemovalScheduler.cancel', () {
    test('cancels a pending schedule', () {
      fakeAsync((async) {
        final deleted = <String>[];
        final s = _make(deletedFolders: deleted);
        s.scheduleForBook(_driveBook());
        async.flushMicrotasks();
        expect(s.isPending, isTrue);
        s.cancel();
        expect(s.isPending, isFalse);
        async.elapse(const Duration(minutes: 5));
        expect(deleted, isEmpty);
      });
    });

    test('is safe to call when nothing is pending', () {
      final s = _make(deletedFolders: []);
      s.cancel();
      s.cancel();
      expect(s.isPending, isFalse);
    });
  });
}
