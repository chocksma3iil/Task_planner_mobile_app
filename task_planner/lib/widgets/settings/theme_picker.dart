import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/theme_mode_provider.dart';

/// Lets the user pick System / Light / Dark and persists the choice.
Future<void> showThemePicker(BuildContext context, WidgetRef ref) async {
  final mode = ref.read(themeModeProvider);
  final selected = await showDialog<ThemeMode>(
    context: context,
    builder: (ctx) => RadioGroup<ThemeMode>(
      groupValue: mode,
      onChanged: (value) => Navigator.of(ctx).pop(value),
      child: SimpleDialog(
        title: const Text('Theme'),
        children: [
          for (final option in const [
            (ThemeMode.system, 'System'),
            (ThemeMode.light, 'Light'),
            (ThemeMode.dark, 'Dark'),
          ])
            RadioListTile<ThemeMode>(title: Text(option.$2), value: option.$1),
        ],
      ),
    ),
  );
  if (selected != null) {
    await ref.read(themeModeProvider.notifier).set(selected);
  }
}
