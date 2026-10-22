import 'package:flutter/material.dart';

import '../../models/models.dart';
import '../shared/position_field.dart';

/// Values collected by [AddMemberDialog].
class MemberDraft {
  const MemberDraft({
    required this.name,
    required this.email,
    required this.password,
    this.position,
    this.projectId,
  });

  final String name;
  final String email;
  final String password;
  final String? position;
  final int? projectId;
}

/// Adds an active member directly. Admins choose the project; owners add
/// plain users to their own project (the server enforces the scope).
class AddMemberDialog extends StatefulWidget {
  const AddMemberDialog({
    super.key,
    required this.projects,
    required this.isAdmin,
    this.ownerProjectId,
  });

  final List<Project> projects;
  final bool isAdmin;
  final int? ownerProjectId;

  @override
  State<AddMemberDialog> createState() => _AddMemberDialogState();
}

class _AddMemberDialogState extends State<AddMemberDialog> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _position;
  late int? _projectId = widget.isAdmin ? null : widget.ownerProjectId;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.of(context).pop(
      MemberDraft(
        name: _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        position: _position,
        projectId: _projectId,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add user'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Name',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.mail_outline),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Password',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            PositionField(onChanged: (v) => _position = v),
            if (widget.isAdmin) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                decoration: const InputDecoration(
                  labelText: 'Project',
                  prefixIcon: Icon(Icons.folder_outlined),
                ),
                initialValue: _projectId,
                items: [
                  for (final p in widget.projects)
                    DropdownMenuItem(value: p.id, child: Text(p.name)),
                ],
                onChanged: (v) => setState(() => _projectId = v),
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
        FilledButton(onPressed: _submit, child: const Text('Create')),
      ],
    );
  }
}
