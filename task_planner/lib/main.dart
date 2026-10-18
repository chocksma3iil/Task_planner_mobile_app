import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'app/app.dart';
import 'core/database.dart';
import 'features/auth/presentation/session_providers.dart';

/// Opens the persistent on-device database.
Future<AppDatabase> openAppDatabase() async {
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/task_planner.sqlite');
  return AppDatabase(LazyDatabase(() async => NativeDatabase(file)));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final db = await openAppDatabase();
  runApp(
    ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const TaskPlannerApp(),
    ),
  );
}
