import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mrz/core/config/injection.dart';
import 'package:mrz/main.dart';

void main() {
  setUpAll(() async {
    await configureDependencies();
  });

  testWidgets('shows loading while opening scanner', (tester) async {
    await tester.pumpWidget(const MyApp());
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
