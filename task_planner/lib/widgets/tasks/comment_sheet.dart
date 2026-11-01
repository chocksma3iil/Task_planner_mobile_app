/// A read/write comment list for one task.
///
/// Shows existing comments (newest first) and a composer to add new ones.
/// Viewer accounts can read but not create/edit/delete comments.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/formatters.dart';
import '../../models/models.dart';
import '../../providers/data_providers.dart';
import '../../providers/session_providers.dart';
import '../shared/app_snackbar.dart';

/// Bottom sheet that lists comments for [taskId] and lets the user add new
/// ones. Use [showCommentSheet] to present it.
class CommentSheet extends ConsumerStatefulWidget {
  const CommentSheet({super.key, required this.taskId});

  final int taskId;

  @override
  ConsumerState<CommentSheet> createState() => _CommentSheetState();
}

class _CommentSheetState extends ConsumerState<CommentSheet> {
  final _bodyController = TextEditingController();
  bool _posting = false;

  @override
  void dispose() {
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _postComment() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) return;
    setState(() => _posting = true);
    try {
      final service = ref.read(commentServiceProvider);
      await service.create(taskId: widget.taskId, body: body);
      _bodyController.clear();
      if (mounted) {
        Navigator.of(context).pop(true); // signal the list to refresh
      }
    } catch (e) {
      if (mounted) {
        showAppSnackBar(context, userMessage(e));
      }
    } finally {
      if (mounted) setState(() => _posting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accountAsync = ref.watch(currentUserProvider);

    return accountAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Could not load account: $e')),
      data: (account) {
        final canMutate = account != null && account.role != 'viewer';
        return FutureBuilder<List<Comment>>(
          future: ref.read(commentServiceProvider).list(widget.taskId),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Error loading comments: ${snapshot.error}'),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () => setState(() {}),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }
            final comments = snapshot.data ?? const <Comment>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'Comments',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                if (comments.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No comments yet.'),
                  )
                else
                  ...comments.map((c) => _CommentRow(comment: c)).toList(),
                if (canMutate)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _bodyController,
                            decoration: const InputDecoration(
                              hintText: 'Write a comment…',
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                            ),
                            maxLines: null,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _postComment(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: _posting ? null : _postComment,
                          child: _posting
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Post'),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Shows the comment bottom sheet for [taskId]. Returns true if a comment was
/// added (caller should refresh its comment list).
Future<bool?> showCommentSheet(BuildContext context, int taskId) async {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    builder: (_) => CommentSheet(taskId: taskId),
  );
}

class _CommentRow extends ConsumerWidget {
  const _CommentRow({required this.comment});

  final Comment comment;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accountAsync = ref.watch(currentUserProvider);
    final isAuthor = accountAsync.maybeWhen(
      data: (a) => a != null && a.id == comment.authorId,
      orElse: () => false,
    );
    final canEdit = isAuthor && comment.deletedAt == null;
    final canDelete = isAuthor && comment.deletedAt == null;

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        child: Text(comment.authorId.toString().substring(0, 1)),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            comment.deletedAt != null
                ? '[message supprimé]'
                : comment.body,
            style: comment.deletedAt != null
                ? const TextStyle(
                    fontStyle: FontStyle.italic, color: Colors.grey)
                : null,
          ),
          const SizedBox(height: 2),
          Text(
            formatDate(comment.createdAt),
            style: const TextStyle(fontSize: 11, color: Colors.grey),
          ),
          if (comment.editedAt != null)
            const Text(
              'edited',
              style: TextStyle(fontSize: 10, color: Colors.grey),
            ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canEdit)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 20),
              onPressed: () async {
                final controller = TextEditingController(text: comment.body);
                final result = await showDialog<String>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Edit comment'),
                    content: TextField(
                      controller: controller,
                      maxLines: 3,
                      autofocus: true,
                    ),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel')),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('Save'),
                      ),
                    ],
                  ),
                );
                if (result != null && result.isNotEmpty && result != comment.body) {
                  try {
                    final service = ref.read(commentServiceProvider);
                    await service.update(commentId: comment.id, body: result);
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(userMessage(e))));
                  }
                }
              },
            ),
          if (canDelete)
            IconButton(
              icon: const Icon(Icons.delete_outline, size: 20),
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Delete comment?'),
                    content:
                        const Text('This will soft-delete the comment.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
                if (confirmed == true) {
                  try {
                    final service = ref.read(commentServiceProvider);
                    await service.delete(comment.id);
                  } catch (e) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text(userMessage(e))));
                  }
                }
              },
            ),
        ],
      ),
    );
  }
}
