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
    final type = field.type.toLowerCase();

    // 1. SECTION HEADER / DIVIDER
    if (type == 'section' || type == 'header' || type == 'divider') {
      return Container(
        margin: const EdgeInsets.only(top: 16.0, bottom: 8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 4.0,
                  height: 18.0,
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.primaryAccent,
                    borderRadius: BorderRadius.circular(2.0),
                  ),
                ),
                const SizedBox(width: 8.0),
                Expanded(
                  child: Text(
                    field.label.toUpperCase(),
                    style: const TextStyle(
                      fontSize: 13.0,
                      fontWeight: FontWeight.bold,
                      color: ObsidianUITheme.primaryAccent,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
              ],
            ),
            if (field.description != null && field.description!.isNotEmpty) ...[
              const SizedBox(height: 4.0),
              Text(
                field.description!,
                style: const TextStyle(fontSize: 12.0, color: Colors.white60),
              ),
            ],
            const SizedBox(height: 8.0),
            const Divider(color: Colors.white12, height: 1.0),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFieldControl(context, type),
          if (field.description != null && field.description!.isNotEmpty && type != 'section')
            Padding(
              padding: const EdgeInsets.only(top: 4.0, left: 2.0),
              child: Text(
                field.description!,
                style: const TextStyle(fontSize: 11.5, color: Colors.white54),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldControl(BuildContext context, String type) {
    switch (type) {
      // 2. COUNTER / NUMBER
      case 'counter':
      case 'number':
      case 'stepper':
        int minVal = field.min ?? 0;
        int maxVal = field.max ?? 99;
        int stepVal = field.step ?? 1;
        int val = (currentValue is num) ? (currentValue as num).toInt() : minVal;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                field.label,
                style: const TextStyle(fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.w500),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: val > minVal ? () => onChanged(val - stepVal) : null,
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
                  onPressed: val < maxVal ? () => onChanged(val + stepVal) : null,
                  icon: const Icon(Icons.add_circle_outline, color: ObsidianUITheme.primaryAccent),
                ),
              ],
            ),
          ],
        );

      // 3. SLIDER / RANGE
      case 'slider':
      case 'range':
        double minVal = (field.min ?? 0).toDouble();
        double maxVal = (field.max ?? 10).toDouble();
        int stepVal = field.step ?? 1;
        double current = (currentValue is num) ? (currentValue as num).toDouble() : minVal;
        if (current < minVal) current = minVal;
        if (current > maxVal) current = maxVal;

        final divisions = ((maxVal - minVal) / stepVal).round();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  field.label,
                  style: const TextStyle(fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.w500),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 2.0),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8.0),
                    border: Border.all(color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    stepVal < 1 ? current.toStringAsFixed(1) : current.toInt().toString(),
                    style: const TextStyle(fontSize: 13.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                  ),
                ),
              ],
            ),
            SliderTheme(
              data: SliderThemeData(
                activeTrackColor: ObsidianUITheme.primaryAccent,
                inactiveTrackColor: Colors.white12,
                thumbColor: ObsidianUITheme.primaryAccent,
                overlayColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                valueIndicatorColor: ObsidianUITheme.surface,
                valueIndicatorTextStyle: const TextStyle(color: Colors.white),
              ),
              child: Slider(
                value: current,
                min: minVal,
                max: maxVal,
                divisions: divisions > 0 ? divisions : null,
                label: stepVal < 1 ? current.toStringAsFixed(1) : current.toInt().toString(),
                onChanged: (val) => onChanged(stepVal < 1 ? val : val.round()),
              ),
            ),
          ],
        );

      // 4. RATING / STARS
      case 'rating':
      case 'stars':
        int maxRating = field.max ?? 5;
        int currentRating = (currentValue is num) ? (currentValue as num).toInt() : (field.min ?? 1);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              field.label,
              style: const TextStyle(fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6.0),
            Row(
              children: List.generate(maxRating, (idx) {
                final starNum = idx + 1;
                final isSelected = starNum <= currentRating;
                return IconButton(
                  padding: const EdgeInsets.symmetric(horizontal: 4.0),
                  constraints: const BoxConstraints(),
                  icon: Icon(
                    isSelected ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isSelected ? Colors.amber : Colors.white30,
                    size: 28.0,
                  ),
                  onPressed: () => onChanged(starNum),
                );
              }),
            ),
          ],
        );

      // 5. TOGGLE / BOOLEAN / CHECKBOX
      case 'toggle':
      case 'boolean':
      case 'checkbox':
        bool val = currentValue == true || currentValue == 1 || currentValue == 'true';
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(field.label, style: const TextStyle(color: Colors.white, fontSize: 14.5)),
          value: val,
          activeThumbColor: ObsidianUITheme.primaryAccent,
          activeTrackColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
          onChanged: (bool newValue) => onChanged(newValue),
        );

      // 6. RADIO / SEGMENTED
      case 'radio':
      case 'choice':
        String selectedVal = currentValue?.toString() ?? (field.options.isNotEmpty ? field.options.first.value : '');
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              field.label,
              style: const TextStyle(fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: field.options.map((opt) {
                final isSelected = selectedVal == opt.value;
                return ChoiceChip(
                  label: Text(opt.label),
                  selected: isSelected,
                  selectedColor: ObsidianUITheme.primaryAccent,
                  backgroundColor: Colors.white10,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13.0,
                  ),
                  onSelected: (selected) {
                    if (selected) onChanged(opt.value);
                  },
                );
              }).toList(),
            ),
          ],
        );

      // 7. MULTISELECT / CHECKBOX-GROUP
      case 'multiselect':
      case 'multi-select':
        List<String> selectedList = [];
        if (currentValue is List) {
          selectedList = (currentValue as List).map((e) => e.toString()).toList();
        } else if (currentValue is String && (currentValue as String).isNotEmpty) {
          selectedList = (currentValue as String).split(',');
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              field.label,
              style: const TextStyle(fontSize: 14.5, color: Colors.white, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: field.options.map((opt) {
                final isSelected = selectedList.contains(opt.value);
                return FilterChip(
                  label: Text(opt.label),
                  selected: isSelected,
                  selectedColor: ObsidianUITheme.primaryAccent,
                  backgroundColor: Colors.white10,
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : Colors.white70,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    fontSize: 13.0,
                  ),
                  onSelected: (selected) {
                    final newList = List<String>.from(selectedList);
                    if (selected) {
                      newList.add(opt.value);
                    } else {
                      newList.remove(opt.value);
                    }
                    onChanged(newList);
                  },
                );
              }).toList(),
            ),
          ],
        );

      // 8. SELECT / DROPDOWN
      case 'select':
      case 'dropdown':
        String val = currentValue?.toString() ?? (field.options.isNotEmpty ? field.options.first.value : '');
        return DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: field.options.any((o) => o.value == val) ? val : (field.options.isNotEmpty ? field.options.first.value : null),
          dropdownColor: ObsidianUITheme.surface,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            labelStyle: const TextStyle(color: Colors.white60),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
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

      // 9. TEXTAREA
      case 'textarea':
      case 'notes':
        String val = currentValue?.toString() ?? '';
        return TextFormField(
          initialValue: val,
          maxLines: 3,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder ?? 'Enter comments...',
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 13.0),
            labelStyle: const TextStyle(color: Colors.white60),
            enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24),
              borderRadius: BorderRadius.all(Radius.circular(12.0)),
            ),
            focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: ObsidianUITheme.primaryAccent),
              borderRadius: BorderRadius.all(Radius.circular(12.0)),
            ),
          ),
          onChanged: (text) => onChanged(text),
        );

      // 10. TEXT / DEFAULT STRING
      case 'text':
      case 'string':
      default:
        String val = currentValue?.toString() ?? '';
        return TextFormField(
          initialValue: val,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            hintStyle: const TextStyle(color: Colors.white30, fontSize: 13.0),
            labelStyle: const TextStyle(color: Colors.white60),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
          ),
          onChanged: (text) => onChanged(text),
        );
    }
  }
}
