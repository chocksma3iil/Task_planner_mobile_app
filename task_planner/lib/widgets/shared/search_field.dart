import 'dart:async';

import 'package:flutter/material.dart';

/// Search input with a clear button and a short debounce.
///
/// [onChanged] receives the trimmed, lower-cased query after the debounce.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.hintText,
    required this.onChanged,
    this.debounce = const Duration(milliseconds: 250),
  });

  final String hintText;
  final ValueChanged<String> onChanged;
  final Duration debounce;

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  final _controller = TextEditingController();
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    // Rebuild immediately so the clear button appears without waiting.
    setState(() {});
    _debounce?.cancel();
    _debounce = Timer(widget.debounce, () {
      if (mounted) {
        widget.onChanged(value.trim().toLowerCase());
      }
    });
  }

  void _clear() {
    _debounce?.cancel();
    _controller.clear();
    setState(() {});
    widget.onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      onChanged: _onChanged,
      decoration: InputDecoration(
        hintText: widget.hintText,
        isDense: true,
        prefixIcon: const Icon(Icons.search),
        suffixIcon: _controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: const Icon(Icons.clear),
                onPressed: _clear,
              ),
      ),
    );
  }
}
