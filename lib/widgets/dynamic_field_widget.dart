import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../services/image_utils.dart';
import '../theme/obsidian_ui_theme.dart';
import 'inline_camera_capture_dialog.dart';

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
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);

    // 1. SECTION HEADER / DIVIDER - Deprecated / No longer rendered
    if (type == 'section' || type == 'header' || type == 'divider') {
      return const SizedBox.shrink();
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
        int maxVal = (field.max != null && field.max! > minVal) ? field.max! : 999999;
        int stepVal = (field.step != null && field.step! > 0) ? field.step! : 1;
        int? doubleStep = (field.doubleStep != null && field.doubleStep! > 0) ? field.doubleStep : null;
        bool hasDoubleStep = doubleStep != null && doubleStep > 0;
        int val = (currentValue is num) ? (currentValue as num).toInt() : minVal;

        if (hasDoubleStep) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  context.tr(field.label),
                  style: TextStyle(fontSize: 14.5, color: primaryTextColor, fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(width: 8.0),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStepButton(
                    context: context,
                    label: '-$doubleStep',
                    onPressed: val > minVal ? () => onChanged((val - doubleStep).clamp(minVal, maxVal)) : null,
                    isAccent: false,
                  ),
                  const SizedBox(width: 4.0),
                  _buildStepButton(
                    context: context,
                    label: '-$stepVal',
                    onPressed: val > minVal ? () => onChanged((val - stepVal).clamp(minVal, maxVal)) : null,
                    isAccent: false,
                  ),
                  const SizedBox(width: 6.0),
                  Container(
                    constraints: const BoxConstraints(minWidth: 40.0),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 8.0),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10.0),
                      color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                      border: Border.all(color: ObsidianUITheme.getGlassBorderColor(context)),
                    ),
                    child: Text(
                      '$val',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0, color: primaryTextColor),
                    ),
                  ),
                  const SizedBox(width: 6.0),
                  _buildStepButton(
                    context: context,
                    label: '+$stepVal',
                    onPressed: val < maxVal ? () => onChanged((val + stepVal).clamp(minVal, maxVal)) : null,
                    isAccent: true,
                  ),
                  const SizedBox(width: 4.0),
                  _buildStepButton(
                    context: context,
                    label: '+$doubleStep',
                    onPressed: val < maxVal ? () => onChanged((val + doubleStep).clamp(minVal, maxVal)) : null,
                    isAccent: true,
                  ),
                ],
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                context.tr(field.label),
                style: TextStyle(fontSize: 14.5, color: primaryTextColor, fontWeight: FontWeight.w500),
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: val > minVal ? () => onChanged((val - stepVal).clamp(minVal, maxVal)) : null,
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
                  onPressed: val < maxVal ? () => onChanged((val + stepVal).clamp(minVal, maxVal)) : null,
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
          key: ValueKey('textarea_${field.id}'),
          initialValue: val,
          maxLines: 3,
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            labelText: context.tr(field.label),
            hintText: field.placeholder != null ? context.tr(field.placeholder!) : 'Enter comments...',
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

      // 10. TEXT (STATIC TEXT DISPLAY)
      case 'text':
      case 'static_text':
      case 'label':
      case 'info':
        final labelText = context.tr(field.label);
        final placeholderText = field.placeholder != null ? context.tr(field.placeholder!) : null;
        return Container(
          key: ValueKey('text_static_${field.id}'),
          width: double.infinity,
          margin: const EdgeInsets.symmetric(vertical: 2.0),
          padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
          decoration: BoxDecoration(
            color: surfaceColor.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(10.0),
            border: Border.all(color: borderColor.withValues(alpha: 0.6)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                labelText,
                style: TextStyle(
                  color: primaryTextColor,
                  fontSize: 14.0,
                  fontWeight: FontWeight.w500,
                  height: 1.3,
                ),
              ),
              if (placeholderText != null && placeholderText.isNotEmpty) ...[
                const SizedBox(height: 4.0),
                Text(
                  placeholderText,
                  style: TextStyle(
                    color: tertiaryTextColor,
                    fontSize: 12.0,
                    height: 1.2,
                  ),
                ),
              ],
            ],
          ),
        );

      // 11. IMAGE / PHOTO UPLOAD
      case 'image':
      case 'image_upload':
      case 'photo':
        return _buildImageUploadField(context);

      default:
        String val = currentValue?.toString() ?? '';
        return TextFormField(
          key: ValueKey('field_${field.id}'),
          initialValue: val,
          style: TextStyle(color: primaryTextColor),
          decoration: InputDecoration(
            labelText: context.tr(field.label),
            hintText: field.placeholder != null ? context.tr(field.placeholder!) : null,
            hintStyle: TextStyle(color: tertiaryTextColor, fontSize: 13.0),
            labelStyle: TextStyle(color: secondaryTextColor),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: borderColor)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ObsidianUITheme.primaryAccent)),
          ),
          onChanged: (text) => onChanged(text),
        );
    }
  }

  Widget _buildStepButton({
    required BuildContext context,
    required String label,
    required VoidCallback? onPressed,
    required bool isAccent,
  }) {
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final isEnabled = onPressed != null;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8.0),
        child: Container(
          constraints: const BoxConstraints(minWidth: 40.0, minHeight: 38.0),
          padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 6.0),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8.0),
            color: isEnabled
                ? (isAccent
                    ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.18)
                    : ObsidianUITheme.getGlassSurfaceColor(context))
                : ObsidianUITheme.getGlassSurfaceColor(context).withValues(alpha: 0.05),
            border: Border.all(
              color: isEnabled
                  ? (isAccent ? ObsidianUITheme.primaryAccent.withValues(alpha: 0.6) : borderColor)
                  : borderColor.withValues(alpha: 0.2),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.0,
              fontWeight: FontWeight.bold,
              color: isEnabled
                  ? (isAccent ? ObsidianUITheme.primaryAccent : primaryTextColor)
                  : faintTextColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImageUploadField(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final surfaceColor = ObsidianUITheme.getGlassSurfaceColor(context);
    final borderColor = ObsidianUITheme.getGlassBorderColor(context);

    final String? imgStr = currentValue is String && (currentValue as String).isNotEmpty ? currentValue as String : null;
    final Uint8List? imgBytes = ImageProcessingUtils.dataUrlToBytes(imgStr);

    Future<void> pickPhoto(ImageSource source) async {
      if (source == ImageSource.camera) {
        final result = await InlineCameraCaptureDialog.show(context);
        if (result != null) {
          onChanged(result.dataUrl);
        }
      } else {
        final result = await ImageProcessingUtils.pickAndProcessImage(source: source);
        if (result != null) {
          onChanged(result.dataUrl);
        }
      }
    }

    void showSourceSelector() {
      showModalBottomSheet(
        context: context,
        backgroundColor: surfaceColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 20.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Text(
                  context.tr(field.label),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: primaryTextColor,
                  ),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.camera_alt_outlined, color: ObsidianUITheme.primaryAccent),
                  title: Text('Take Photo with Camera', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                  subtitle: Text('Take a live mechanism snapshot', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.white.withValues(alpha: 0.05),
                  onTap: () {
                    Navigator.pop(ctx);
                    pickPhoto(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 10),
                ListTile(
                  leading: const Icon(Icons.photo_library_outlined, color: ObsidianUITheme.secondaryAccent),
                  title: Text('Choose from Gallery', style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.w600)),
                  subtitle: Text('Pick an existing photo from device', style: TextStyle(color: secondaryTextColor, fontSize: 12)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  tileColor: Colors.white.withValues(alpha: 0.05),
                  onTap: () {
                    Navigator.pop(ctx);
                    pickPhoto(ImageSource.gallery);
                  },
                ),
              ],
            ),
          ),
        ),
      );
    }

    void showImageZoomDialog() {
      if (imgBytes == null) return;
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: Colors.black.withValues(alpha: 0.92),
          insetPadding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(12.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        context.tr(field.label),
                        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.white70),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: InteractiveViewer(
                  panEnabled: true,
                  minScale: 0.5,
                  maxScale: 4.0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(imgBytes, fit: BoxFit.contain),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      );
    }

    return Container(
      key: ValueKey('image_field_${field.id}'),
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 4.0),
      padding: const EdgeInsets.all(12.0),
      decoration: BoxDecoration(
        color: surfaceColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12.0),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                context.tr(field.label),
                style: TextStyle(
                  fontSize: 14.5,
                  color: primaryTextColor,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (field.required && imgBytes == null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'Required',
                    style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8.0),
          if (imgBytes != null) ...[
            GestureDetector(
              onTap: showImageZoomDialog,
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  Container(
                    height: 180,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.black38,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        imgBytes,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.all(8),
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.zoom_in, size: 14, color: ObsidianUITheme.primaryAccent),
                        SizedBox(width: 4),
                        Text(
                          'Tap to Zoom',
                          style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w500),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8.0),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'Cleaned & Optimized',
                    style: TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 11, fontWeight: FontWeight.w600),
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: showSourceSelector,
                      icon: const Icon(Icons.refresh, size: 16, color: ObsidianUITheme.primaryAccent),
                      label: const Text('Retake', style: TextStyle(fontSize: 12, color: ObsidianUITheme.primaryAccent)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton.icon(
                      onPressed: () => onChanged(null),
                      icon: const Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
                      label: const Text('Remove', style: TextStyle(fontSize: 12, color: Colors.redAccent)),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 12.0),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: borderColor.withValues(alpha: 0.4)),
              ),
              child: Column(
                children: [
                  Icon(Icons.add_a_photo_outlined, size: 32, color: tertiaryTextColor),
                  const SizedBox(height: 6),
                  Text(
                    field.placeholder != null ? context.tr(field.placeholder!) : 'Attach robot photo (auto downscaled & cleaned)',
                    style: TextStyle(color: tertiaryTextColor, fontSize: 12.0),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: () => pickPhoto(ImageSource.camera),
                        icon: const Icon(Icons.camera_alt, size: 16),
                        label: const Text('Camera', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: ObsidianUITheme.primaryAccent,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          elevation: 0,
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton.icon(
                        onPressed: () => pickPhoto(ImageSource.gallery),
                        icon: const Icon(Icons.photo_library, size: 16),
                        label: const Text('Gallery', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: primaryTextColor,
                          side: BorderSide(color: borderColor),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
