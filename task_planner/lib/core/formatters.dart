// Small display helpers shared by screens and widgets.

/// First letter of [name] for avatar initials; falls back to '?'.
String initialsOf(String name) {
  final trimmed = name.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  return trimmed.substring(0, 1).toUpperCase();
}

/// Compact date label used in task rows, e.g. `2026-10-21`.
String formatDate(DateTime date) => '${date.year}-${date.month}-${date.day}';
