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
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

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
                style: TextStyle(fontSize: 12.0, color: secondaryTextColor),
              ),
            ],
            const SizedBox(height: 8.0),
            Divider(color: borderColor, height: 1.0),
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
                style: TextStyle(fontSize: 11.5, color: tertiaryTextColor),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFieldControl(BuildContext context, String type) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

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
                style: TextStyle(fontSize: 14.5, color: primaryTextColor, fontWeight: FontWeight.w500),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: val > minVal ? () => onChanged(val - stepVal) : null,
                  icon: Icon(Icons.remove_circle_outline, color: secondaryTextColor, size: 30.0),
                  iconSize: 30.0,
                  padding: const EdgeInsets.all(14.0),
                  constraints: const BoxConstraints(minWidth: 56.0, minHeight: 56.0),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 8.0),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12.0),
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                    border: Border.all(color: ObsidianUITheme.getGlassBorderColor(context)),
                  ),
                  child: Text(
                    '$val',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18.0, color: primaryTextColor),
                  ),
                ),
                IconButton(
                  onPressed: val < maxVal ? () => onChanged(val + stepVal) : null,
                  icon: const Icon(Icons.add_circle_outline, color: ObsidianUITheme.primaryAccent, size: 30.0),
                  iconSize: 30.0,
                  padding: const EdgeInsets.all(14.0),
                  constraints: const BoxConstraints(minWidth: 56.0, minHeight: 56.0),
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
                  style: TextStyle(fontSize: 14.5, color: primaryTextColor, fontWeight: FontWeight.w500),
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
                inactiveTrackColor: borderColor,
                thumbColor: ObsidianUITheme.primaryAccent,
                overlayColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                valueIndicatorColor: surfaceColor,
                valueIndicatorTextStyle: TextStyle(color: primaryTextColor),
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
              style: TextStyle(fontSize: 14.5, color: primaryTextColor, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6.0),
            Wrap(
              spacing: 2.0,
              children: List.generate(maxRating, (idx) {
                final starNum = idx + 1;
                final isSelected = starNum <= currentRating;
                return IconButton(
                  padding: const EdgeInsets.all(10.0),
                  constraints: const BoxConstraints(minWidth: 48.0, minHeight: 48.0),
                  icon: Icon(
                    isSelected ? Icons.star_rounded : Icons.star_border_rounded,
                    color: isSelected ? Colors.amber : faintTextColor,
                    size: 32.0,
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
          title: Text(field.label, style: TextStyle(color: primaryTextColor, fontSize: 14.5)),
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
              style: TextStyle(fontSize: 14.5, color: primaryTextColor, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: field.options.map((opt) {
                final isSelected = selectedVal == opt.value;
                return ChoiceChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                    child: Text(opt.label, style: const TextStyle(fontSize: 14.0)),
                  ),
                  selected: isSelected,
                  selectedColor: ObsidianUITheme.primaryAccent,
                  backgroundColor: ObsidianUITheme.isDark(context) ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  labelPadding: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : secondaryTextColor,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
              style: TextStyle(fontSize: 14.5, color: primaryTextColor, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 8.0),
            Wrap(
              spacing: 8.0,
              runSpacing: 8.0,
              children: field.options.map((opt) {
                final isSelected = selectedList.contains(opt.value);
                return FilterChip(
                  label: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6.0, vertical: 4.0),
                    child: Text(opt.label, style: const TextStyle(fontSize: 14.0)),
                  ),
                  selected: isSelected,
                  selectedColor: ObsidianUITheme.primaryAccent,
                  backgroundColor: ObsidianUITheme.isDark(context) ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  labelPadding: EdgeInsets.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                  labelStyle: TextStyle(
                    color: isSelected ? Colors.white : secondaryTextColor,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
          dropdownColor: surfaceColor,
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            labelStyle: TextStyle(color: secondaryTextColor),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
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
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder ?? 'Enter comments...',
            hintStyle: TextStyle(color: tertiaryTextColor, fontSize: 13.0),
            labelStyle: TextStyle(color: secondaryTextColor),
            enabledBorder: OutlineInputBorder(
              borderSide: BorderSide(color: borderColor),
              borderRadius: const BorderRadius.all(Radius.circular(12.0)),
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
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            labelText: field.label,
            hintText: field.placeholder,
            hintStyle: TextStyle(color: tertiaryTextColor, fontSize: 13.0),
            labelStyle: TextStyle(color: secondaryTextColor),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
          ),
          onChanged: (text) => onChanged(text),
        );
    }
  }
}
