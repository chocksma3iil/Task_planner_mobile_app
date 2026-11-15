import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';

import 'support/app_harness.dart';

/// C05: the filter chips and the search box must combine, and the stat cards
/// must apply the same filters as the chips.
void main() {
  Future<void> openTasks(WidgetTester tester) async {
    await tester.tap(find.text('Tasks'));
    await settle(tester);
  }

  /// Five tasks covering every bucket plus a shared word in the title so the
  /// search and the filter can be combined.
  Fixture buildFixture() {
    final fixture = Fixture();
    final now = DateTime.now();
    fixture.api
      ..addTask(
        Task(
          id: 1,
          title: 'Overdue report',
          projectId: fixture.project.id,
          dueDate: now.subtract(const Duration(days: 2)),
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
      )
      ..addTask(
        Task(
          id: 2,
          title: 'Today report',
          projectId: fixture.project.id,
          dueDate: now,
          createdAt: now.subtract(const Duration(minutes: 4)),
        ),
      )
      ..addTask(
        Task(
          id: 3,
          title: 'Upcoming report',
          projectId: fixture.project.id,
          dueDate: now.add(const Duration(days: 3)),
          createdAt: now.subtract(const Duration(minutes: 3)),
        ),
      )
      ..addTask(
        Task(
          id: 4,
          title: 'Overdue invoice',
          projectId: fixture.project.id,
          dueDate: now.subtract(const Duration(days: 1)),
          createdAt: now.subtract(const Duration(minutes: 2)),
        ),
      )
      ..addTask(
        Task(
          id: 5,
          title: 'Done report',
          projectId: fixture.project.id,
          status: 'completed',
          createdAt: now.subtract(const Duration(minutes: 1)),
        ),
      );
    return fixture;
  }

  Future<void> search(WidgetTester tester, String query) async {
    await tester.enterText(find.byType(TextField).first, query);
    // The search field debounces for 250 ms before filtering.
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  testWidgets('a search term and an active filter apply together', (
    tester,
  ) async {
    final fixture = buildFixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await openTasks(tester);

    await tester.tap(find.widgetWithText(ChoiceChip, 'Overdue'));
    await settle(tester);
    expect(find.text('Overdue report'), findsOneWidget);
    expect(find.text('Overdue invoice'), findsOneWidget);
    expect(find.text('Today report'), findsNothing);
    expect(find.text('Done report'), findsNothing);

    // Narrow the overdue bucket with the search box.
    await search(tester, 'report');
    expect(find.text('Overdue report'), findsOneWidget);
    expect(find.text('Overdue invoice'), findsNothing);

    // Same filter, another term.
    await search(tester, 'invoice');
    expect(find.text('Overdue invoice'), findsOneWidget);
    expect(find.text('Overdue report'), findsNothing);

    // A term that does not exist inside the active filter shows the empty
    // state instead of falling back to the other buckets.
    await search(tester, 'today');
    expect(find.text('No tasks here'), findsOneWidget);
    expect(find.text('Today report'), findsNothing);

    // Search is case-insensitive (the field lower-cases the query).
    await tester.tap(find.byTooltip('Clear search'));
    await settle(tester);
    await search(tester, 'INVOICE');
    expect(find.text('Overdue invoice'), findsOneWidget);
  });

  testWidgets('tapping a stat card applies its filter, then Done clears it', (
    tester,
  ) async {
    final fixture = buildFixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await openTasks(tester);

    // The "Due today" card behaves like the Today chip.
    await tester.tap(find.text('Due today'));
    await settle(tester);
    expect(find.text('Today report'), findsOneWidget);
    expect(find.text('Overdue report'), findsNothing);
    expect(find.text('Done report'), findsNothing);

    // "Done" shows only completed tasks, whatever their due date.
    await tester.tap(find.widgetWithText(ChoiceChip, 'Done'));
    await settle(tester);
    expect(find.text('Done report'), findsOneWidget);
    expect(find.text('Today report'), findsNothing);

    // Back to All: every bucket is listed again.
    await tester.tap(find.widgetWithText(ChoiceChip, 'All'));
    await settle(tester);
    expect(find.text('Overdue report'), findsOneWidget);
    expect(find.text('Today report'), findsOneWidget);
    // The completed section is last and the list is lazy.
    final scrollable = find.descendant(
      of: find.byType(ListView),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Done report'),
      150,
      scrollable: scrollable,
    );
    expect(find.text('Done report'), findsOneWidget);
  });
}
