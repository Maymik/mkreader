import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mkreader/src/app/mkreader_app.dart';

void main() {
  testWidgets('App boots to library screen', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: MkReaderApp()));
    await tester.pumpAndSettle();

    expect(find.text('Library'), findsOneWidget);
  });
}
