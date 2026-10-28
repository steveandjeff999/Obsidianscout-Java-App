import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../theme/obsidian_ui_theme.dart';

/// One line in the review: a field label and its formatted value.
/// [isBlank] rows (zero, unset, empty) are dimmed so filled-in values stand out.
class SubmitReviewRow {
  final String label;
  final String value;
  final bool isBlank;

  const SubmitReviewRow(this.label, this.value, {this.isBlank = false});
}

class SubmitReviewSection {
  final String title;
  final List<SubmitReviewRow> rows;

  const SubmitReviewSection(this.title, this.rows);
}

/// Headline facts shown as chips at the top (team, match, point totals).
class SubmitReviewChip {
  final String label;
  final String value;

  const SubmitReviewChip(this.label, this.value);
}

const Set<String> _nonInputTypes = {
  'section', 'header', 'divider', 'static_text', 'label', 'info',
};

/// Formats a form value the way a scout would read it, e.g. option labels
/// instead of option values and Yes/No for toggles.
SubmitReviewRow reviewRowForField(ScoutingFieldModel field, dynamic value) {
  final t = field.type.toLowerCase();
  String optionLabel(dynamic v) {
    final s = v?.toString() ?? '';
    for (final opt in field.options) {
      if (opt.value == s) return opt.label;
    }
    return s;
  }

  switch (t) {
    case 'boolean':
    case 'toggle':
    case 'checkbox':
      final on = value == true || value == 'true';
      return SubmitReviewRow(field.label, on ? 'Yes' : 'No', isBlank: !on);
    case 'counter':
    case 'number':
    case 'stepper':
    case 'slider':
    case 'range':
      final n = value is num ? value : num.tryParse(value?.toString() ?? '');
      final text = n == null ? '-' : (n == n.roundToDouble() ? n.toInt().toString() : n.toString());
      return SubmitReviewRow(field.label, text, isBlank: n == null || n == 0);
    case 'rating':
    case 'stars':
      final n = value is num ? value : num.tryParse(value?.toString() ?? '');
      if (n == null) return SubmitReviewRow(field.label, '-', isBlank: true);
      final max = field.max ?? 5;
      return SubmitReviewRow(field.label, '${n.toInt()} / $max');
    case 'select':
    case 'dropdown':
    case 'radio':
    case 'choice':
      final label = optionLabel(value);
      return SubmitReviewRow(field.label, label.isEmpty ? '-' : label, isBlank: label.isEmpty);
    case 'multiselect':
    case 'multi-select':
      final list = value is List ? value : const [];
      return SubmitReviewRow(
        field.label,
        list.isEmpty ? 'None' : list.map(optionLabel).join(', '),
        isBlank: list.isEmpty,
      );
    case 'image':
    case 'image_upload':
    case 'photo':
      final count = value is List ? value.length : ((value?.toString() ?? '').isNotEmpty ? 1 : 0);
      return SubmitReviewRow(
        field.label,
        count == 0 ? 'No photo' : (count == 1 ? '1 photo' : '$count photos'),
        isBlank: count == 0,
      );
    default:
      final text = value?.toString().trim() ?? '';
      return SubmitReviewRow(field.label, text.isEmpty ? '-' : text, isBlank: text.isEmpty);
  }
}

/// Builds review sections from a scouting config. Fields are grouped by
/// [groupOf] (e.g. match phase) in first-seen order; [groupTitle] names each group.
/// Without [groupOf], the config's own section/header fields start each group.
List<SubmitReviewSection> buildReviewSections(
  ScoutingConfigModel? config,
  Map<String, dynamic> data, {
  String Function(ScoutingFieldModel field)? groupOf,
  String Function(String group)? groupTitle,
  String defaultTitle = 'Responses',
}) {
  if (config == null) return const [];
  final groups = <String, List<SubmitReviewRow>>{};
  var currentHeader = '';
  for (final field in config.fields) {
    final t = field.type.toLowerCase();
    if (t == 'section' || t == 'header') currentHeader = field.label;
    if (_nonInputTypes.contains(t)) continue;
    final group = groupOf?.call(field) ?? currentHeader;
    groups.putIfAbsent(group, () => []).add(reviewRowForField(field, data[field.id]));
  }
  return groups.entries
      .map((e) => SubmitReviewSection(
            e.key.isEmpty ? defaultTitle : (groupTitle?.call(e.key) ?? e.key),
            e.value,
          ))
      .toList();
}

