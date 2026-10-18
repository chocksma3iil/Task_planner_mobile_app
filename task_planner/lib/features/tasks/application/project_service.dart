import 'package:drift/drift.dart';

import '../../../core/database.dart';
import '../../../core/rules.dart';

/// Project management. Only admins create projects and assign owners.
/// Assigning an owner also moves them into the project as a project owner.
class ProjectService {
  ProjectService(this._db);

  final AppDatabase _db;

  Future<Project> createProject({
    required Assignee actor,
    required String name,
    String? description,
  }) async {
    requireAdmin(actor.role);
    final id = await _db.into(_db.projects).insert(
          ProjectsCompanion.insert(
            name: name,
            description: Value(description),
          ),
        );
    return _byId(id);
  }

  Future<Project> assignOwner({
    required Assignee actor,
    required int projectId,
    required int ownerId,
  }) async {
    requireAdmin(actor.role);
    final owner = await (_db.select(_db.assignees)
          ..where((t) => t.id.equals(ownerId)))
        .getSingle();
    if (!canLogIn(owner.status)) {
      throw StateError('The owner account must be active.');
    }
    await (_db.update(_db.assignees)..where((t) => t.id.equals(ownerId))).write(
      AssigneesCompanion(
        projectId: Value(projectId),
        role: const Value(Roles.projectOwner),
      ),
    );
    await (_db.update(_db.projects)..where((t) => t.id.equals(projectId)))
        .write(ProjectsCompanion(ownerId: Value(ownerId)));
    return _byId(projectId);
  }

  Stream<List<Project>> watchProjects() {
    return (_db.select(_db.projects)
          ..orderBy([(t) => OrderingTerm(expression: t.name)]))
        .watch();
  }

  Stream<List<Project>> watchOwnProjects(Assignee viewer) {
    final query = _db.select(_db.projects)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (!isAdmin(viewer.role)) {
      query.where((t) => t.id.equals(viewer.projectId!));
    }
    return query.watch();
  }

  Future<Project> _byId(int id) {
    return (_db.select(_db.projects)..where((t) => t.id.equals(id)))
        .getSingle();
  }
}
