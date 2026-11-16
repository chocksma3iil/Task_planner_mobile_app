import 'package:flutter/material.dart';

import '../../models/ai_proposal.dart';

/// Dialogs that show an AI proposal and require explicit human approval.

/// Weekly-plan proposal: pick the tasks to create. Null means "cancelled".
Future<List<AiTaskProposal>?> showWeeklyPlanDialog(
  BuildContext context,
  AiWeeklyPlanProposal proposal,
) {
  return showDialog<List<AiTaskProposal>>(
    context: context,
    builder: (_) => _ChecklistDialog<AiTaskProposal>(
      title: proposal.title.isEmpty ? 'Weekly plan' : proposal.title,
      intro: proposal.tasks.isEmpty
          ? 'The AI did not propose any tasks for this project.'
          : 'Select the tasks you want to create.',
      items: proposal.tasks,
      labelOf: (task) => task.title,
      subtitleOf: (task) {
        final parts = <String>[
          'Priority: ${task.priority}',
          if (task.dueDate != null) 'Due: ${task.dueDate}',
          if (task.assignee != null) 'Assignee: ${task.assignee}',
        ];
        if (task.description != null && task.description!.isNotEmpty) {
          parts.add(task.description!);
        }
        return parts.join(' • ');
      },
      confirmLabel: 'Create',
    ),
  );
}

/// Decompose proposal: pick the subtasks to add. Null means "cancelled".
Future<List<AiSubtaskProposal>?> showDecomposeDialog(
  BuildContext context,
  AiDecomposeProposal proposal,
) {
  return showDialog<List<AiSubtaskProposal>>(
    context: context,
    builder: (_) => _ChecklistDialog<AiSubtaskProposal>(
      title: 'Suggested subtasks',
      intro: proposal.subtasks.isEmpty
          ? 'The AI did not propose any subtasks. Check that AI is enabled '
              'for this project.'
          : 'Select the subtasks you want to add.',
      items: proposal.subtasks,
      labelOf: (subtask) => subtask.title,
      subtitleOf: (subtask) {
        final parts = <String>['Priority: ${subtask.priority}'];
        if (subtask.description != null && subtask.description!.isNotEmpty) {
          parts.add(subtask.description!);
        }
        return parts.join(' • ');
      },
      confirmLabel: 'Add',
    ),
  );
}

/// Read-only briefing text.
Future<void> showBriefingDialog(
  BuildContext context,
  AiBriefingProposal proposal,
) {
  return showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Project briefing'),
      content: SingleChildScrollView(
        child: SelectableText(
          proposal.briefing.isEmpty
              ? 'The AI did not return a briefing.'
              : proposal.briefing,
        ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

/// Asks for the natural-language sentence used to capture a task.
Future<String?> showCaptureInputDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => const _CaptureInputDialog(),
  );
}

/// Shows the extracted task; returns true when the user approves creation.
Future<bool> showCaptureProposalDialog(
  BuildContext context,
  AiCaptureProposal proposal,
) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Task from text'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              proposal.title,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            if (proposal.description != null &&
                proposal.description!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(proposal.description!),
            ],
            const SizedBox(height: 10),
            Text(
              'Priority: ${proposal.priority}'
              '${proposal.dueDate == null ? '' : ' • Due: ${proposal.dueDate}'}'
              '${proposal.assignee == null ? '' : ' • Assignee: ${proposal.assignee}'}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Create task'),
        ),
      ],
    ),
  );
  return approved ?? false;
}

/// Confirms that AI should be enabled for the current project.
Future<bool> showEnableAiDialog(BuildContext context, String projectName) async {
  final approved = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('AI is disabled'),
      content: Text(
        'AI is disabled for "$projectName". Enable it to use planning, '
        'briefings, task capture and subtask suggestions.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Enable AI'),
        ),
      ],
    ),
  );
  return approved ?? false;
}

class _ChecklistDialog<T> extends StatefulWidget {
  const _ChecklistDialog({
    required this.title,
    required this.intro,
    required this.items,
    required this.labelOf,
    required this.subtitleOf,
    required this.confirmLabel,
  });

  final String title;
  final String intro;
  final List<T> items;
  final String Function(T) labelOf;
  final String Function(T) subtitleOf;
  final String confirmLabel;

  @override
  State<_ChecklistDialog<T>> createState() => _ChecklistDialogState<T>();
}

class _ChecklistDialogState<T> extends State<_ChecklistDialog<T>> {
  late final List<bool> _selected =
      List<bool>.filled(widget.items.length, true);

  int get _count => _selected.where((value) => value).length;

  @override
  Widget build(BuildContext context) {
    final hasItems = widget.items.isNotEmpty;
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.intro),
            if (hasItems) ...[
              const SizedBox(height: 8),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: widget.items.length,
                  itemBuilder: (context, index) {
                    final item = widget.items[index];
                    return CheckboxListTile(
                      value: _selected[index],
                      onChanged: (value) => setState(
                        () => _selected[index] = value ?? false,
                      ),
                      title: Text(widget.labelOf(item)),
                      subtitle: Text(widget.subtitleOf(item)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        if (hasItems)
          FilledButton(
            onPressed: _count == 0
                ? null
                : () => Navigator.of(context).pop([
                      for (var i = 0; i < widget.items.length; i++)
                        if (_selected[i]) widget.items[i],
                    ]),
            child: Text('${widget.confirmLabel} ($_count)'),
          ),
      ],
    );
  }
}

class _CaptureInputDialog extends StatefulWidget {
  const _CaptureInputDialog();

  @override
  State<_CaptureInputDialog> createState() => _CaptureInputDialogState();
}

class _CaptureInputDialogState extends State<_CaptureInputDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create a task from text'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        maxLines: 3,
        textInputAction: TextInputAction.done,
        onSubmitted: (_) => _submit(),
        decoration: const InputDecoration(
          labelText: 'Describe the task',
          hintText: 'e.g. Call the supplier tomorrow at 10',
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Suggest task'),
        ),
      ],
    );
  }
}
