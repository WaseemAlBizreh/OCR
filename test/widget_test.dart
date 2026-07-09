import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/main.dart';

void main() {
  setUpAll(() async {
    await configureDependencies();
  });

  testWidgets('shows home screen with both scanner options', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pumpAndSettle();

    expect(find.text('Choose a scanning mode'), findsOneWidget);
    expect(find.text('MRZ Camera Scanner'), findsOneWidget);
    expect(find.text('Arabic Document Scanner'), findsOneWidget);
  });
}
