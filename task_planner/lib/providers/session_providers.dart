import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../services/data_sync.dart';
import 'api_providers.dart';

/// Key used to persist the JWT token in shared preferences.
const _sessionTokenKey = 'session_token';

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

/// One-shot message shown on the login screen after a forced logout (401).
class SessionNotice extends Notifier<String?> {
  @override
  String? build() => null;

  void set(String? message) => state = message;
}

final sessionNoticeProvider = NotifierProvider<SessionNotice, String?>(
  SessionNotice.new,
);

/// True once the saved token has been checked at startup. The router shows
/// the splash screen until then, so a cold start never flashes the login page
/// before restoring an existing session.
class SessionReady extends Notifier<bool> {
  @override
  bool build() => false;

  void set(bool value) => state = value;
}

final sessionReadyProvider = NotifierProvider<SessionReady, bool>(
  SessionReady.new,
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
  ref.read(sessionNoticeProvider.notifier).set(null);
  ref.read(sessionUserIdProvider.notifier).set(account.id);
  ref.read(sessionRefreshProvider).ping();
}

/// Logs out, drops the session token, and refreshes navigation.
Future<void> logOut(WidgetRef ref) async {
  ref.read(apiClientProvider).clearToken();
  SharedPreferences.getInstance().then((prefs) {
    prefs.remove(_sessionTokenKey);
  });
  ref.read(sessionNoticeProvider.notifier).set(null);
  ref.read(sessionUserIdProvider.notifier).set(null);
  ref.read(sessionRefreshProvider).ping();
}
