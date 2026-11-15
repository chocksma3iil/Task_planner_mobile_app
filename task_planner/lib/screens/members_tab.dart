import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/rules.dart';
import '../models/models.dart';
import '../providers/data_providers.dart';
import '../providers/session_providers.dart';
import '../widgets/members/add_member_dialog.dart';
import '../widgets/members/member_card.dart';
import '../widgets/shared/app_snackbar.dart';
import '../widgets/shared/empty_state.dart';
import '../widgets/shared/error_state.dart';
import '../widgets/shared/search_field.dart';
import '../widgets/shared/section_header.dart';

/// Scoped roster. Admins, project owners, and team leads see pending/active
/// statuses and the pending-requests section; plain users see names only.
///
/// Flat design: no elevation, no shadows, no gradients. Surface colors come
/// from the semantic theme tokens.
class MembersTab extends ConsumerStatefulWidget {
  const MembersTab({super.key});

  @override
  ConsumerState<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<MembersTab> {
  String _query = '';
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoadingMore) {
      _loadMore();
    }
  }

  bool get _isLoadingMore {
    final state = ref.read(visibleMembersProvider);
    return state.hasValue && state.value!.isLoadingMore;
  }

  Future<void> _loadMore() async {
    await ref.read(visibleMembersProvider.notifier).loadMore();
  }

  Future<void> _refresh() async {
    await ref.read(visibleMembersProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(currentUserProvider);
    return account.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorState(
        message: 'Could not load account: $e',
        onRetry: () => ref.invalidate(currentUserProvider),
      ),
      data: (user) {
        if (user == null) {
          return const Center(child: Text('Logged out.'));
        }
        final canManage =
            isOwnerOrAdmin(user.role) || isTeamLead(user.role);
        final membersState = ref.watch(visibleMembersProvider);
        return Scaffold(
          backgroundColor: Theme.of(context).colorScheme.surface,
          floatingActionButton: canManage
              ? FloatingActionButton(
                  tooltip: 'Add user',
                  onPressed: () => _addDialog(context, ref, user),
                  child: const Icon(Icons.person_add),
                )
              : null,
          body: membersState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(
              message: 'Could not load members: $e',
              onRetry: _refresh,
            ),
            data: (paginated) => _body(context, ref, user, paginated, canManage),
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    Account user,
    PaginatedList<Account> paginated,
    bool canManage,
  ) {
    final list = paginated.items;
    final searched = _query.isEmpty
        ? list
        : list
              .where(
                (m) =>
                    m.name.toLowerCase().contains(_query) ||
                    m.email.toLowerCase().contains(_query) ||
                    (m.position?.toLowerCase().contains(_query) ?? false),
              )
              .toList();
    final pending = searched
        .where((m) => m.status == MemberStatus.pending)
        .toList();
    final active = searched
        .where((m) => m.status != MemberStatus.pending)
        .toList();
    final isEmpty = list.isEmpty;
    final noMatches = !isEmpty && searched.isEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: DebouncedSearchField(
            hintText: 'Search members',
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              if (notification is ScrollEndNotification &&
                  notification.metrics.pixels >=
                      notification.metrics.maxScrollExtent - 200 &&
                  !paginated.isLoadingMore &&
                  paginated.hasMore) {
                _loadMore();
              }
              return false;
            },
            child: RefreshIndicator(
              onRefresh: _refresh,
              child: noMatches
                  ? const EmptyState(
                      scrollable: true,
                      icon: Icons.search_off,
                      title: 'No matches',
                      hint: 'Try a different search',
                    )
                  : isEmpty
                  ? EmptyState(
                      scrollable: true,
                      icon: Icons.people_outline,
                      title: 'No members yet',
                      hint: canManage ? 'Tap + to add one' : null,
                    )
                  : ListView(
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                      children: [
                        // Pending members are shown by name to everyone;
                        // only owners/admins get the confirmation section
                        // and status chips.
                        if (canManage && pending.isNotEmpty) ...[
                          const SectionHeader('Waiting for confirmation'),
                          for (final m in pending) ...[
                            _card(context, ref, user, m, pending: true),
                            const SizedBox(height: 12),
                          ],
                        ],
                        if (canManage) ...[
                          if (active.isNotEmpty) ...[
                            const SectionHeader('Members'),
                            for (final m in active) ...[
                              _card(context, ref, user, m, pending: false),
                              const SizedBox(height: 12),
                            ],
                          ],
                        ] else if (searched.isNotEmpty) ...[
                          const SectionHeader('Members'),
                          for (final m in searched) ...[
                            _card(context, ref, user, m, pending: false),
                            const SizedBox(height: 12),
                          ],
                        ],
                        if (paginated.hasMore)
                          const Padding(
                            padding: EdgeInsets.all(20),
                            child: Center(child: CircularProgressIndicator()),
                          ),
                      ],
                    ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(
    BuildContext context,
    WidgetRef ref,
    Account viewer,
    Account member, {
    required bool pending,
  }) {
    final canConfirm =
        pending &&
        (isAdmin(viewer.role) ||
            ((viewer.role == Roles.projectOwner ||
                    isTeamLead(viewer.role)) &&
                member.projectId == viewer.projectId));
    final canChangeRole =
        isAdmin(viewer.role) &&
        member.status == MemberStatus.active &&
        member.id != viewer.id &&
        member.role != Roles.projectOwner;
    final showStatus = isOwnerOrAdmin(viewer.role) || isTeamLead(viewer.role);
    final showRole = isAdmin(viewer.role);
    return MemberCard(
      member: member,
      showStatus: showStatus,
      showRole: showRole,
      canConfirm: canConfirm,
      onConfirm: canConfirm ? () => _confirm(context, ref, member) : null,
      canChangeRole: canChangeRole,
      onRoleChangePressed: canChangeRole
          ? () => _showRoleChangeDialog(context, ref, member)
          : null,
    );
  }

  /// Applies an admin-only role change; granting admin asks for confirmation.
  Future<void> _changeRole(
    BuildContext context,
    WidgetRef ref,
    Account member,
    String role,
  ) async {
    if (role == Roles.admin) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Give admin access?'),
          content: Text(
            '${member.name} will be able to manage every project, member '
            'and role.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Make admin'),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) {
        return;
      }
    }
    try {
      await ref
          .read(memberServiceProvider)
          .changeRole(userId: member.id, role: role);
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  /// Shows a role-selection dialog for [member], then applies the chosen role.
  Future<void> _showRoleChangeDialog(
    BuildContext context,
    WidgetRef ref,
    Account member,
  ) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Change role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Text('Admin'),
              onTap: () => Navigator.pop(context, Roles.admin),
            ),
            ListTile(
              title: const Text('Team lead'),
              onTap: () => Navigator.pop(context, Roles.teamLead),
            ),
            ListTile(
              title: const Text('User'),
              onTap: () => Navigator.pop(context, Roles.user),
            ),
            ListTile(
              title: const Text('Viewer'),
              onTap: () => Navigator.pop(context, Roles.viewer),
            ),
          ],
        ),
      ),
    );
    if (newRole != null && newRole != member.role) {
      await _changeRole(context, ref, member, newRole);
    }
  }

  Future<void> _confirm(
    BuildContext context,
    WidgetRef ref,
    Account member,
  ) async {
    try {
      await ref.read(memberServiceProvider).confirmUser(userId: member.id);
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }

  Future<void> _addDialog(
    BuildContext context,
    WidgetRef ref,
    Account viewer,
  ) async {
    final admin = isAdmin(viewer.role);
    List<Project> projects = const <Project>[];
    if (admin) {
      try {
        final projectState = ref.read(projectListProvider);
        if (projectState.hasValue) {
          projects = projectState.value!.items;
        }
      } catch (e) {
        if (context.mounted) {
          showAppSnackBar(context, userMessage(e));
        }
        return;
      }
      if (!context.mounted) {
        return;
      }
    }
    final draft = await showDialog<MemberDraft>(
      context: context,
      builder: (_) => AddMemberDialog(
        projects: projects,
        isAdmin: admin,
        ownerProjectId: viewer.projectId,
      ),
    );
    if (draft == null || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(memberServiceProvider)
          .createUser(
            name: draft.name,
            email: draft.email,
            password: draft.password,
            position: draft.position,
            projectId: draft.projectId,
          );
      if (context.mounted) {
        ref.invalidate(visibleMembersProvider);
      }
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}
