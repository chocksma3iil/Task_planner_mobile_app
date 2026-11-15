import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rules.dart';
import '../providers/data_providers.dart';
import '../providers/session_providers.dart';
import '../providers/theme_mode_provider.dart';
import '../widgets/settings/theme_picker.dart';
import '../widgets/shared/error_state.dart';
import 'members_tab.dart';
import 'my_tasks_tab.dart';
import 'notifications_screen.dart';
import 'planner_tab.dart';
import 'projects_tab.dart';
import 'tasks_tab.dart';
import 'dashboard_screen.dart';

/// Post-login shell. Shows only the tabs allowed for the user's role and
/// keeps the selected tab while the session stays open.
///
/// Flat design: surface colors from the semantic theme, no shadows or
/// gradients on the NavigationBar.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final tabs = user.when(
      data: (account) => account != null ? visibleTabs(account.role) : <String>[],
      loading: () => <String>[],
      error: (_, __) => <String>[],
    );
    final selectedIndex = tabs.isEmpty
        ? 0
        : _selectedIndex.clamp(0, tabs.length - 1);

    return user.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
        body: ErrorState(
          message: 'Could not load account: $e',
          onRetry: () => ref.invalidate(currentUserProvider),
        ),
      ),
      data: (account) {
        if (account == null) {
          return const Scaffold(body: Center(child: Text('Logged out.')));
        }
        final tabName = tabs.isNotEmpty ? tabs[selectedIndex] : null;
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          backgroundColor: scheme.surface,
          appBar: AppBar(
            backgroundColor: scheme.surface,
            elevation: 0,
            title: Text(tabName != null ? _titleFor(tabName) : 'Task Planner'),
            actions: [
              Consumer(
                builder: (context, ref, _) {
                  final mode = ref.watch(themeModeProvider);
                  final icon = switch (mode) {
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.dark => Icons.dark_mode_outlined,
                    ThemeMode.system => Icons.brightness_auto_outlined,
                  };
                  return IconButton(
                    tooltip: 'Theme',
                    icon: Icon(icon),
                    onPressed: () => showThemePicker(context, ref),
                  );
                },
              ),
              Consumer(
                builder: (context, ref, _) {
                  final async = ref.watch(unreadNotificationListProvider);
                  final unread = async.value?.unread ?? 0;
                  return Stack(
                    children: [
                      IconButton(
                        tooltip: 'Notifications',
                        icon: const Icon(Icons.notifications_outlined),
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const NotificationsScreen(),
                            ),
                          );
                        },
                      ),
                      if (unread > 0)
                        Positioned(
                          right: 6,
                          top: 6,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              color: scheme.error,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
              PopupMenuButton<String>(
                tooltip: account.name,
                onSelected: (value) {
                  if (value == 'logout') {
                    logOut(ref);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'logout',
                    child: Text('Log out'),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Text(_initials(account.name)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: tabName != null ? _body(tabName) : const Center(child: Text('No view available')),
          bottomNavigationBar: tabName != null
              ? NavigationBar(
                  selectedIndex: selectedIndex,
                  onDestinationSelected: (i) {
                    setState(() => _selectedIndex = i);
                  },
                  labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
                  indicatorColor: scheme.primary.withValues(alpha: 0.14),
                  destinations: [
                    for (final tab in tabs)
                      NavigationDestination(
                        icon: Icon(_icons[tabs.indexOf(tab)]),
                        label: _navLabels[tab]!,
                      ),
                  ],
                )
              : null,
        );
      },
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  static const List<IconData> _icons = [
    Icons.home_outlined,
    Icons.folder_outlined,
    Icons.task_outlined,
    Icons.person_outlined,
    Icons.calendar_today_outlined,
    Icons.bar_chart_outlined,
  ];

  static const Map<String, String> _navLabels = {
    'projects': 'Projects',
    'members': 'Members',
    'tasks': 'Tasks',
    'mine': 'Mine',
    'planner': 'Planner',
    'dashboard': 'Dashboard',
  };

  static Widget _body(String tabName) {
    switch (tabName) {
      case 'projects':
        return const ProjectsTab();
      case 'tasks':
        return const TasksTab();
      case 'mine':
        return const MyTasksTab();
      case 'members':
        return const MembersTab();
      case 'planner':
        return const PlannerTab();
      case 'dashboard':
        return const DashboardScreen();
      default:
        return const Center(child: Text('No view available'));
    }
  }

  static String _titleFor(String tab) => switch (tab) {
        'projects' => 'Projects',
        'tasks' => 'Tasks',
        'mine' => 'Assigned to me',
        'members' => 'Members',
        'planner' => 'Planner',
        'dashboard' => 'Dashboard',
        _ => 'Task Planner',
      };
}
