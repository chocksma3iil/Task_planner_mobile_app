import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'rules.dart';

part 'database.g.dart';

/// Projects group assignees and tasks. Created by admins, who assign owners.
class Projects extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant('active'))();
  IntColumn get ownerId => integer().nullable().references(Assignees, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// People: the local account table. Each person belongs to exactly one
/// project, except global admins whose [projectId] is null.
///
/// `position` is a display-only job title, unrelated to the access [role].
/// `approvedBy` records the owner who confirmed a self-registered account.
class Assignees extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get position => text().nullable()();
  IntColumn get projectId => integer().nullable().references(Projects, #id)();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  TextColumn get role => text().withDefault(const Constant(Roles.user))();
  TextColumn get status =>
      text().withDefault(const Constant(MemberStatus.pending))();
  // Plain id on purpose (no SQL self-FK): enforced in the service layer.
  IntColumn get approvedBy => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// Tasks belong to a project. Assigned to the whole project
/// ([assigneeId] null) or to one person from that project — never both.
class Tasks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text()();
  TextColumn get description => text().nullable()();
  TextColumn get status => text().withDefault(const Constant(TaskStatus.todo))();
  TextColumn get priority => text().withDefault(const Constant('medium'))();
  DateTimeColumn get dueDate => dateTime().nullable()();
  IntColumn get projectId => integer().references(Projects, #id)();
  IntColumn get assigneeId => integer().nullable().references(Assignees, #id)();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get completedAt => dateTime().nullable()();
}

/// Device-level key/value settings (e.g. the theme mode). Not scoped to an
/// account: it is a preference of the person using this device.
class AppSettings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();
  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Projects, Assignees, Tasks, AppSettings])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  /// In-memory database for tests.
  AppDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(appSettings);
          }
        },
      );
}
