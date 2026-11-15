import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/core/rules.dart';
import 'package:task_planner/models/models.dart';

import 'support/app_harness.dart';

/// G09: the shell must stay usable on a 360x640 phone, with enlarged text,
/// with touch targets above the Material minimum, and with readable contrast
/// in both themes.
void main() {
  void setPhone(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  /// Visits every tab visible for [account]; any overflow or layout error
  /// fails the test when the frame is pumped.
  Future<void> visitTabs(WidgetTester tester, Account account) async {
    final tabs = visibleTabs(account.role);
    for (var i = 0; i < tabs.length; i += 1) {
      await tester.tap(find.byType(NavigationDestination).at(i));
      await settle(tester);
      expect(
        tester.takeException(),
        isNull,
        reason: 'tab ${tabs[i]} must lay out without an exception',
      );
    }
  }

  testWidgets('every role lays out on a 360x640 phone', (tester) async {
    setPhone(tester);
    final fixture = Fixture();
    final viewer = const Account(
      id: 9,
      name: 'Vera Viewer',
      email: 'vera@example.com',
      projectId: 1,
      role: 'viewer',
      status: 'active',
    );
    fixture.api.addAccount(viewer);

    for (final account in [fixture.admin, fixture.owner, fixture.user, viewer]) {
      // TaskPlannerApp restores the session in initState; clear the tree so
      // each account gets a fresh app instead of the previous provider state.
      await tester.pumpWidget(const SizedBox.shrink());
      await pumpTaskPlanner(tester, fixture.api, account: account);
      expect(find.byType(NavigationDestination), findsWidgets);
      await visitTabs(tester, account);
    }
  });

  testWidgets('enlarged text still lays out every tab', (tester) async {
    setPhone(tester);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

    final fixture = Fixture();
    fixture.api.addTask(
      Task(
        id: 1,
        title: 'A reasonably long task title that wraps on a narrow screen',
        description: 'With a description that also wraps.',
        projectId: fixture.project.id,
        dueDate: DateTime.now(),
        createdAt: DateTime.now(),
      ),
    );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);
    await visitTabs(tester, fixture.owner);
  });

  testWidgets('primary touch targets meet the Material minimum', (
    tester,
  ) async {
    setPhone(tester);
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    // The FAB lives on the Tasks tab.
    await tester.tap(find.byType(NavigationDestination).at(1));
    await settle(tester);

    final fab = tester.getSize(find.byType(FloatingActionButton).first);
    expect(fab.width, greaterThanOrEqualTo(48));
    expect(fab.height, greaterThanOrEqualTo(48));

    final destination = tester.getSize(
      find.byType(NavigationDestination).first,
    );
    expect(destination.height, greaterThanOrEqualTo(48));

    final notification = tester.getSize(find.byTooltip('Notifications'));
    expect(notification.width, greaterThanOrEqualTo(40));
    expect(notification.height, greaterThanOrEqualTo(40));
  });

  testWidgets('both themes keep WCAG AA contrast on surfaces', (tester) async {
    final fixture = Fixture();

    for (final mode in ['light', 'dark']) {
      await pumpTaskPlanner(
        tester,
        fixture.api,
        account: fixture.user,
        prefs: {'themeMode': mode},
      );
      final context = tester.element(find.byType(Scaffold).first);
      final scheme = Theme.of(context).colorScheme;
      expect(
        Theme.of(context).brightness,
        mode == 'dark' ? Brightness.dark : Brightness.light,
      );
      expect(
        _contrast(scheme.onSurface, scheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: '$mode onSurface/surface',
      );
      expect(
        _contrast(scheme.onSurfaceVariant, scheme.surface),
        greaterThanOrEqualTo(4.5),
        reason: '$mode onSurfaceVariant/surface',
      );
      expect(
        _contrast(scheme.onErrorContainer, scheme.errorContainer),
        greaterThanOrEqualTo(4.5),
        reason: '$mode error container text',
      );
      // Filled buttons use the fixed accent with white text in both themes.
      expect(
        _contrast(Colors.white, const Color(0xFF7C4DFF)),
        greaterThanOrEqualTo(4.5),
        reason: '$mode filled button on accent',
      );
      // FABs use the Material 3 primary container pair.
      expect(
        _contrast(scheme.onPrimaryContainer, scheme.primaryContainer),
        greaterThanOrEqualTo(4.5),
        reason: '$mode FAB container pair',
      );
    }
  });
}

/// WCAG 2.1 contrast ratio between two opaque colors.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}
