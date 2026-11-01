import 'package:flutter/material.dart' hide Notification;
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';

import 'support/app_harness.dart';

/// Notification widget tests: list, tap-to-read, unread filter, empty state.
void main() {
  testWidgets('unread notifications are listed and marked read on tap', (
    tester,
  ) async {
    final fixture = Fixture();
    fixture.api.addNotification(
      Notification(
        id: 7,
        type: 'task_created',
        title: 'New task in Alpha',
        body: 'Ship the release was created',
        payload: '2',
        createdAt: DateTime.now(),
      ),
    );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);

    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester);

    expect(find.text('Notifications'), findsWidgets);
    expect(find.text('New task in Alpha'), findsOneWidget);
    expect(find.text('Ship the release was created'), findsOneWidget);

    await tester.tap(find.text('New task in Alpha'));
    await settle(tester);

    expect(fixture.api.notifications.single.readAt, isNotNull);
    expect(find.text('New task in Alpha'), findsOneWidget);

    // The unread filter no longer lists the notification.
    await tester.tap(find.byTooltip('Unread only'));
    await settle(tester);
    expect(find.text('No unread notifications'), findsOneWidget);
    expect(find.text('New task in Alpha'), findsNothing);
  });

  testWidgets('the notifications screen shows an empty state', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);

    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester);

    expect(find.text('No notifications'), findsOneWidget);
    expect(
      find.text('You will see updates here when tasks or members change.'),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('notification list errors are shown with a retry action', (
    tester,
  ) async {
    final fixture = Fixture();
    fixture.api.notificationsError = 'offline';
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);

    await tester.tap(find.byTooltip('Notifications'));
    await settle(tester);

    expect(find.textContaining('Could not load notifications'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);

    fixture.api.notificationsError = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('No notifications'), findsOneWidget);
  });
}
