/// Comment widget tests (D05): comment sheet, create/edit/delete, viewer read-only.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:task_planner/models/comment.dart';
import 'package:task_planner/widgets/tasks/comment_sheet.dart';
import 'support/app_harness.dart';

void main() {
  testWidgets('creating a comment shows it in the list', (
    tester,
  ) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await tester.tap(find.text('Tasks'));
    await settle(tester);

    // Post a comment via the comment icon on the first task tile
    await tester.tap(find.byIcon(Icons.comment_outlined).first);
    await settle(tester);
    expect(find.byType(CommentSheet), findsOneWidget);

    await tester.enterText(
      find.descendant(
        of: find.byType(CommentSheet),
        matching: find.byType(TextField),
      ),
      'Hello world',
    );
    await tester.tap(find.descendant(
      of: find.byType(CommentSheet),
      matching: find.byType(FilledButton),
    ));
    await settle(tester);

    expect(find.text('Hello world'), findsOneWidget);
    expect(find.text('No comments yet.'), findsNothing);
  });

  testWidgets('viewer cannot post a comment', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(tester, fixture.api, account: fixture.viewer);
    await tester.tap(find.text('Tasks'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.comment_outlined).first);
    await settle(tester);
    expect(find.byType(CommentSheet), findsOneWidget);
    // Viewer sees no composer
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('editing a comment updates the body', (tester) async {
    final fixture = Fixture();
    fixture.api.comments.add(Comment(
      id: 1,
      taskId: 1,
      authorId: fixture.user.id,
      body: 'Original comment',
      mentions: const [],
      createdAt: DateTime(2026, 1, 1),
    ));
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await tester.tap(find.text('Tasks'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.comment_outlined).first);
    await settle(tester);
    expect(find.byType(CommentSheet), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_outlined).first);
    await settle(tester);
    await tester.enterText(
      find.byType(TextField).last,
      'Updated comment',
    );
    await tester.tap(find.text('Save').last);
    await settle(tester);

    expect(find.text('Updated comment'), findsOneWidget);
    expect(find.text('Original comment'), findsNothing);
  });

  testWidgets('deleting a comment soft-deletes it', (tester) async {
    final fixture = Fixture();
    fixture.api.comments.add(Comment(
      id: 1,
      taskId: 1,
      authorId: fixture.user.id,
      body: 'To be deleted',
      mentions: const [],
      createdAt: DateTime(2026, 1, 1),
    ));
    await pumpTaskPlanner(tester, fixture.api, account: fixture.user);
    await tester.tap(find.text('Tasks'));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.comment_outlined).first);
    await settle(tester);
    expect(find.byType(CommentSheet), findsOneWidget);
    expect(find.text('To be deleted'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.delete_outlined).first);
    await settle(tester);
    await tester.tap(find.text('Delete').first);
    await settle(tester);

    expect(find.text('[message supprimé]'), findsOneWidget);
  });
}