/// Shows the pre-submit review. Resolves to true when the scout taps Submit,
/// false when they go back to edit (or dismiss the sheet).
Future<bool> showSubmitReview(
  BuildContext context, {
  required String title,
  List<SubmitReviewChip> chips = const [],
  required List<SubmitReviewSection> sections,
  String? submitLabel,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (ctx) => _SubmitReviewSheet(
      title: title,
      chips: chips,
      sections: sections,
      submitLabel: submitLabel,
    ),
  );
  return result == true;
}

class _SubmitReviewSheet extends StatelessWidget {
  final String title;
  final List<SubmitReviewChip> chips;
  final List<SubmitReviewSection> sections;
  final String? submitLabel;

  const _SubmitReviewSheet({
    required this.title,
    required this.chips,
    required this.sections,
    this.submitLabel,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final surface = ObsidianUITheme.getSurfaceColor(context);
    final border = ObsidianUITheme.getBorderColor(context);
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final accent = ObsidianUITheme.getPrimaryAccent(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.88;

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: Container(
        decoration: BoxDecoration(
          color: surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(22.0)),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10.0, bottom: 6.0),
                width: 40.0,
                height: 4.0,
                decoration: BoxDecoration(color: border, borderRadius: BorderRadius.circular(2.0)),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 6.0, 20.0, 4.0),
              child: Row(
                children: [
                  Icon(Icons.fact_check_rounded, color: accent, size: 24.0),
                  const SizedBox(width: 10.0),
                  Expanded(
                    child: Text(
                      title,
                      style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold, color: primaryText),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 10.0),
              child: Text(
                context.tr('review.subtitle', 'Check your entry before it is saved.'),
                style: TextStyle(fontSize: 12.5, color: secondaryText),
              ),
            ),
            if (chips.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(20.0, 0.0, 20.0, 10.0),
                child: Wrap(
                  spacing: 8.0,
                  runSpacing: 8.0,
                  children: chips
                      .map((c) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 6.0),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10.0),
                              border: Border.all(color: accent.withValues(alpha: 0.35)),
                            ),
                            child: RichText(
                              text: TextSpan(
                                style: TextStyle(fontSize: 12.5, color: primaryText),
                                children: [
                                  TextSpan(text: '${c.label}  ', style: TextStyle(color: secondaryText)),
                                  TextSpan(text: c.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            Divider(height: 1, color: border),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(20.0, 8.0, 20.0, 12.0),
                children: [
                  for (final section in sections) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12.0, bottom: 6.0),
                      child: Text(
                        section.title.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.1,
                          color: secondaryText,
                        ),
                      ),
                    ),
                    for (final row in section.rows)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5.0),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              flex: 5,
                              child: Text(
                                row.label,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  color: row.isBlank ? secondaryText : primaryText,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12.0),
                            Expanded(
                              flex: 4,
                              child: Text(
                                row.value,
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: row.isBlank ? FontWeight.w400 : FontWeight.w700,
                                  color: row.isBlank
                                      ? secondaryText.withValues(alpha: isDark ? 0.7 : 0.8)
                                      : primaryText,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
            Divider(height: 1, color: border),
            Padding(
              padding: const EdgeInsets.fromLTRB(16.0, 12.0, 16.0, 16.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        side: BorderSide(color: border),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: Icon(Icons.edit_rounded, color: primaryText, size: 18.0),
                      label: Text(
                        context.tr('review.edit', 'Edit'),
                        style: TextStyle(fontWeight: FontWeight.bold, color: primaryText),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12.0),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      autofocus: true,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: accent,
                        padding: const EdgeInsets.symmetric(vertical: 14.0),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14.0)),
                      ),
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.cloud_upload_rounded, color: Colors.white, size: 18.0),
                      label: Text(
                        submitLabel ?? context.tr('review.submit', 'Submit'),
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
