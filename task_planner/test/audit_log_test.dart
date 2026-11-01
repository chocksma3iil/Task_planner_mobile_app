import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';

import 'support/app_harness.dart';

/// Audit-log widget tests (D06): the admin-only entry point on the dashboard,
/// newest-first rendering, and the project filter.
void main() {
  testWidgets('admin opens the audit log and sees labelled entries', (
    tester,
  ) async {
    final fixture = Fixture();
    fixture.api
      ..addAuditLog(
        action: 'project.created',
        actor: fixture.admin,
        entityType: 'project',
        entityId: 1,
        projectId: 1,
        details: '{"name":"Alpha"}',
      )
      ..addAuditLog(
        action: 'member.role_changed',
        actor: fixture.admin,
        entityId: 3,
        projectId: 1,
        details: '{"name":"Bob Builder","from":"user","to":"team_lead"}',
      );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);
    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);

    expect(find.text('Audit log'), findsWidgets);
    expect(find.text('Project created'), findsOneWidget);
    expect(find.text('Member role changed'), findsOneWidget);
    expect(find.textContaining('Root Admin'), findsWidgets);
    // Newest first: the role change is above the project creation.
    final roleY = tester.getTopLeft(find.text('Member role changed')).dy;
    final projectY = tester.getTopLeft(find.text('Project created')).dy;
    expect(roleY, lessThan(projectY));
  });

  testWidgets('owners do not see the audit entry point', (tester) async {
    final fixture = Fixture();
    fixture.api.addAuditLog(
      action: 'project.created',
      actor: fixture.admin,
      entityType: 'project',
      entityId: 1,
      projectId: 1,
    );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);
    await tester.tap(find.text('Dashboard'));
    await settle(tester);

    expect(find.byTooltip('Audit log'), findsNothing);
    expect(find.text('Project Dashboard'), findsOneWidget);
  });

  testWidgets('the project filter narrows the trail', (tester) async {
    final fixture = Fixture();
    fixture.api
      ..addProject(
        Project(id: 2, name: 'Beta', createdAt: DateTime(2026, 1, 1)),
      )
      ..addAuditLog(
        action: 'project.created',
        actor: fixture.admin,
        entityType: 'project',
        entityId: 1,
        projectId: 1,
      )
      ..addAuditLog(
        action: 'member.created',
        actor: fixture.admin,
        entityId: 9,
        projectId: 2,
      );

    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);
    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.byTooltip('Audit log'));
    await settle(tester);

    expect(find.text('Project created'), findsOneWidget);
    expect(find.text('Member created'), findsOneWidget);

    await tester.tap(find.byTooltip('Filter by project'));
    await settle(tester);
    await tester.tap(find.text('Beta').last);
    await settle(tester);

    expect(find.text('Member created'), findsOneWidget);
    expect(find.text('Project created'), findsNothing);
  });
}
