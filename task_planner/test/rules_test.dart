import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/core/rules.dart';

void main() {
  group('task assignment', () {
    test('project-level assignment needs no person', () {
      validateTaskAssignment(
        taskProjectId: 1,
        assigneeId: null,
        assigneeProjectId: null,
      );
    });

    test('person from the same project is accepted', () {
      validateTaskAssignment(
        taskProjectId: 1,
        assigneeId: 7,
        assigneeProjectId: 1,
      );
    });

    test('person from another project is rejected', () {
      expect(
        () => validateTaskAssignment(
          taskProjectId: 1,
          assigneeId: 7,
          assigneeProjectId: 2,
        ),
        throwsArgumentError,
      );
    });
  });

  group('login gate', () {
    test('active accounts can log in', () {
      expect(canLogIn(MemberStatus.active), isTrue);
    });

    test('pending accounts cannot log in', () {
      expect(canLogIn(MemberStatus.pending), isFalse);
    });
  });

  group('roles', () {
    test('admin sees all three tabs in order', () {
      expect(visibleTabs(Roles.admin), ['projects', 'members', 'tasks']);
    });

    test('owner and user see members, tasks, and mine', () {
      expect(visibleTabs(Roles.projectOwner), ['members', 'tasks', 'mine']);
      expect(visibleTabs(Roles.user), ['members', 'tasks', 'mine']);
    });

    test('requireAdmin rejects non-admins', () {
      expect(() => requireAdmin(Roles.user), throwsStateError);
      expect(() => requireAdmin(Roles.projectOwner), throwsStateError);
      requireAdmin(Roles.admin);
    });

    test('requireOwnerOrAdmin rejects plain users', () {
      expect(() => requireOwnerOrAdmin(Roles.user), throwsStateError);
      requireOwnerOrAdmin(Roles.projectOwner);
      requireOwnerOrAdmin(Roles.admin);
    });
  });

  group('planner classifiers', () {
    final now = DateTime(2026, 10, 12, 15, 30);

    test('overdue is incomplete with a past due date', () {
      expect(
        isOverdue(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 11, 23, 59),
          now: now,
        ),
        isTrue,
      );
    });

    test('completed tasks never match today/upcoming/overdue', () {
      const status = TaskStatus.completed;
      expect(
        isOverdue(status: status, dueDate: DateTime(2026, 10, 11), now: now),
        isFalse,
      );
      expect(
        isDueToday(status: status, dueDate: DateTime(2026, 10, 12), now: now),
        isFalse,
      );
      expect(
        isUpcoming(status: status, dueDate: DateTime(2026, 10, 13), now: now),
        isFalse,
      );
    });

    test('today matches the calendar day regardless of time', () {
      expect(
        isDueToday(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 12, 0, 0),
          now: now,
        ),
        isTrue,
      );
      expect(
        isDueToday(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 13),
          now: now,
        ),
        isFalse,
      );
    });

    test('upcoming is incomplete with a future due date', () {
      expect(
        isUpcoming(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 13),
          now: now,
        ),
        isTrue,
      );
      expect(
        isUpcoming(
          status: TaskStatus.todo,
          dueDate: DateTime(2026, 10, 12),
          now: now,
        ),
        isFalse,
      );
    });

    test('tasks without a due date match nothing', () {
      expect(
        isOverdue(status: TaskStatus.todo, dueDate: null, now: now),
        isFalse,
      );
      expect(
        isDueToday(status: TaskStatus.todo, dueDate: null, now: now),
        isFalse,
      );
      expect(
        isUpcoming(status: TaskStatus.todo, dueDate: null, now: now),
        isFalse,
      );
    });
  });
}
