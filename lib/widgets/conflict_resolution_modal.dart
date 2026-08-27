import 'package:flutter/material.dart';
import '../models/config_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

class ConflictResolutionModal extends StatefulWidget {
  final ApiService apiService;
  final String title;
  final String subtitle;
  final String type; // 'match', 'pit', 'qual'
  final List<ScoutingFieldModel> fields;
  final List<Map<String, dynamic>> conflictingEntries;
  final VoidCallback onResolved;

  const ConflictResolutionModal({
    super.key,
    required this.apiService,
    required this.title,
    required this.subtitle,
    required this.type,
    required this.fields,
    required this.conflictingEntries,
    required this.onResolved,
  });

  static Future<void> show({
    required BuildContext context,
    required ApiService apiService,
    required String title,
    required String subtitle,
    required String type,
    required List<ScoutingFieldModel> fields,
    required List<Map<String, dynamic>> conflictingEntries,
    required VoidCallback onResolved,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ConflictResolutionModal(
        apiService: apiService,
        title: title,
        subtitle: subtitle,
        type: type,
        fields: fields,
        conflictingEntries: conflictingEntries,
        onResolved: onResolved,
      ),
    );
  }

  @override
  State<ConflictResolutionModal> createState() => _ConflictResolutionModalState();
}

class _ConflictResolutionModalState extends State<ConflictResolutionModal> {
  bool _isProcessing = false;
  String? _statusMessage;
  late Map<String, dynamic> _customMergedData;

  @override
  void initState() {
    super.initState();
    _customMergedData = _calculateMergedData();
  }

  Map<String, dynamic> _calculateMergedData() {
    final Map<String, dynamic> merged = {};
    if (widget.conflictingEntries.isEmpty) return merged;

    // 1. Seed with all fields from all conflicting entries (starting with the primary entry)
    for (final entry in widget.conflictingEntries) {
      final data = entry['data'];
      if (data is Map) {
        data.forEach((k, v) {
          if (v != null && !merged.containsKey(k.toString())) {
            merged[k.toString()] = v;
          }
        });
      }
    }

    // 2. Ensure meta fields (eventKey, matchKey, matchNumber, targetTeamNumber) are copied from entry top-level if missing
    for (final entry in widget.conflictingEntries) {
      if (entry['eventKey'] != null && merged['eventKey'] == null) merged['eventKey'] = entry['eventKey'];
      if (entry['matchKey'] != null && merged['matchKey'] == null) merged['matchKey'] = entry['matchKey'];
      if (entry['matchNumber'] != null && merged['matchNumber'] == null) merged['matchNumber'] = entry['matchNumber'];
      if (entry['targetTeamNumber'] != null && merged['targetTeamNumber'] == null) merged['targetTeamNumber'] = entry['targetTeamNumber'];
    }

    // 3. For any fields defined in config, calculate consensus averages / majority votes
    for (final field in widget.fields) {
      final id = field.id;
      final values = widget.conflictingEntries
          .map((e) => e['data'] is Map ? e['data'][id] : null)
          .where((v) => v != null)
          .toList();

      if (values.isNotEmpty) {
        if (['number', 'counter', 'slider', 'range', 'rating'].contains(field.type.toLowerCase())) {
          double sum = 0;
          int count = 0;
          for (final v in values) {
            if (v is num) {
              sum += v.toDouble();
              count++;
            } else if (v is String) {
              final parsed = double.tryParse(v);
              if (parsed != null) {
                sum += parsed;
                count++;
              }
            }
          }
          if (count > 0) {
            final avg = sum / count;
            merged[id] = (avg % 1 == 0) ? avg.toInt() : double.parse(avg.toStringAsFixed(1));
          }
        } else if (field.type.toLowerCase() == 'checkbox') {
          // Majority vote for booleans
          final trueCount = values.where((v) => v == true || v == 'true' || v == 1).length;
          merged[id] = trueCount >= (values.length / 2);
        } else {
          // For text, take the first non-empty value
          final nonEmpties = values.where((v) => v.toString().trim().isNotEmpty).toList();
          if (nonEmpties.isNotEmpty) {
            merged[id] = nonEmpties.first;
          }
        }
      }

      // 4. Ensure required fields have at least a default fallback so server validation passes
      if (field.required && (merged[id] == null || (merged[id] is String && (merged[id] as String).isEmpty && field.type.toLowerCase() != 'text'))) {
        final t = field.type.toLowerCase();
        if (['number', 'counter', 'slider', 'range', 'rating'].contains(t)) {
          merged[id] = field.min ?? 0;
        } else if (t == 'checkbox') {
          merged[id] = false;
        } else if (field.options.isNotEmpty) {
          merged[id] = field.options.first.value;
        } else {
          merged[id] = 0;
        }
      }
    }
    return merged;
  }

