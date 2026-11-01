import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/providers/data_providers.dart';
import 'package:task_planner/providers/session_providers.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('401 ends the session and returns to login with a notice', (
    tester,
  ) async {
    final fixture = Fixture();
    final container = await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.owner,
    );
    expect(find.text('Olive Owner'), findsWidgets);
    expect(container.read(sessionUserIdProvider), fixture.owner.id);

    fixture.api.unauthorized = true;
    container.invalidate(visibleMembersProvider);
    await settle(tester);
    await settle(tester);

    expect(container.read(sessionUserIdProvider), isNull);
    expect(find.text('Your session expired. Log in again.'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);
    expect(find.text('Olive Owner'), findsNothing);
  });

  testWidgets('login works again after an expired session', (tester) async {
    final fixture = Fixture();
    final container = await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.user,
    );

    fixture.api.unauthorized = true;
    container.invalidate(visibleMembersProvider);
    await settle(tester);
    await settle(tester);
    expect(find.text('Your session expired. Log in again.'), findsOneWidget);

    fixture.api.unauthorized = false;
    await tester.enterText(find.byType(TextField).at(0), 'bob@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await settle(tester);

    expect(find.byType(NavigationDestination), findsNWidgets(5));
    expect(find.text('Your session expired. Log in again.'), findsNothing);
  });
}
