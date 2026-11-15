import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/models/models.dart';

import 'support/app_harness.dart';
import 'support/fake_api_client.dart';

const _genericMessage =
    'If the account exists, a reset code has been sent.';

void main() {
  testWidgets('unknown emails get the same generic confirmation', (
    tester,
  ) async {
    final api = FakeApiClient();
    api.addAccount(
      const Account(
        id: 1,
        name: 'Root Admin',
        email: 'root@example.com',
        role: 'admin',
        status: 'active',
      ),
    );
    await pumpTaskPlanner(tester, api);

    await tester.tap(find.text('Forgot password?'));
    await settle(tester);
    expect(find.text('Reset password'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'missing@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset code'));
    await settle(tester);

    expect(find.text(_genericMessage), findsOneWidget);
    expect(api.resetCodes.containsKey('missing@example.com'), isFalse);
    // The code step is available even though no code was issued.
    expect(
      find.widgetWithText(FilledButton, 'Reset password'),
      findsOneWidget,
    );
  });

  testWidgets('a valid code sets a new password and returns to login', (
    tester,
  ) async {
    final api = FakeApiClient();
    api.addAccount(
      const Account(
        id: 1,
        name: 'Root Admin',
        email: 'root@example.com',
        role: 'admin',
        status: 'active',
      ),
    );
    await pumpTaskPlanner(tester, api);

    await tester.tap(find.text('Forgot password?'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'root@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset code'));
    await settle(tester);

    expect(api.resetCodes['root@example.com'], 'reset-code-1');
    expect(find.text(_genericMessage), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Reset code'),
      'reset-code-1',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'brand-new-pass-1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await settle(tester);

    expect(api.passwords['root@example.com'], 'brand-new-pass-1');
    expect(find.text('Password updated. Log in with the new password.'),
        findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Log in'), findsOneWidget);

    // The new password opens a real session.
    await tester.enterText(find.byType(TextField).at(0), 'root@example.com');
    await tester.enterText(find.byType(TextField).at(1), 'brand-new-pass-1');
    await tester.tap(find.widgetWithText(FilledButton, 'Log in'));
    await settle(tester);

    expect(api.token, 'fake-token');
    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });

  testWidgets('an invalid code shows the server message', (tester) async {
    final api = FakeApiClient();
    api.addAccount(
      const Account(
        id: 1,
        name: 'Root Admin',
        email: 'root@example.com',
        role: 'admin',
        status: 'active',
      ),
    );
    await pumpTaskPlanner(tester, api);

    await tester.tap(find.text('Forgot password?'));
    await settle(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Email'),
      'root@example.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Send reset code'));
    await settle(tester);

    await tester.enterText(
      find.widgetWithText(TextField, 'Reset code'),
      'not-a-real-code',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'New password'),
      'brand-new-pass-1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Reset password'));
    await settle(tester);

    expect(find.text('Invalid or expired reset code.'), findsOneWidget);
    expect(api.passwords['root@example.com'], 'password123');
    expect(find.widgetWithText(FilledButton, 'Reset password'),
        findsOneWidget);
  });
}
