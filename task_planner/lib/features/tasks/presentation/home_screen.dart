import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error_state.dart';
import '../../../core/rules.dart';
import '../../../core/theme.dart';
import '../../auth/presentation/session_providers.dart';
import '../../settings/application/theme_mode_provider.dart';
import 'members_tab.dart';
import 'my_tasks_tab.dart';
import 'projects_tab.dart';
import 'tasks_tab.dart';

/// Post-login shell. Shows only the tabs allowed for the user's role.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _index = 0;

  static const _titles = {
    'projects': 'Projects',
    'members': 'Members',
    'tasks': 'Tasks',
    'mine': 'Assigned to me',
  };

  // Short labels for the bottom navigation bar.
  static const _navLabels = {
    'projects': 'Projects',
    'members': 'Members',
    'tasks': 'Tasks',
    'mine': 'Mine',
  };

  static const _icons = {
    'projects': Icons.folder_outlined,
    'members': Icons.people_outline,
    'tasks': Icons.checklist_outlined,
    'mine': Icons.person_outline,
  };

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
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
        final tabs = visibleTabs(account.role);
        final safeIndex = _index.clamp(0, tabs.length - 1);
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          appBar: AppBar(
            title: Text(_titles[tabs[safeIndex]]!),
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
                    onPressed: () => _pickThemeMode(context, ref),
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
                  PopupMenuItem<String>(
                    enabled: false,
                    child: Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: scheme.primaryContainer,
                          foregroundColor: scheme.onPrimaryContainer,
                          child: Text(initialsOf(account.name)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                account.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              Text(
                                account.email,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem<String>(
                    value: 'logout',
                    child: Row(
                      children: [
                        Icon(Icons.logout),
                        SizedBox(width: 12),
                        Text('Log out'),
                      ],
                    ),
                  ),
                ],
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: CircleAvatar(
                    backgroundColor: scheme.primaryContainer,
                    foregroundColor: scheme.onPrimaryContainer,
                    child: Text(initialsOf(account.name)),
                  ),
                ),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: _body(tabs[safeIndex], account.id),
          bottomNavigationBar: NavigationBar(
            selectedIndex: safeIndex,
            onDestinationSelected: (i) => setState(() => _index = i),
            destinations: [
              for (final tab in tabs)
                NavigationDestination(
                  icon: Icon(_icons[tab]),
                  label: _navLabels[tab]!,
                ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _pickThemeMode(BuildContext context, WidgetRef ref) async {
    final mode = ref.read(themeModeProvider);
    final selected = await showDialog<ThemeMode>(
      context: context,
      builder: (ctx) => RadioGroup<ThemeMode>(
        groupValue: mode,
        onChanged: (v) => Navigator.of(ctx).pop(v),
        child: SimpleDialog(
          title: const Text('Theme'),
          children: [
            for (final option in const [
              (ThemeMode.system, 'System'),
              (ThemeMode.light, 'Light'),
              (ThemeMode.dark, 'Dark'),
            ])
              RadioListTile<ThemeMode>(
                title: Text(option.$2),
                value: option.$1,
              ),
          ],
        ),
      ),
    );
    if (selected != null) {
      await ref.read(themeModeProvider.notifier).set(selected);
    }
  }

  Widget _body(String tab, int accountId) {
    switch (tab) {
      case 'projects':
        return const ProjectsTab();
      case 'members':
        return const MembersTab();
      case 'mine':
        return const MyTasksTab();
      case 'tasks':
      default:
        return const TasksTab();
    }
  }
}
