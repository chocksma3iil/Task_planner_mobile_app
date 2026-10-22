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

/// Scoped roster. Owners and admins see pending/active statuses and the
/// pending-requests section; plain users see names only.
class MembersTab extends ConsumerStatefulWidget {
  const MembersTab({super.key});

  @override
  ConsumerState<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<MembersTab> {
  String _query = '';

  Future<void> _refresh() async {
    ref.invalidate(visibleMembersProvider);
    try {
      await ref
          .read(visibleMembersProvider.future)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // The stream keeps updating in the background.
    }
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
        final canManage = isOwnerOrAdmin(user.role);
        final members = ref.watch(visibleMembersProvider);
        return Scaffold(
          backgroundColor: Colors.transparent,
          floatingActionButton: canManage
              ? FloatingActionButton(
                  tooltip: 'Add user',
                  onPressed: () => _addDialog(context, ref, user),
                  child: const Icon(Icons.person_add),
                )
              : null,
          body: members.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorState(
              message: 'Could not load members: $e',
              onRetry: () => ref.invalidate(visibleMembersProvider),
            ),
            data: (list) => _body(context, ref, user, list, canManage),
          ),
        );
      },
    );
  }

  Widget _body(
    BuildContext context,
    WidgetRef ref,
    Account user,
    List<Account> list,
    bool canManage,
  ) {
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
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: DebouncedSearchField(
            hintText: 'Search members',
            onChanged: (query) => setState(() => _query = query),
          ),
        ),
        Expanded(
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
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                    children: [
                      // Pending members are shown by name to everyone;
                      // only owners/admins get the confirmation section
                      // and status chips.
                      if (canManage && pending.isNotEmpty) ...[
                        const SectionHeader('Waiting for confirmation'),
                        for (final m in pending) ...[
                          _card(context, ref, user, m, pending: true),
                          const SizedBox(height: 8),
                        ],
                      ],
                      if (canManage) ...[
                        if (active.isNotEmpty) ...[
                          const SectionHeader('Members'),
                          for (final m in active) ...[
                            _card(context, ref, user, m, pending: false),
                            const SizedBox(height: 8),
                          ],
                        ],
                      ] else if (searched.isNotEmpty) ...[
                        const SectionHeader('Members'),
                        for (final m in searched) ...[
                          _card(context, ref, user, m, pending: false),
                          const SizedBox(height: 8),
                        ],
                      ],
                    ],
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
    // Status is owner/admin information (access-control skill); plain users
    // see names only.
    final canConfirm =
        pending &&
        (isAdmin(viewer.role) ||
            (viewer.role == Roles.projectOwner &&
                member.projectId == viewer.projectId));
    return MemberCard(
      member: member,
      showStatus: isOwnerOrAdmin(viewer.role),
      showRole: isAdmin(viewer.role),
      canConfirm: canConfirm,
      onConfirm: () => _confirm(context, ref, member),
    );
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
    final List<Project> projects;
    try {
      projects = await ref.read(projectsProvider.future);
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
      return;
    }
    if (!context.mounted) {
      return;
    }
    final draft = await showDialog<MemberDraft>(
      context: context,
      builder: (_) => AddMemberDialog(
        projects: projects,
        isAdmin: isAdmin(viewer.role),
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
    } catch (e) {
      if (context.mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    }
  }
}
