import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/main.dart';

void main() {
  setUpAll(() async {
    await configureDependencies();
  });

  testWidgets('shows the home screen with both document options', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose a document to scan'), findsOneWidget);
    expect(find.text('Sudan ID (front + back)'), findsOneWidget);
    expect(find.text('Passport'), findsOneWidget);
  });
}
