import 'package:drift/drift.dart';

import '../../../core/database.dart';
import '../../../core/rules.dart';
import '../../../core/security.dart';

/// User management: creation by admins/owners, owner confirmation of
/// self-registered accounts, and admin-only role changes.
class MemberService {
  MemberService(this._db);

  final AppDatabase _db;

  /// Creates an active user directly. Admins may create anywhere with any
  /// role; owners may only create plain users inside their own project.
  Future<Assignee> createUser({
    required Assignee actor,
    required String name,
    required String email,
    required String password,
    String? position,
    int? projectId,
    String role = Roles.user,
  }) async {
    if (isAdmin(actor.role)) {
      // Admins may create anywhere.
    } else {
      requireOwnerOrAdmin(actor.role);
      if (role != Roles.user || projectId != actor.projectId) {
        throw StateError('Owners can only add plain users to their project.');
      }
    }
    await _requireUniqueEmail(email);
    final id = await _db.into(_db.assignees).insert(
          AssigneesCompanion.insert(
            name: name,
            position: Value(position),
            projectId: Value(projectId),
            email: email,
            passwordHash: PasswordHasher.hash(password),
            role: Value(role),
            status: const Value(MemberStatus.active),
            approvedBy: Value(actor.id),
          ),
        );
    return _byId(id);
  }

  /// Moves a pending account to active. Allowed for admins everywhere and
  /// for owners inside their own project. Records the confirmer.
  Future<Assignee> confirmUser({
    required Assignee actor,
    required int userId,
  }) async {
    final target = await _byId(userId);
    if (!isAdmin(actor.role)) {
      requireOwnerOrAdmin(actor.role);
      if (actor.projectId == null ||
          target.projectId != actor.projectId) {
        throw StateError('You can only confirm your own project members.');
      }
    }
    await (_db.update(_db.assignees)..where((t) => t.id.equals(userId))).write(
      AssigneesCompanion(
        status: const Value(MemberStatus.active),
        approvedBy: Value(actor.id),
      ),
    );
    return _byId(userId);
  }

  /// Admin-only role changes.
  Future<Assignee> changeRole({
    required Assignee actor,
    required int userId,
    required String role,
  }) async {
    requireAdmin(actor.role);
    await (_db.update(_db.assignees)..where((t) => t.id.equals(userId))).write(
      AssigneesCompanion(role: Value(role)),
    );
    return _byId(userId);
  }

  /// Members visible to [viewer]: everyone for admins, own project otherwise.
  ///
  /// Throws [StateError] for a non-admin without a project instead of
  /// crashing on a null check, so screens can show a clear error.
  Stream<List<Assignee>> watchVisibleMembers(Assignee viewer) {
    final query = _db.select(_db.assignees)
      ..orderBy([(t) => OrderingTerm(expression: t.name)]);
    if (!isAdmin(viewer.role)) {
      final projectId = viewer.projectId;
      if (projectId == null) {
        throw StateError('Account has not been assigned to a project.');
      }
      query.where((t) => t.projectId.equals(projectId));
    }
    return query.watch();
  }

  Future<Assignee> _byId(int id) {
    return (_db.select(_db.assignees)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  Future<void> _requireUniqueEmail(String email) async {
    final hit = await (_db.select(_db.assignees)
          ..where((t) => t.email.equals(email)))
        .getSingleOrNull();
    if (hit != null) {
      throw StateError('An account with this email already exists.');
    }
  }
}
