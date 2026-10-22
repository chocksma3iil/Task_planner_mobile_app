import 'package:flutter/material.dart';

/// Shows a floating snackbar with an optional action (e.g. Undo).
void showAppSnackBar(
  BuildContext context,
  String message, {
  String? actionLabel,
  Future<void> Function()? onAction,
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      action: actionLabel == null
          ? null
          : SnackBarAction(
              label: actionLabel,
              onPressed: () {
                onAction?.call();
              },
            ),
    ),
  );
}

/// Extracts a user-facing message from the app's normalized error types.
String userMessage(Object error) => switch (error) {
  StateError(:final message) => message,
  ArgumentError(:final message) => message?.toString() ?? 'Request failed.',
  _ => error.toString(),
};
