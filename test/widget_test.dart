import 'package:flutter_test/flutter_test.dart';
import 'package:audiovault/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const AudioVaultApp());
    expect(find.byType(AudioVaultApp), findsOneWidget);
  });
}
