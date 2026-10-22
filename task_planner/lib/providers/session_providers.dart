import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../services/data_sync.dart';
import 'api_providers.dart';

/// Logged-in account id. Null means logged out.
class SessionUserId extends Notifier<int?> {
  @override
  int? build() => null;

  void set(int? id) => state = id;
}

final sessionUserIdProvider = NotifierProvider<SessionUserId, int?>(
  SessionUserId.new,
);

/// Pings the router when the session changes.
class SessionRefresh extends ChangeNotifier {
  void ping() => notifyListeners();
}

final sessionRefreshProvider = Provider<SessionRefresh>(
  (_) => SessionRefresh(),
);

/// The logged-in account row, or null when logged out.
///
/// Re-fetches after every data-sync ping (fresh role/status without a
/// loading flicker, because the stream keeps its previous value).
final currentUserProvider = StreamProvider<Account?>((ref) {
  final api = ref.watch(apiClientProvider);
  if (ref.watch(sessionUserIdProvider) == null) {
    return Stream.value(null);
  }
  return watchFromApi(() async {
    final json = await api.get('/auth/me') as Map<String, dynamic>;
    return Account.fromJson(json);
  });
});

/// Marks the session as active and refreshes navigation.
Future<void> logIn(WidgetRef ref, Account account) async {
  ref.read(sessionUserIdProvider.notifier).set(account.id);
  ref.read(sessionRefreshProvider).ping();
}

/// Logs out, drops the session token, and refreshes navigation.
Future<void> logOut(WidgetRef ref) async {
  ref.read(apiClientProvider).clearToken();
  ref.read(sessionUserIdProvider.notifier).set(null);
  ref.read(sessionRefreshProvider).ping();
}
