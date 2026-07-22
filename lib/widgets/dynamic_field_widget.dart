import 'package:flutter/material.dart';
import '../models/config_models.dart';
import '../theme/obsidian_ui_theme.dart';

class DynamicFieldWidget extends StatelessWidget {
  final ScoutingFieldModel field;
  final dynamic currentValue;
  final ValueChanged<dynamic> onChanged;

  const DynamicFieldWidget({
    super.key,
    required this.field,
    required this.currentValue,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    switch (field.type.toLowerCase()) {
      case 'counter':
      case 'number':
        int val = (currentValue is num) ? (currentValue as num).toInt() : 0;
        int min = field.min ?? 0;
        int max = field.max ?? 99;
        int step = field.step ?? 1;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                field.label,
                style: const TextStyle(fontSize: 15.0, color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: val > min ? () => onChanged(val - step) : null,
                  icon: const Icon(Icons.remove_circle_outline, color: Colors.white70),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 6.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                    border: Border.all(color: ObsidianUITheme.glassBorderLight),
                  ),
                  child: Text(
                    '$val',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: Colors.white),
                  ),
                ),
                IconButton(
                  onPressed: val < max ? () => onChanged(val + step) : null,
                  icon: const Icon(Icons.add_circle_outline, color: ObsidianUITheme.primaryAccent),
                ),
              ],
            ),
          ],
        );

      case 'toggle':
      case 'boolean':
        bool val = currentValue == true;
        return Material(
          color: Colors.transparent,
          child: SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(field.label, style: const TextStyle(color: Colors.white, fontSize: 15.0)),
            value: val,
            activeThumbColor: ObsidianUITheme.primaryAccent,
            onChanged: (bool newValue) => onChanged(newValue),
          ),
        );

      case 'select':
        String val = currentValue?.toString() ?? (field.options.isNotEmpty ? field.options.first.value : '');
        return DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: val.isNotEmpty ? val : null,
          dropdownColor: ObsidianUITheme.surface,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: field.label,
            labelStyle: const TextStyle(color: Colors.white60),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          items: field.options.map((opt) {
            return DropdownMenuItem<String>(
              value: opt.value,
              child: Text(opt.label, overflow: TextOverflow.ellipsis),
            );
          }).toList(),
          onChanged: (String? newSelection) {
            if (newSelection != null) {
              onChanged(newSelection);
            }
          },
        );

      case 'text':
      default:
        String val = currentValue?.toString() ?? '';
        return TextFormField(
          initialValue: val,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: field.label,
            labelStyle: const TextStyle(color: Colors.white60),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          onChanged: (text) => onChanged(text),
        );
    }
  }
}
