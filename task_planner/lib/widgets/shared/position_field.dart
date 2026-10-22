import 'package:flutter/material.dart';

import '../../core/positions.dart';

/// Sentinel dropdown value meaning "type a custom position".
const _other = '\u0000other';

/// Position picker: a dropdown of [predefinedPositions] plus "No position"
/// and "Other". Choosing "Other" reveals a free-text field. Reports the
/// final value through [onChanged] — null when empty or not chosen.
class PositionField extends StatefulWidget {
  const PositionField({super.key, required this.onChanged});

  /// Reports the effective position: a predefined label, the custom text,
  /// or null when the user picked "No position" / left "Other" blank.
  final ValueChanged<String?> onChanged;

  @override
  State<PositionField> createState() => _PositionFieldState();
}

class _PositionFieldState extends State<PositionField> {
  String? _dropdownValue;
  final _custom = TextEditingController();

  @override
  void dispose() {
    _custom.dispose();
    super.dispose();
  }

  void _emit() {
    if (_dropdownValue == _other) {
      final text = _custom.text.trim();
      widget.onChanged(text.isEmpty ? null : text);
    } else {
      widget.onChanged(_dropdownValue);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String?>(
          decoration: const InputDecoration(labelText: 'Position (optional)'),
          initialValue: _dropdownValue,
          items: [
            const DropdownMenuItem<String?>(
              value: null,
              child: Text('No position'),
            ),
            for (final p in predefinedPositions)
              DropdownMenuItem<String?>(value: p, child: Text(p)),
            const DropdownMenuItem<String?>(
              value: _other,
              child: Text('Other…'),
            ),
          ],
          onChanged: (v) {
            setState(() => _dropdownValue = v);
            _emit();
          },
        ),
        if (_dropdownValue == _other) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _custom,
            decoration: const InputDecoration(labelText: 'Your position'),
            onChanged: (_) => _emit(),
          ),
        ],
      ],
    );
  }
}
