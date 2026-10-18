import 'package:drift/drift.dart';

import '../../../core/database.dart';
import '../../../core/rules.dart';
import '../../../core/security.dart';

/// Login, sign-up, and session-adjacent account operations.
///
/// Role checks live here (application layer), never only in widgets.
class AuthService {
  AuthService(this._db);

  final AppDatabase _db;

  /// Registers an account. The very first account on a fresh install becomes
  /// the active admin (bootstrap); every later sign-up picks a project and
  /// starts pending until its owner confirms it.
  Future<Assignee> signUp({
    required String name,
    required String email,
    required String password,
    String? position,
    int? projectId,
  }) async {
    await _requireUniqueEmail(email);
    final existing = await _db.select(_db.assignees).get();
    if (existing.isEmpty) {
      return _insert(
        name: name,
        email: email,
        password: password,
        position: position,
        projectId: null,
        role: Roles.admin,
        status: MemberStatus.active,
      );
    }
    if (projectId == null) {
      throw ArgumentError('Choose a project to join.');
    }
    return _insert(
      name: name,
      email: email,
      password: password,
      position: position,
      projectId: projectId,
      role: Roles.user,
      status: MemberStatus.pending,
    );
  }

  /// Returns the account when credentials are valid and active.
  /// Throws [StateError] for unknown accounts, wrong passwords, and
  /// pending accounts awaiting owner confirmation.
  Future<Assignee> login({
    required String email,
    required String password,
  }) async {
    final account = await (_db.select(_db.assignees)
          ..where((t) => t.email.equals(email)))
        .getSingleOrNull();
    if (account == null ||
        !PasswordHasher.verify(password, account.passwordHash)) {
      throw StateError('Wrong email or password.');
    }
    if (!canLogIn(account.status)) {
      throw StateError('Account is waiting for project owner confirmation.');
    }
    return account;
  }

  Future<void> _requireUniqueEmail(String email) async {
    final hit = await (_db.select(_db.assignees)
          ..where((t) => t.email.equals(email)))
        .getSingleOrNull();
    if (hit != null) {
      throw StateError('An account with this email already exists.');
    }
  }

  Future<Assignee> _insert({
    required String name,
    required String email,
    required String password,
    required String? position,
    required int? projectId,
    required String role,
    required String status,
  }) async {
    final id = await _db.into(_db.assignees).insert(
          AssigneesCompanion.insert(
            name: name,
            position: Value(position),
            projectId: Value(projectId),
            email: email,
            passwordHash: PasswordHasher.hash(password),
            role: Value(role),
            status: Value(status),
          ),
        );
    return (await (_db.select(_db.assignees)
              ..where((t) => t.id.equals(id)))
            .getSingle());
  }
}
