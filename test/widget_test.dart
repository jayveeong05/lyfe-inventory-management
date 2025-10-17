// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:inventory_pro/screens/dashboard_screen.dart';

void main() {
  testWidgets('InventoryPro dashboard smoke test', (WidgetTester tester) async {
    // Build our dashboard screen directly (avoiding Firebase initialization in tests)
    await tester.pumpWidget(const MaterialApp(home: DashboardScreen()));

    // Wait for the widget to settle
    await tester.pumpAndSettle();

    // Verify that our app title is displayed.
    expect(find.text('InventoryPro'), findsOneWidget);
    expect(find.text('Inventory Management'), findsOneWidget);

    // Verify that all four main buttons are present.
    expect(find.text('Stock In'), findsOneWidget);
    expect(find.text('Stock Out'), findsOneWidget);

    // Scroll to ensure all items are visible
    await tester.drag(find.byType(GridView), const Offset(0, -200));
    await tester.pumpAndSettle();

    expect(find.text('Invoice'), findsOneWidget);
    expect(find.text('Delivery Order'), findsOneWidget);
  });
}
