import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/models/audiobook.dart';
import 'package:audiovault/widgets/book_cover.dart';

Audiobook _book() => Audiobook(
      title: 'Test Book',
      path: '/dummy/test-book',
      audioFiles: const [],
    );

Widget _wrap(Widget child) => MaterialApp(
      home: Scaffold(
        body: SizedBox(width: 100, height: 100, child: child),
      ),
    );

void main() {
  testWidgets('placeholder shows menu_book icon by default', (tester) async {
    await tester.pumpWidget(_wrap(BookCover(book: _book())));
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('shows spinner overlay while enriching', (tester) async {
    await tester.pumpWidget(
      _wrap(BookCover(book: _book(), isEnriching: true)),
    );
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('shows failed icon when enrichmentFailed and not enriching',
      (tester) async {
    await tester.pumpWidget(
      _wrap(BookCover(book: _book(), enrichmentFailed: true)),
    );
    expect(find.byIcon(Icons.image_not_supported_outlined), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_rounded), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'spinner wins over failed when both flags are somehow set (retry in flight)',
      (tester) async {
    await tester.pumpWidget(
      _wrap(BookCover(
        book: _book(),
        isEnriching: true,
        enrichmentFailed: true,
      )),
    );
    // While enriching, should show the default placeholder icon + spinner —
    // not the "failed" icon — because the current attempt may still succeed.
    expect(find.byIcon(Icons.menu_book_rounded), findsOneWidget);
    expect(find.byIcon(Icons.image_not_supported_outlined), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
