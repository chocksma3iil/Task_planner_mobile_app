import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('theme choices persist and survive logout', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);

    Future<void> pick(String label) async {
      await tester.tap(find.byTooltip('Theme'));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text(label));
      await settle(tester);
    }

    await pick('Light');
    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.light);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('themeMode'), 'light');

    await pick('System');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.system,
    );
    expect(prefs.getString('themeMode'), 'system');

    await pick('Dark');
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );

    await tester.tap(find.byType(PopupMenuButton<String>));
    await settle(tester);
    await tester.tap(find.text('Log out'));
    await settle(tester);

    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
  });
}
