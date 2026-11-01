import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/theme.dart';
import '../models/models.dart';
import '../providers/api_providers.dart';
import '../providers/session_providers.dart';
import '../providers/theme_mode_provider.dart';
import '../services/api_client.dart';
import '../services/data_sync.dart';
import 'router.dart';

/// Root widget: theming plus the router, which owns the auth redirects.
///
/// Also owns the 401 hook: when an authenticated request is rejected, the
/// session is cleared so the router returns to the login screen.
class TaskPlannerApp extends ConsumerStatefulWidget {
  const TaskPlannerApp({super.key});

  @override
  ConsumerState<TaskPlannerApp> createState() => _TaskPlannerAppState();
}

class _TaskPlannerAppState extends ConsumerState<TaskPlannerApp>
    with WidgetsBindingObserver {
  late final ApiClient _api;

  /// Key used to persist the JWT token in shared preferences.
  static const _sessionTokenKey = 'session_token';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = ref.read(apiClientProvider);
    _api.setUnauthorizedHandler(_handleUnauthorized);
    _restoreSession();
  }

  /// Validates the persisted token once at startup, then hydrates the
  /// in-memory session so the router can go straight to the home screen.
  ///
  /// A missing or rejected token leaves the app logged out. The token is
  /// dropped on rejection so a stale session is never retried forever.
  Future<void> _restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_sessionTokenKey);
    if (token == null || token.isEmpty) {
      if (mounted) {
        ref.read(sessionReadyProvider.notifier).set(true);
      }
      return;
    }
    _api.setToken(token);
    try {
      final json = await _api.get('/auth/me') as Map<String, dynamic>;
      if (mounted) {
        ref.read(sessionUserIdProvider.notifier).set(
          Account.fromJson(json).id,
        );
      }
    } catch (_) {
      _api.clearToken();
      await prefs.remove(_sessionTokenKey);
    } finally {
      if (mounted) {
        ref.read(sessionReadyProvider.notifier).set(true);
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _api.setUnauthorizedHandler(null);
    super.dispose();
  }

  /// Returning to the app re-reads the account and visible lists, so a role
  /// or status change made by an admin elsewhere is applied without logout.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      DataSync.instance.ping();
    }
  }

  /// A 401 on an authenticated request means the token is no longer valid:
  /// end the session so the router returns to the login screen.
  ///
  /// State changes are deferred to a microtask because this callback runs
  /// while a provider is building, and Riverpod forbids modifying other
  /// providers during initialization.
  void _handleUnauthorized() {
    if (!mounted) {
      return;
    }
    _api.clearToken();
    SharedPreferences.getInstance().then((prefs) {
      prefs.remove(_sessionTokenKey);
    });
    Future<void>.microtask(() {
      if (!mounted) {
        return;
      }
      ref
          .read(sessionNoticeProvider.notifier)
          .set('Your session expired. Log in again.');
      ref.read(sessionUserIdProvider.notifier).set(null);
      ref.read(sessionRefreshProvider).ping();
    });
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final mode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Task Planner',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: mode,
      routerConfig: router,
    );
  }
}

