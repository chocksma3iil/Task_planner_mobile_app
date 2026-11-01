import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/services/task_service.dart';

import 'support/app_harness.dart';

void main() {
  test('a successful mutation refreshes subscribed task streams', () async {
    final fixture = Fixture();
    fixture.api.me = fixture.admin;
    final service = TaskService(fixture.api);
    final values = <int>[];
    final subscription = service
        .watchProjectTasks(fixture.project.id)
        .listen((tasks) => values.add(tasks.items.length));
    addTearDown(
      () => subscription.cancel().timeout(const Duration(seconds: 2)),
    );

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(values, [0]);

    await service.createTask(
      projectId: fixture.project.id,
      title: 'Synced task',
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));

    expect(values, [0, 1]);
    expect(fixture.api.tasks.single.title, 'Synced task');
  });
}
