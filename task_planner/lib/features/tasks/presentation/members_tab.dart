import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database.dart';
import '../../../core/error_state.dart';
import '../../../core/position_field.dart';
import '../../../core/rules.dart';
import '../../../core/theme.dart';
import '../../auth/presentation/session_providers.dart';
import 'providers.dart';

/// Scoped roster. Owners and admins see pending/active statuses and the
/// pending-requests section; plain users see names only.
class MembersTab extends ConsumerStatefulWidget {
  const MembersTab({super.key});

  @override
  ConsumerState<MembersTab> createState() => _MembersTabState();
}

class _MembersTabState extends ConsumerState<MembersTab> {
  final _search = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) {
        setState(() => _query = value.trim().toLowerCase());
      }
    });
    // Rebuild immediately so the clear button appears without waiting.
    setState(() {});
  }

  Future<void> _refresh() async {
    ref.invalidate(visibleMembersProvider);
    try {
      await ref
          .read(visibleMembersProvider.future)
          .timeout(const Duration(seconds: 3));
    } on TimeoutException {
      // Stream keeps updating in the background.
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
    Assignee user,
    List<Assignee> list,
    bool canManage,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final searched = _query.isEmpty
        ? list
        : list
            .where((m) =>
                m.name.toLowerCase().contains(_query) ||
                m.email.toLowerCase().contains(_query) ||
                (m.position?.toLowerCase().contains(_query) ?? false))
            .toList();
    final pending =
        searched.where((m) => m.status == MemberStatus.pending).toList();
    final active =
        searched.where((m) => m.status != MemberStatus.pending).toList();
    final isEmpty = list.isEmpty;
    final noMatches = !isEmpty && searched.isEmpty;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child: TextField(
            controller: _search,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: 'Search members',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _search.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _search.clear();
                        setState(() => _query = '');
                      },
                    ),
            ),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: noMatches
                ? _scrollableEmpty(
                    context,
                    scheme,
                    icon: Icons.search_off,
                    title: 'No matches',
                    hint: 'Try a different search',
                  )
                : isEmpty
                    ? _scrollableEmpty(
                        context,
                        scheme,
                        icon: Icons.people_outline,
                        title: 'No members yet',
                        hint: canManage ? 'Tap + to add one' : '',
                      )
                    : ListView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                        children: [
                          // Pending members are shown by name to everyone;
                          // only owners/admins get the confirmation section
                          // and status chips.
                          if (canManage && pending.isNotEmpty) ...[
                            sectionHeader(
                                context, 'Waiting for confirmation'),
                            for (final m in pending) ...[
                              _card(context, ref, user, m, true),
                              const SizedBox(height: 8),
                            ],
                          ],
                          if (canManage) ...[
                            if (active.isNotEmpty) ...[
                              sectionHeader(context, 'Members'),
                              for (final m in active) ...[
                                _card(context, ref, user, m, false),
                                const SizedBox(height: 8),
                              ],
                            ],
                          ] else if (searched.isNotEmpty) ...[
                            sectionHeader(context, 'Members'),
                            for (final m in searched) ...[
                              _card(context, ref, user, m, false),
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

  Widget _scrollableEmpty(
    BuildContext context,
    ColorScheme scheme, {
    required IconData icon,
    required String title,
    required String hint,
  }) {
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 48, color: scheme.outline),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (hint.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    hint,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _card(BuildContext context, WidgetRef ref, Assignee viewer,
      Assignee member, bool isPending) {
    final scheme = Theme.of(context).colorScheme;
    // Status is owner/admin information (access-control skill); plain users
    // see names only.
    final showStatus = isOwnerOrAdmin(viewer.role);
    final canConfirm = isPending &&
        (isAdmin(viewer.role) ||
            (viewer.role == Roles.projectOwner &&
                member.projectId == viewer.projectId));
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: isPending
                  ? scheme.tertiaryContainer
                  : scheme.primaryContainer,
              foregroundColor: isPending
                  ? scheme.onTertiaryContainer
                  : scheme.onPrimaryContainer,
              child: Text(initialsOf(member.name)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          member.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showStatus) ...[
                        const SizedBox(width: 8),
                        _statusChip(context, member, isPending),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      if (member.position != null) member.position!,
                      member.email,
                    ].join(' · '),
                    style: TextStyle(
                      fontSize: 12.5,
                      color: scheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isAdmin(viewer.role))
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          member.role,
                          style: TextStyle(
                            fontSize: 11,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (canConfirm)
              FilledButton.tonal(
                onPressed: () async {
                  try {
                    await ref.read(memberServiceProvider).confirmUser(
                          actor: viewer,
                          userId: member.id,
                        );
                  } on StateError catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                },
                child: const Text('Confirm'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(BuildContext context, Assignee member, bool isPending) {
    final scheme = Theme.of(context).colorScheme;
    final color = isPending ? scheme.tertiary : scheme.primary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        member.status,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Future<void> _addDialog(
      BuildContext context, WidgetRef ref, Assignee viewer) async {
    final name = TextEditingController();
    final email = TextEditingController();
    final password = TextEditingController();
    String? position;
    int? projectId = viewer.projectId;
    final projects = await ref.read(projectsProvider.future);
    if (!context.mounted) {
      return;
    }
    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add user'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                ),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 12),
                PositionField(onChanged: (v) => position = v),
                if (isAdmin(viewer.role)) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    decoration: const InputDecoration(
                      labelText: 'Project',
                      prefixIcon: Icon(Icons.folder_outlined),
                    ),
                    initialValue: projectId,
                    items: [
                      for (final p in projects)
                        DropdownMenuItem(value: p.id, child: Text(p.name)),
                    ],
                    onChanged: (v) => setDialogState(() => projectId = v),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Create'),
            ),
          ],
        ),
      ),
    );
    if (created == true && context.mounted) {
      try {
        await ref.read(memberServiceProvider).createUser(
              actor: viewer,
              name: name.text.trim(),
              email: email.text.trim(),
              password: password.text,
              position: position,
              projectId: projectId,
            );
      } on StateError catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(e.message)));
        }
      }
    }
    name.dispose();
    email.dispose();
    password.dispose();
  }
}
