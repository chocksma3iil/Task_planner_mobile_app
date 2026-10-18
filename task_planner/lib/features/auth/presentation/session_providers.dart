import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database.dart';
import '../application/auth_service.dart';

/// The open database. Overridden in `main` with the real one.
final databaseProvider = Provider<AppDatabase>(
  (_) => throw UnimplementedError('Database not initialized.'),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(ref.watch(databaseProvider)),
);

/// Logged-in account id. Null means logged out.
class SessionUserId extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? id) => state = id;
}

final sessionUserIdProvider =
    NotifierProvider<SessionUserId, int?>(SessionUserId.new);

/// Pings the router when the session changes.
class SessionRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final sessionRefreshProvider =
    Provider<SessionRefresh>((_) => SessionRefresh());

/// The logged-in account row, or null when logged out.
final currentUserProvider = StreamProvider<Assignee?>((ref) {
  final db = ref.watch(databaseProvider);
  final id = ref.watch(sessionUserIdProvider);
  if (id == null) {
    return Stream.value(null);
  }
  return (db.select(db.assignees)..where((t) => t.id.equals(id)))
      .watchSingleOrNull();
});

/// Logs in and refreshes navigation. Throws [StateError] on failure.
Future<void> logIn(WidgetRef ref, Assignee account) async {
  ref.read(sessionUserIdProvider.notifier).set(account.id);
  ref.read(sessionRefreshProvider).ping();
}

/// Logs out and refreshes navigation.
Future<void> logOut(WidgetRef ref) async {
  ref.read(sessionUserIdProvider.notifier).set(null);
  ref.read(sessionRefreshProvider).ping();
}
