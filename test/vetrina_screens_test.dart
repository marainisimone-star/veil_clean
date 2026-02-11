import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:veil_clean/screens/vetrina_create_screen.dart';
import 'package:veil_clean/screens/vetrina_detail_screen.dart';
import 'package:veil_clean/screens/vetrina_feed_screen.dart';

import 'helpers/fakes/fake_vetrina_repository.dart';

void main() {
  group('Vetrina screens', () {
    testWidgets('VetrinaCreateScreen renders core sections', (tester) async {
      await tester.pumpWidget(_wrap(const VetrinaCreateScreen()));
      await tester.pump();

      expect(find.text('Create Showcase'), findsOneWidget);
      expect(find.text('Showcase content'), findsOneWidget);
      expect(find.text('Sign (Showcase name)'), findsOneWidget);

      await tester.drag(find.byType(ListView), const Offset(0, -500));
      await tester.pump();

      expect(find.text('Core rules'), findsOneWidget);
      expect(find.text('Rule options'), findsOneWidget);
    });

    testWidgets('VetrinaCreateScreen shows text draft field after Text chip', (tester) async {
      await tester.pumpWidget(_wrap(const VetrinaCreateScreen()));
      await tester.pump();

      expect(find.text('Text content'), findsNothing);

      await tester.tap(find.widgetWithText(ActionChip, 'Text'));
      await tester.pump();

      expect(find.text('Text content'), findsOneWidget);
    });

    testWidgets('VetrinaCreateScreen shows link draft field after Link chip', (tester) async {
      await tester.pumpWidget(_wrap(const VetrinaCreateScreen()));
      await tester.pump();

      expect(find.text('Link URL'), findsNothing);

      await tester.tap(find.widgetWithText(ActionChip, 'Link'));
      await tester.pump();

      expect(find.text('Link URL'), findsOneWidget);
    });

    testWidgets('VetrinaFeedScreen renders showcases from repository', (tester) async {
      _setLargeSurface(tester);
      final repo = FakeVetrinaRepository();

      await tester.pumpWidget(
        _wrap(VetrinaFeedScreen(repository: repo, showBottomNav: false)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Vetrina Showcase'), findsOneWidget);
      expect(find.text('Test Showcase'), findsOneWidget);
      expect(find.text('Latest discussion'), findsOneWidget);
      expect(find.text('Latest message from fake repo'), findsOneWidget);
    });

    testWidgets('VetrinaDetailScreen renders and sends message via repository', (tester) async {
      _setLargeSurface(tester);
      final repo = FakeVetrinaRepository();

      await tester.pumpWidget(
        _wrap(
          VetrinaDetailScreen(
            vetrinaId: 'v1',
            repository: repo,
            showBottomNav: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Test Showcase'), findsOneWidget);
      expect(find.text('Core rules'), findsOneWidget);
      expect(find.text('Discussion'), findsOneWidget);
      expect(find.text('Hello from fake repo'), findsOneWidget);

      await tester.enterText(find.byType(TextField).last, 'new message');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
      await tester.pump();

      expect(repo.lastSentText, 'new message');
      expect(repo.lastSentVetrinaId, 'v1');
    });

    testWidgets('VetrinaFeedScreen shows empty state', (tester) async {
      _setLargeSurface(tester);
      final repo = FakeVetrinaRepository(vetrine: const []);

      await tester.pumpWidget(
        _wrap(VetrinaFeedScreen(repository: repo, showBottomNav: false)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('No showcases yet.'), findsOneWidget);
    });

    testWidgets('VetrinaDetailScreen shows not found state', (tester) async {
      _setLargeSurface(tester);
      final repo = FakeVetrinaRepository(byId: const {});

      await tester.pumpWidget(
        _wrap(
          VetrinaDetailScreen(
            vetrinaId: 'missing',
            repository: repo,
            showBottomNav: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('Showcase not found.'), findsOneWidget);
    });

    testWidgets('VetrinaDetailScreen shows warned snackbar', (tester) async {
      _setLargeSurface(tester);
      final repo = FakeVetrinaRepository(addMessageResult: 'warned');

      await tester.pumpWidget(
        _wrap(
          VetrinaDetailScreen(
            vetrinaId: 'v1',
            repository: repo,
            showBottomNav: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField).last, 'warn me');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
      await tester.pump();

      expect(find.text('Warning: stay civil.'), findsOneWidget);
    });

    testWidgets('VetrinaDetailScreen shows restricted snackbar', (tester) async {
      _setLargeSurface(tester);
      final repo = FakeVetrinaRepository(addMessageResult: 'restricted');

      await tester.pumpWidget(
        _wrap(
          VetrinaDetailScreen(
            vetrinaId: 'v1',
            repository: repo,
            showBottomNav: false,
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.enterText(find.byType(TextField).last, 'blocked');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Send'));
      await tester.pump();

      expect(find.text('You are temporarily restricted.'), findsOneWidget);
    });
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(home: child);
}

void _setLargeSurface(WidgetTester tester) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1000);
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}