  bool _isFieldConflicting(String fieldId) {
    if (widget.conflictingEntries.length < 2) return false;
    final firstVal = widget.conflictingEntries.first['data']?[fieldId]?.toString();
    for (int i = 1; i < widget.conflictingEntries.length; i++) {
      final val = widget.conflictingEntries[i]['data']?[fieldId]?.toString();
      if (val != firstVal) return true;
    }
    return false;
  }

  Future<void> _keepSingleEntry(Map<String, dynamic> winningEntry) async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Resolving conflict...';
    });

    try {
      final winningId = winningEntry['id']?.toString() ?? '';
      final entriesToDelete = widget.conflictingEntries.where((e) => e['id']?.toString() != winningId).toList();

      for (final e in entriesToDelete) {
        final id = e['id']?.toString();
        if (id != null && id.isNotEmpty) {
          final res = await widget.apiService.deleteScoutingEntry(id, type: widget.type);
          if (!res.success) {
            throw Exception(res.message ?? 'Failed to delete duplicate entry ($id)');
          }
        }
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        await widget.apiService.clearScoutingCaches();
        widget.onResolved();
        messenger.showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 10),
                Text('Conflict resolved successfully!'),
              ],
            ),
            backgroundColor: Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _saveAveragedMerge() async {
    setState(() {
      _isProcessing = true;
      _statusMessage = 'Saving merged consensus entry...';
    });

    try {
      if (widget.conflictingEntries.isEmpty) return;

      final primary = widget.conflictingEntries.first;
      final primaryId = primary['id']?.toString() ?? '';

      // Merge data payload ensuring all metadata & original fields are preserved
      final dataToSend = Map<String, dynamic>.from(_customMergedData);
      if (primary['data'] is Map) {
        (primary['data'] as Map).forEach((k, v) {
          if (!dataToSend.containsKey(k.toString())) {
            dataToSend[k.toString()] = v;
          }
        });
      }
      if (dataToSend['eventKey'] == null && primary['eventKey'] != null) {
        dataToSend['eventKey'] = primary['eventKey'];
      }
      if (dataToSend['matchKey'] == null && primary['matchKey'] != null) {
        dataToSend['matchKey'] = primary['matchKey'];
      }
      if (dataToSend['matchNumber'] == null && primary['matchNumber'] != null) {
        dataToSend['matchNumber'] = primary['matchNumber'];
      }
      if (dataToSend['targetTeamNumber'] == null && primary['targetTeamNumber'] != null) {
        dataToSend['targetTeamNumber'] = primary['targetTeamNumber'];
      }

      // Ensure all required fields from config are non-null
      for (final field in widget.fields) {
        if (field.required && (!dataToSend.containsKey(field.id) || dataToSend[field.id] == null)) {
          final t = field.type.toLowerCase();
          if (['number', 'counter', 'slider', 'range', 'rating'].contains(t)) {
            dataToSend[field.id] = field.min ?? 0;
          } else if (t == 'checkbox') {
            dataToSend[field.id] = false;
          } else if (field.options.isNotEmpty) {
            dataToSend[field.id] = field.options.first.value;
          } else {
            dataToSend[field.id] = 0;
          }
        }
      }

      // Update primary entry with merged data
      final updateRes = await widget.apiService.updateScoutingEntry(primaryId, dataToSend, type: widget.type);
      if (!updateRes.success) {
        throw Exception(updateRes.message ?? 'Failed to update scouting entry ($primaryId)');
      }

      // Delete other conflicting entries
      for (int i = 1; i < widget.conflictingEntries.length; i++) {
        final id = widget.conflictingEntries[i]['id']?.toString();
        if (id != null && id.isNotEmpty) {
          final delRes = await widget.apiService.deleteScoutingEntry(id, type: widget.type);
          if (!delRes.success) {
            throw Exception(delRes.message ?? 'Failed to delete duplicate entry ($id)');
          }
        }
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        await widget.apiService.clearScoutingCaches();
        widget.onResolved();
        messenger.showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: Colors.greenAccent),
                SizedBox(width: 10),
                Text('Consensus merged entry saved!'),
              ],
            ),
            backgroundColor: Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  Future<void> _deleteEntry(Map<String, dynamic> entry) async {
    final id = entry['id']?.toString();
    if (id == null || id.isEmpty) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Submission?'),
        content: Text('Are you sure you want to delete the submission from ${entry['scoutUsername'] ?? 'Unknown'}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Deleting entry...';
    });

    try {
      final res = await widget.apiService.deleteScoutingEntry(id, type: widget.type);
      if (!res.success) {
        throw Exception(res.message ?? 'Failed to delete entry ($id)');
      }
      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        await widget.apiService.clearScoutingCaches();
        widget.onResolved();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Submission deleted'),
            backgroundColor: Color(0xFF1E293B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _statusMessage = 'Error: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);

    final distinctFieldIds = <String>{};
    final allFields = <ScoutingFieldModel>[];
    for (final f in widget.fields) {
      if (f.type != 'section' && distinctFieldIds.add(f.id)) {
        allFields.add(f);
      }
    }
    for (final entry in widget.conflictingEntries) {
      final data = entry['data'];
      if (data is Map) {
        for (final k in data.keys) {
          if (distinctFieldIds.add(k.toString())) {
            allFields.add(ScoutingFieldModel(id: k.toString(), label: k.toString(), type: 'text'));
          }
        }
      }
    }

    final conflictCount = allFields.where((f) => _isFieldConflicting(f.id)).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xF80F172A) : const Color(0xF8F8FAFC),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
          ),
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
                        color: Colors.amberAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.compare_arrows_rounded, color: Colors.amberAccent, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: primaryTextColor,
                            ),
                          ),
                          Text(
                            widget.subtitle,
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

              // Summary Banner
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.amberAccent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amberAccent.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.amberAccent, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '$conflictCount field discrepancy(ies) between ${widget.conflictingEntries.length} submissions.',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.amberAccent,
                          ),
                        ),
                      ),
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amberAccent,
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _isProcessing ? null : _saveAveragedMerge,
                        icon: const Icon(Icons.merge_type_rounded, size: 16),
                        label: const Text('Merge / Avg'),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              if (_isProcessing)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const CircularProgressIndicator(),
                      if (_statusMessage != null) ...[
                        const SizedBox(height: 8),
                        Text(_statusMessage!, style: TextStyle(color: secondaryTextColor, fontSize: 13)),
                      ],
                    ],
                  ),
                ),

              // Comparison Table
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
                  children: [
                    // Submissions Cards
                    Text(
                      'Submissions (${widget.conflictingEntries.length})',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: widget.conflictingEntries.asMap().entries.map((item) {
                        final idx = item.key;
                        final entry = item.value;
                        final scouter = entry['scoutUsername'] ?? entry['username'] ?? 'Scouter ${idx + 1}';
                        final created = entry['createdAt'] != null ? entry['createdAt'].toString().substring(11, 16) : '';

                        return Expanded(
                          child: Container(
                            margin: EdgeInsets.only(right: idx < widget.conflictingEntries.length - 1 ? 8 : 0),
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '#${idx + 1}: $scouter',
                                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: primaryTextColor),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    IconButton(
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.redAccent),
                                      onPressed: () => _deleteEntry(entry),
                                      tooltip: 'Delete this submission',
                                    ),
                                  ],
                                ),
                                if (created.isNotEmpty)
                                  Text('Time: $created', style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.blueAccent.withValues(alpha: 0.2),
                                      foregroundColor: Colors.blueAccent,
                                      elevation: 0,
                                      padding: const EdgeInsets.symmetric(vertical: 6),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    ),
                                    onPressed: _isProcessing ? null : () => _keepSingleEntry(entry),
                                    child: const Text('Keep This', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Side-by-Side Field Diff
                    Text(
                      'Field-by-Field Breakdown',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: primaryTextColor),
                    ),
                    const SizedBox(height: 8),

                    ...allFields.map((field) {
                      final isConflict = _isFieldConflicting(field.id);
                      final label = field.label.isNotEmpty ? field.label : field.id;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: isConflict
                              ? Colors.amberAccent.withValues(alpha: isDark ? 0.08 : 0.06)
                              : (isDark ? Colors.white.withValues(alpha: 0.02) : Colors.black.withValues(alpha: 0.01)),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isConflict
                                ? Colors.amberAccent.withValues(alpha: 0.4)
                                : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.06)),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  label,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                    color: isConflict ? Colors.amberAccent : primaryTextColor,
                                  ),
                                ),
                                const Spacer(),
                                if (isConflict)
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.amberAccent.withValues(alpha: 0.2),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text(
                                      'DIFF',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amberAccent),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: widget.conflictingEntries.asMap().entries.map((item) {
                                final idx = item.key;
                                final entry = item.value;
                                final val = entry['data']?[field.id];

                                return Expanded(
                                  child: Container(
                                    margin: EdgeInsets.only(right: idx < widget.conflictingEntries.length - 1 ? 8 : 0),
                                    padding: const EdgeInsets.all(8),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.02),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Sub #${idx + 1}', style: TextStyle(fontSize: 10, color: secondaryTextColor)),
                                        const SizedBox(height: 2),
                                        Text(
                                          _formatVal(val),
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                            color: isConflict ? Colors.amberAccent : primaryTextColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatVal(dynamic val) {
    if (val == null) return '--';
    if (val is bool) return val ? 'Yes' : 'No';
    if (val is List) return val.join(', ');
    return val.toString();
  }
}
