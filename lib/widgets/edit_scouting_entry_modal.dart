import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import 'dynamic_field_widget.dart';
import 'obsidian_feedback.dart';

class EditScoutingEntryModal extends StatefulWidget {
  final ApiService apiService;
  final String id;
  final String type; // 'match', 'pit', 'qual'
  final String title;
  final String? subtitle;
  final int? targetTeamNumber;
  final int? matchNumber;
  final String? matchKey;
  final String? eventKey;
  final bool isPrescout;
  final Map<String, dynamic> initialData;
  final List<ScoutingFieldModel> fields;
  final VoidCallback onSaved;

  const EditScoutingEntryModal({
    super.key,
    required this.apiService,
    required this.id,
    required this.type,
    required this.title,
    this.subtitle,
    this.targetTeamNumber,
    this.matchNumber,
    this.matchKey,
    this.eventKey,
    this.isPrescout = false,
    required this.initialData,
    required this.fields,
    required this.onSaved,
  });

  static Future<bool?> show({
    required BuildContext context,
    required ApiService apiService,
    required String id,
    required String type,
    required String title,
    String? subtitle,
    int? targetTeamNumber,
    int? matchNumber,
    String? matchKey,
    String? eventKey,
    bool isPrescout = false,
    required Map<String, dynamic> initialData,
    required List<ScoutingFieldModel> fields,
    required VoidCallback onSaved,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => EditScoutingEntryModal(
        apiService: apiService,
        id: id,
        type: type,
        title: title,
        subtitle: subtitle,
        targetTeamNumber: targetTeamNumber,
        matchNumber: matchNumber,
        matchKey: matchKey,
        eventKey: eventKey,
        isPrescout: isPrescout,
        initialData: initialData,
        fields: fields,
        onSaved: onSaved,
      ),
    );
  }

  /// Stored values the form doesn't define, as fields that keep each value's type. Lists, maps and embedded images
  /// aren't offered for editing: they stay in the entry exactly as they are.
  static List<ScoutingFieldModel> extraFields(Map<String, dynamic> data, Set<String> knownFieldIds) {
    const reservedKeys = {'eventKey', 'matchKey', 'matchNumber', 'compLevel', 'targetTeamNumber', 'id', 'clientId', 'isPrescout', 'timestamp'};
    final extras = <ScoutingFieldModel>[];
    data.forEach((key, value) {
      if (knownFieldIds.contains(key) || reservedKeys.contains(key)) return;
      final type = switch (value) {
        bool() => 'boolean',
        num() => 'number',
        String() when !value.startsWith('data:') => 'notes',
        _ => null,
      };
      if (type != null) extras.add(ScoutingFieldModel(id: key, label: key, type: type));
    });
    return extras;
  }

  @override
  State<EditScoutingEntryModal> createState() => _EditScoutingEntryModalState();
}

class _EditScoutingEntryModalState extends State<EditScoutingEntryModal> {
  late Map<String, dynamic> _formData;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _formData = Map<String, dynamic>.from(widget.initialData);
  }

  Future<void> _saveEntry() async {
    setState(() => _isSaving = true);
    try {
      final payload = Map<String, dynamic>.from(_formData);
      if (widget.targetTeamNumber != null) {
        payload['targetTeamNumber'] = widget.targetTeamNumber;
      }
      if (widget.eventKey != null && widget.eventKey!.isNotEmpty) {
        payload['eventKey'] = widget.eventKey;
      }
      if (widget.isPrescout) {
        payload['isPrescout'] = true;
      }
      if (widget.type != 'pit') {
        if (widget.matchKey != null && widget.matchKey!.isNotEmpty) {
          payload['matchKey'] = widget.matchKey;
        }
        if (widget.matchNumber != null) {
          payload['matchNumber'] = widget.matchNumber;
        }
      }

      final res = await widget.apiService.updateScoutingEntry(widget.id, payload, type: widget.type);
      if (!mounted) return;
      if (res.success) {
        Navigator.of(context).pop(true);
        ObsidianFeedback.showSuccess(context, message: 'Scouting entry updated successfully');
        widget.onSaved();
      } else {
        setState(() => _isSaving = false);
        ObsidianFeedback.showError(context, message: res.message ?? 'Failed to update entry');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ObsidianFeedback.showError(context, message: 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

    // Build the list of fields to display
    final displayedFields = <ScoutingFieldModel>[];
    final knownFieldIds = <String>{};

    for (final f in widget.fields) {
      displayedFields.add(f);
      knownFieldIds.add(f.id);
    }

    // Include any custom fields not present in schema
    displayedFields.addAll(EditScoutingEntryModal.extraFields(widget.initialData, knownFieldIds));

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        // A Material, not a coloured Container: toggle fields paint their ink on the nearest Material.
        return Material(
          color: isDark ? const Color(0xF80F172A) : const Color(0xF8F8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            side: BorderSide(color: isDark ? Colors.white12 : Colors.black12),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 12),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(Icons.edit_note_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          if (widget.subtitle != null && widget.subtitle!.isNotEmpty)
                            Text(
                              widget.subtitle!,
                              style: TextStyle(fontSize: 12, color: secondaryTextColor),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Divider(height: 20),

              // Scrollable Form Fields
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                  children: [
                    if (displayedFields.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No editable fields found for this entry.',
                            style: TextStyle(color: secondaryTextColor),
                          ),
                        ),
                      )
                    else
                      ...displayedFields.map((field) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: DynamicFieldWidget(
                            field: field,
                            currentValue: _formData[field.id],
                            onChanged: (val) {
                              setState(() {
                                _formData[field.id] = val;
                              });
                            },
                          ),
                        );
                      }),
                  ],
                ),
              ),

              // Bottom Action Bar
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: surfaceColor.withValues(alpha: 0.8),
                  border: Border(top: BorderSide(color: isDark ? Colors.white10 : Colors.black12)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                      child: Text(context.tr('common.cancel', 'Cancel')),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: ObsidianUITheme.primaryAccent,
                        foregroundColor: Colors.black,
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      onPressed: _isSaving ? null : _saveEntry,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.save_rounded, size: 18),
                      label: Text(
                        _isSaving ? 'Saving...' : context.tr('common.save', 'Save Changes'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
