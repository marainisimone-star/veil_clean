import 'package:flutter_test/flutter_test.dart';
import 'package:veil_clean/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const VeilCleanApp());
    await tester.pumpAndSettle();
    expect(find.byType(VeilCleanApp), findsOneWidget);
  });
}
