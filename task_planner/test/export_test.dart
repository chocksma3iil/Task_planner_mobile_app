import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:task_planner/providers/data_providers.dart';
import 'package:task_planner/services/export_service.dart';

import 'support/app_harness.dart';

/// Export widget tests (E03): the dashboard menu downloads through the API
/// and hands the bytes to the (injectable) saver — never a platform channel.
void main() {
  testWidgets('exporting CSV saves the downloaded bytes', (tester) async {
    final fixture = Fixture();
    fixture.api.exportBytes['format=csv'] = utf8.encode(
      'id,title\r\n1,Alpha task\r\n',
    );
    SavedExport? saved;
    await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.owner,
      overrides: [
        exportServiceProvider.overrideWithValue(
          ExportService(fixture.api, onSave: (export) async => saved = export),
        ),
      ],
    );

    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.byTooltip('Export'));
    await settle(tester);
    await tester.tap(find.text('Export CSV'));
    await settle(tester);

    expect(saved, isNotNull);
    expect(saved!.name, 'project-1-report');
    expect(saved!.extension, 'csv');
    expect(utf8.decode(saved!.bytes), contains('Alpha task'));
    expect(
      fixture.api.byteRequests.single,
      '/projects/1/export?format=csv',
    );
    expect(find.text('CSV report downloaded.'), findsOneWidget);
  });

  testWidgets('exporting PDF saves the downloaded bytes', (tester) async {
    final fixture = Fixture();
    fixture.api.exportBytes['format=pdf'] = ascii.encode('%PDF-1.7 fake');
    SavedExport? saved;
    await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.user,
      overrides: [
        exportServiceProvider.overrideWithValue(
          ExportService(fixture.api, onSave: (export) async => saved = export),
        ),
      ],
    );

    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.byTooltip('Export'));
    await settle(tester);
    await tester.tap(find.text('Export PDF'));
    await settle(tester);

    expect(saved, isNotNull);
    expect(saved!.extension, 'pdf');
    expect(ascii.decode(saved!.bytes), startsWith('%PDF'));
    expect(find.text('PDF report downloaded.'), findsOneWidget);
  });

  testWidgets('a failed download surfaces the error', (tester) async {
    final fixture = Fixture();
    await pumpTaskPlanner(
      tester,
      fixture.api,
      account: fixture.owner,
      overrides: [
        exportServiceProvider.overrideWithValue(
          ExportService(fixture.api, onSave: (_) async {}),
        ),
      ],
    );

    await tester.tap(find.text('Dashboard'));
    await settle(tester);
    await tester.tap(find.byTooltip('Export'));
    await settle(tester);
    await tester.tap(find.text('Export CSV'));
    await settle(tester);

    expect(find.textContaining('Unexpected download'), findsOneWidget);
  });
}
