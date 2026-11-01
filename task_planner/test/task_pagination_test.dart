import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/providers/data_providers.dart';

import 'support/app_harness.dart';

/// C07: reaching the bottom of the list must fetch and append page 2 instead
/// of reloading page 1.
void main() {
  testWidgets('scrolling to the bottom appends the next page', (tester) async {
    final fixture = Fixture();
    // 25 rows, page size 20: created newest first so page 1 is Task 1..20
    // and page 2 is Task 21..25.
    final base = DateTime(2026, 1, 1, 12);
    for (var i = 1; i <= 25; i += 1) {
      fixture.api.addTask(
        Task(
          id: i,
          title: 'Task $i',
          projectId: fixture.project.id,
          createdAt: base.subtract(Duration(minutes: i)),
        ),
      );
    }

    final container = await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.user,
    );
    await tester.tap(find.text('Tasks'));
    await settle(tester);

    final provider = projectTasksProvider(fixture.project.id);
    var state = container.read(provider).value!;
    expect(state.items.length, 20);
    expect(state.hasMore, isTrue);
    expect(find.text('Task 21'), findsNothing);

    // Drag to the end of page 1; the scroll listener loads page 2.
    final list = find.byType(ListView);
    await tester.drag(list, const Offset(0, -4000));
    await settle(tester, frames: 20);

    state = container.read(provider).value!;
    expect(state.items.length, 25);
    expect(state.items.map((t) => t.id).toSet().length, 25);
    expect(state.hasMore, isFalse);
    expect(state.isLoadingMore, isFalse);

    // The appended rows are reachable and no page-1 row was dropped.
    final scrollable = find.descendant(
      of: list,
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.text('Task 25'),
      200,
      scrollable: scrollable,
    );
    expect(find.text('Task 25'), findsOneWidget);
    expect(find.text('Task 1'), findsNothing);
  });
}
