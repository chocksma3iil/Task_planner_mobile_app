import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';
import 'package:task_planner/providers/data_providers.dart';
import 'package:task_planner/widgets/members/add_member_dialog.dart';
import 'package:task_planner/widgets/members/member_card.dart';

import 'support/app_harness.dart';

void main() {
  testWidgets('owner confirms a pending account', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);

    expect(find.text('Waiting for confirmation'), findsOneWidget);
    expect(find.text('Carol Guest'), findsWidgets);

    await tester.tap(find.text('Confirm'));
    await settle(tester);

    final carol = fixture.api.members.firstWhere((m) => m.id == fixture.pending.id);
    expect(carol.status, 'active');
    expect(carol.approvedBy, fixture.owner.id);
    expect(find.text('Waiting for confirmation'), findsNothing);
  });

  testWidgets('team lead confirms a pending user in their project', (
    tester,
  ) async {
    final fixture = Fixture();
    final lead = Account(
      id: 9,
      name: 'Tina Lead',
      email: 'tina@example.com',
      projectId: fixture.project.id,
      role: 'team_lead',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
    );
    fixture.api.addAccount(lead);
    await pumpTaskPlanner(tester, fixture.api, account: lead);

    // Team leads share the owner's pending/active view but never the
    // admin-only role menu.
    expect(find.text('Waiting for confirmation'), findsOneWidget);
    expect(find.byTooltip('Add user'), findsOneWidget);
    expect(find.byTooltip('Change role'), findsNothing);

    await tester.tap(find.text('Confirm'));
    await settle(tester);

    final carol = fixture.api.members.firstWhere(
      (m) => m.id == fixture.pending.id,
    );
    expect(carol.status, 'active');
    expect(find.text('Waiting for confirmation'), findsNothing);
  });

  testWidgets('owner adds a plain user to their own project', (tester) async {
    final fixture = Fixture();
    final container = await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);

    await tester.tap(find.byTooltip('Add user'));
    await settle(tester);
    expect(find.byType(AddMemberDialog), findsOneWidget);
    expect(find.text('Project'), findsNothing);

    final fields = find.descendant(
      of: find.byType(AddMemberDialog),
      matching: find.byType(TextField),
    );
    await tester.enterText(fields.at(0), 'New Member');
    await tester.enterText(fields.at(1), 'new@example.com');
    await tester.enterText(fields.at(2), 'password123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await settle(tester);

    // Refresh the members provider so the new member appears in the roster.
    await container.read(visibleMembersProvider.notifier).refresh();
    await settle(tester);

    final created = fixture.api.members.firstWhere(
      (m) => m.email == 'new@example.com',
    );
    expect(created.role, 'user');
    expect(created.status, 'active');
    expect(created.projectId, fixture.project.id);
    expect(find.text('New Member'), findsWidgets);
  });

  testWidgets('plain users see names only and cannot add or confirm', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);

    expect(find.byTooltip('Add user'), findsNothing);
    expect(find.text('Confirm'), findsNothing);
    expect(find.text('Waiting for confirmation'), findsNothing);
    expect(find.text('active'), findsNothing);
    expect(find.text('pending'), findsNothing);
    expect(find.text('Carol Guest'), findsWidgets);
  });

  testWidgets('owner roster excludes accounts outside their project', (
    tester,
  ) async {
    final fixture = Fixture();
    fixture.api.addAccount(
      const Account(
        id: 9,
        name: 'Other Project',
        email: 'other@example.com',
        projectId: 2,
        role: 'user',
        status: 'active',
      ),
    );
    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);

    expect(find.text('Other Project'), findsNothing);
    expect(find.text('Root Admin'), findsNothing);
    expect(find.text('Bob Builder'), findsWidgets);
  });

  testWidgets('roster search narrows by name, email, and position', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);

    expect(find.text('Bob Builder'), findsWidgets);
    expect(find.text('Carol Guest'), findsWidgets);

    // By name.
    await tester.enterText(find.byType(TextField).first, 'bob');
    await settle(tester);
    expect(find.text('Bob Builder'), findsWidgets);
    expect(find.text('Carol Guest'), findsNothing);
    expect(find.text('Olive Owner'), findsNothing);

    // By email.
    await tester.enterText(find.byType(TextField).first, 'carol@example.com');
    await settle(tester);
    expect(find.text('Carol Guest'), findsWidgets);
    expect(find.text('Bob Builder'), findsNothing);

    // By position ("Project Manager"), lower-cased by the field.
    await tester.enterText(find.byType(TextField).first, 'manager');
    await settle(tester);
    expect(find.text('Olive Owner'), findsWidgets);
    expect(find.text('Bob Builder'), findsNothing);
    expect(find.text('Carol Guest'), findsNothing);

    // No match: the empty state replaces the roster.
    await tester.enterText(find.byType(TextField).first, 'nobody-here');
    await settle(tester);
    expect(find.text('No matches'), findsOneWidget);
    expect(find.text('Try a different search'), findsOneWidget);
    expect(find.text('Olive Owner'), findsNothing);
    expect(find.text('Bob Builder'), findsNothing);
  });

  testWidgets('member list errors surface with a working retry', (tester) async {
    final fixture = Fixture();
    fixture.api.membersError = 'offline';
    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);

    expect(find.textContaining('Could not load members'), findsOneWidget);
    fixture.api.membersError = null;
    await tester.tap(find.text('Retry'));
    await settle(tester);
    expect(find.text('Bob Builder'), findsWidgets);
  });

  testWidgets('admin changes a user role after confirmation', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);
    await tester.tap(find.text('Members'));
    await settle(tester);
    // The floating "Add user" button overlaps the bottom-right corner of the
    // last card at the default test viewport; scroll the card clear first.
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await settle(tester);

    final bobCard = find.ancestor(
      of: find.text('Bob Builder'),
      matching: find.byType(MemberCard),
    );
    expect(
      find.descendant(of: bobCard, matching: find.byTooltip('Change role')),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(of: bobCard, matching: find.byTooltip('Change role')),
    );
    await settle(tester);
    await tester.tap(find.text('Admin').last);
    await settle(tester);

    expect(find.text('Give admin access?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Make admin'));
    await settle(tester);

    expect(
      fixture.api.members.firstWhere((m) => m.id == fixture.user.id).role,
      'admin',
    );
  });

  testWidgets('admin assigns team lead and viewer roles from the menu', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);
    await tester.tap(find.text('Members'));
    await settle(tester);
    await tester.drag(find.byType(ListView), const Offset(0, -150));
    await settle(tester);

    Future<void> chooseRole(String label) async {
      final card = find.ancestor(
        of: find.text('Bob Builder'),
        matching: find.byType(MemberCard),
      );
      await tester.tap(
        find.descendant(of: card, matching: find.byTooltip('Change role')),
      );
      await settle(tester);
      await tester.tap(find.text(label).last);
      await settle(tester);
    }

    await chooseRole('Viewer');
    expect(
      fixture.api.members.firstWhere((m) => m.id == fixture.user.id).role,
      'viewer',
    );

    await chooseRole('Team lead');
    expect(
      fixture.api.members.firstWhere((m) => m.id == fixture.user.id).role,
      'team_lead',
    );
  });

  testWidgets('admins cannot change their own role or an owner role', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.admin);
    await tester.tap(find.text('Members'));
    await settle(tester);

    final adminCard = find.ancestor(
      of: find.text('Root Admin'),
      matching: find.byType(MemberCard),
    );
    final ownerCard = find.ancestor(
      of: find.text('Olive Owner'),
      matching: find.byType(MemberCard),
    );
    expect(
      find.descendant(of: adminCard, matching: find.byTooltip('Change role')),
      findsNothing,
    );
    expect(
      find.descendant(of: ownerCard, matching: find.byTooltip('Change role')),
      findsNothing,
    );
  });

  testWidgets('owners and users never see the role menu', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.owner);

    expect(find.text('Olive Owner'), findsWidgets);
    expect(find.byTooltip('Change role'), findsNothing);
  });
}
