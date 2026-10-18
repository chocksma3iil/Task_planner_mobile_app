import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/theme.dart';
import '../features/auth/presentation/login_screen.dart';
import '../features/auth/presentation/session_providers.dart';
import '../features/auth/presentation/signup_screen.dart';
import '../features/settings/application/theme_mode_provider.dart';
import '../features/tasks/presentation/home_screen.dart';

/// Screen order: login first, then sign-up (from login only), then the
/// role-filtered home tabs after a successful login.
final routerProvider = Provider<GoRouter>((ref) {
  final refresh = ref.watch(sessionRefreshProvider);
  return GoRouter(
    initialLocation: '/login',
    refreshListenable: refresh,
    redirect: (context, state) {
      final userId = ref.read(sessionUserIdProvider);
      final here = state.matchedLocation;
      if (userId == null) {
        return (here == '/login' || here == '/signup') ? null : '/login';
      }
      return (here == '/login' || here == '/signup' || here == '/')
          ? '/home'
          : null;
    },
    routes: [
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, _) => const SignUpScreen()),
      GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/', redirect: (_, _) => '/home'),
    ],
  );
});

class TaskPlannerApp extends ConsumerWidget {
  const TaskPlannerApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp.router(
      title: 'Task Planner',
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: themeMode,
      routerConfig: router,
    );
  }
}
