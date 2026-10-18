// Seeds demo accounts, a project, and tasks into the real app database.
//
// Idempotent: rows whose email/title already exist are skipped, so it is
// safe to re-run. Uses the same services and password hashing as the app.
//
// Run from the task_planner/ directory:
//   dart run tool/seed_users.dart [path\to\task_planner.sqlite]
import 'dart:io';

import 'package:drift/native.dart';
import 'package:task_planner/core/database.dart';
import 'package:task_planner/core/rules.dart';
import 'package:task_planner/features/auth/application/auth_service.dart';
import 'package:task_planner/features/tasks/application/member_service.dart';
import 'package:task_planner/features/tasks/application/project_service.dart';
import 'package:task_planner/features/tasks/application/task_service.dart';

/// Default location used by the app via path_provider on Windows.
String _defaultDbPath() {
  final profile = Platform.environment['USERPROFILE'] ??
      Platform.environment['HOME'] ??
      '';
  return '$profile\\Documents\\task_planner.sqlite';
}

Future<void> main(List<String> args) async {
  final path = args.isNotEmpty ? args.first : _defaultDbPath();
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('Database not found: $path');
    stderr.writeln('Run the app once first, or pass the sqlite file path.');
    exitCode = 1;
    return;
  }

  final db = AppDatabase(NativeDatabase(file));
  try {
    await _seed(db);
  } finally {
    await db.close();
  }
}

Future<void> _seed(AppDatabase db) async {
  final auth = AuthService(db);
  final members = MemberService(db);
  final projects = ProjectService(db);
  final tasks = TaskService(db);

  // 1. Bootstrap admin — only possible while the account table is empty.
  final existing = await db.select(db.assignees).get();
  Assignee admin;
  if (existing.isEmpty) {
    admin = await auth.signUp(
      name: 'Admin',
      email: 'admin@local.dev',
      password: 'admin123',
    );
    stdout.writeln('Created bootstrap admin: admin@local.dev / admin123');
  } else {
    admin = existing.firstWhere(
      (a) => a.role == Roles.admin,
      orElse: () => throw StateError(
        'No admin account exists and the table is not empty; '
        'cannot seed safely.',
      ),
    );
    stdout.writeln('Using existing admin: ${admin.email}');
  }

  // 2. Demo project owned by admin until an owner is assigned below.
  const projectName = 'Mobile App Launch';
  final allProjects = await db.select(db.projects).get();
  Project project;
  final existingProject =
      allProjects.where((p) => p.name == projectName).firstOrNull;
  if (existingProject != null) {
    project = existingProject;
    stdout.writeln('Using existing project: $projectName (#${project.id})');
  } else {
    project = await projects.createProject(
      actor: admin,
      name: projectName,
      description: 'Demo project seeded by tool/seed_users.dart',
    );
    stdout.writeln('Created project: $projectName (#${project.id})');
  }

  // 3. Active members (created by the admin, immediately active).
  final memberSpecs = [
    (name: 'Alice Designer', email: 'alice@local.dev', position: 'UI Designer'),
    (name: 'Bob Developer', email: 'bob@local.dev', position: 'Developer'),
  ];
  final membersNow = await db.select(db.assignees).get();
  final byEmail = {
    for (final a in membersNow) a.email: a,
  };
  final created = <Assignee>[];
  for (final spec in memberSpecs) {
    if (byEmail.containsKey(spec.email)) {
      stdout.writeln('User already exists: ${spec.email}');
      created.add(byEmail[spec.email]!);
      continue;
    }
    final user = await members.createUser(
      actor: admin,
      name: spec.name,
      email: spec.email,
      password: 'password123',
      position: spec.position,
      projectId: project.id,
    );
    created.add(user);
    stdout.writeln(
        'Created user: ${spec.email} / password123 (${spec.position})');
  }

  // 4. Pending self-registration — cannot log in until confirmed.
  const pendingEmail = 'carol@local.dev';
  Assignee? carol = byEmail[pendingEmail];
  if (carol == null) {
    carol = await auth.signUp(
      name: 'Carol Guest',
      email: pendingEmail,
      password: 'password123',
      position: 'Guest',
      projectId: project.id,
    );
    stdout.writeln(
        'Created pending user: $pendingEmail / password123 '
        '(needs owner confirmation)');
  } else {
    stdout.writeln('Pending user already exists: $pendingEmail');
  }

  // 5. Make Alice the project owner (admin-only operation).
  final alice = created.firstWhere((a) => a.email == 'alice@local.dev');
  final refreshedProject =
      await (db.select(db.projects)..where((t) => t.id.equals(project.id)))
          .getSingle();
  if (refreshedProject.ownerId != alice.id) {
    await projects.assignOwner(
      actor: admin,
      projectId: project.id,
      ownerId: alice.id,
    );
    stdout.writeln('Assigned project owner: alice@local.dev');
  } else {
    stdout.writeln('Project owner already set: alice@local.dev');
  }

  // 6. A few demo tasks (due dates relative to today).
  final bob = created.firstWhere((a) => a.email == 'bob@local.dev');
  final now = DateTime.now();
  DateTime day(int offset) =>
      DateTime(now.year, now.month, now.day + offset);
  final taskSpecs = [
    (title: 'Design the onboarding screens', assignee: alice, due: day(1)),
    (title: 'Set up project repository', assignee: bob, due: day(0)),
    (title: 'Write the launch checklist', assignee: null, due: day(3)),
    (title: 'Fix login layout overflow', assignee: bob, due: day(-1)),
  ];
  final existingTasks =
      await (db.select(db.tasks)..where((t) => t.projectId.equals(project.id)))
          .get();
  final taskTitles = existingTasks.map((t) => t.title).toSet();
  for (final spec in taskSpecs) {
    if (taskTitles.contains(spec.title)) {
      stdout.writeln('Task already exists: ${spec.title}');
      continue;
    }
    await tasks.createTask(
      actor: admin,
      projectId: project.id,
      title: spec.title,
      dueDate: spec.due,
      assigneeId: spec.assignee?.id,
    );
    stdout.writeln('Created task: ${spec.title}');
  }

  stdout.writeln('\nSeed complete. Login accounts:');
  stdout.writeln('  admin@local.dev      / admin123     (admin)');
  stdout.writeln('  alice@local.dev      / password123  (project owner)');
  stdout.writeln('  bob@local.dev        / password123  (user)');
  stdout.writeln('  carol@local.dev      / password123  (pending, cannot log in)');
}
