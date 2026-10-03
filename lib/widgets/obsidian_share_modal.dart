import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../models/share_models.dart';
import '../services/api_service.dart';
import 'obsidian_glass_card.dart';

class ObsidianShareModal extends StatefulWidget {
  final ApiService apiService;
  final String defaultTitle;
  final String resourceType; // graph, predictor, event_predictor, all_data, qual_data, pit_data, match_data, custom_analytics, match_planning
  final String? targetEventKey;
  final Map<String, dynamic> queryConfig;
  final Map<String, dynamic>? snapshotData;

  const ObsidianShareModal({
    super.key,
    required this.apiService,
    required this.defaultTitle,
    required this.resourceType,
    this.targetEventKey,
    this.queryConfig = const {},
    this.snapshotData,
  });

  static Future<void> show(
    BuildContext context, {
    required ApiService apiService,
    required String defaultTitle,
    required String resourceType,
    String? targetEventKey,
    Map<String, dynamic> queryConfig = const {},
    Map<String, dynamic>? snapshotData,
  }) {
    return showDialog(
      context: context,
      builder: (ctx) => ObsidianShareModal(
        apiService: apiService,
        defaultTitle: defaultTitle,
        resourceType: resourceType,
        targetEventKey: targetEventKey,
        queryConfig: queryConfig,
        snapshotData: snapshotData,
      ),
    );
  }

  @override
  State<ObsidianShareModal> createState() => _ObsidianShareModalState();
}

class _ObsidianShareModalState extends State<ObsidianShareModal> {
  late TextEditingController _titleController;
  late TextEditingController _descController;
  late TextEditingController _allowedTeamsController;
  late TextEditingController _pinController;

  String _accessScope = 'public'; // public, team, alliance, pin
  String _shareMode = 'live_query'; // live_query, frozen_snapshot
  String _expiryChoice = '24h'; // 1h, 24h, 7d, 30d, custom, never
  DateTime? _customExpiryDate;
  bool _redactPrivateNotes = true;
  bool _redactScoutNames = false;

  bool _isCreating = false;
  ShareLinkModel? _createdShare;

  @override
  void initState() {
    super.initState();
    _titleController = TextEditingController(text: widget.defaultTitle);
    _descController = TextEditingController();
    _allowedTeamsController = TextEditingController();
    _pinController = TextEditingController();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descController.dispose();
    _allowedTeamsController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  DateTime? _calculateExpiresAt() {
    final now = DateTime.now();
    switch (_expiryChoice) {
      case '1h':
        return now.add(const Duration(hours: 1));
      case '24h':
        return now.add(const Duration(hours: 24));
      case '7d':
        return now.add(const Duration(days: 7));
      case '30d':
        return now.add(const Duration(days: 30));
      case 'custom':
        return _customExpiryDate;
      case 'never':
      default:
        return null;
    }
  }

  Future<void> _handleGenerate() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a link title')),
      );
      return;
    }

    if (_accessScope == 'pin') {
      final pin = _pinController.text.trim();
      if (pin.length < 4) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter a PIN of at least 4 digits')),
        );
        return;
      }
    }

    if (_expiryChoice == 'custom' && _customExpiryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please choose a custom expiration date')),
      );
      return;
    }

    setState(() => _isCreating = true);

    final req = CreateShareRequest(
      title: title,
      description: _descController.text.trim().isNotEmpty ? _descController.text.trim() : null,
      resourceType: widget.resourceType,
      targetEventKey: widget.targetEventKey,
      shareMode: _shareMode,
      queryConfig: widget.queryConfig,
      snapshotData: _shareMode == 'frozen_snapshot' ? widget.snapshotData : null,
      accessScope: _accessScope,
      allowedTeams: _accessScope == 'alliance' ? _allowedTeamsController.text.trim() : null,
      pin: _accessScope == 'pin' ? _pinController.text.trim() : null,
      redactPrivateNotes: _redactPrivateNotes,
      redactScoutNames: _redactScoutNames,
      expiresAt: _calculateExpiresAt(),
    );

    final result = await widget.apiService.createSharedLink(req);

    if (mounted) {
      setState(() {
        _isCreating = false;
        _createdShare = result;
      });

      if (result == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to generate share link')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 540),
        child: ObsidianGlassCard(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.share_outlined, color: theme.colorScheme.primary, size: 24),
                        const SizedBox(width: 10),
                        Text(
                          _createdShare == null ? context.tr('share_modal.title', 'Share Data & Visuals') : context.tr('share_modal.created_title', 'Share Link Created!'),
                          style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                      tooltip: 'Close',
                    ),
                  ],
                ),
                const Divider(height: 24),

                if (_createdShare == null) ...[
                  // Link Title
                  TextField(
                    controller: _titleController,
                    decoration: InputDecoration(
                      labelText: context.tr('share_modal.link_title', 'Link Title'),
                      hintText: context.tr('share_modal.link_title_placeholder', 'e.g. 2026 Midwest Regional Top Scorers'),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Access Scope
                  Text(
                    context.tr('share_modal.access_scope', 'Access Scope'),
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _buildScopeChip('public', context.tr('shares.scope_public', 'Public'), Icons.public),
                      _buildScopeChip('alliance', context.tr('shares.scope_alliance', 'Selected Team(s)'), Icons.group_work),
                      _buildScopeChip('pin', context.tr('shares.scope_pin', 'PIN Protected'), Icons.lock),
                    ],
                  ),

                  if (_accessScope == 'alliance') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _allowedTeamsController,
                      decoration: InputDecoration(
                        labelText: context.tr('share_modal.allowed_teams', 'Allowed Team Numbers'),
                        hintText: context.tr('share_modal.allowed_teams_placeholder', 'e.g. 254, 1678, 1114'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],

                  if (_accessScope == 'pin') ...[
                    const SizedBox(height: 10),
                    TextField(
                      controller: _pinController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: context.tr('share_modal.pin_label', 'Access PIN (4-8 digits)'),
                        hintText: context.tr('share_modal.pin_placeholder', 'Enter access PIN code'),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ],

                  const SizedBox(height: 16),

                  // Expiration
                  Text(
                    context.tr('share_modal.expiration', 'Expiration'),
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: _expiryChoice,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
                    ),
                    items: [
                      DropdownMenuItem(value: '1h', child: Text(context.tr('share_modal.exp_1h', '1 Hour (Quick match review)'))),
                      DropdownMenuItem(value: '24h', child: Text(context.tr('share_modal.exp_24h', '24 Hours'))),
                      DropdownMenuItem(value: '7d', child: Text(context.tr('share_modal.exp_7d', '7 Days (Competition week)'))),
                      DropdownMenuItem(value: '30d', child: Text(context.tr('share_modal.exp_30d', '30 Days'))),
                      DropdownMenuItem(value: 'never', child: Text(context.tr('share_modal.exp_never', 'Never (Permanent)'))),
                    ],
                    onChanged: (val) {
                      if (val != null) setState(() => _expiryChoice = val);
                    },
                  ),

                  const SizedBox(height: 16),

                  // Data Mode
                  Text(
                    context.tr('share_modal.data_mode', 'Data Mode'),
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'live_query',
                        label: Text(context.tr('share_modal.mode_live_title', 'Live Feed')),
                        icon: const Icon(Icons.sync, size: 16),
                      ),
                      ButtonSegment(
                        value: 'frozen_snapshot',
                        label: Text(context.tr('share_modal.mode_snapshot_title', 'Snapshot')),
                        icon: const Icon(Icons.camera_alt, size: 16),
                      ),
                    ],
                    selected: {_shareMode},
                    onSelectionChanged: (set) => setState(() => _shareMode = set.first),
                  ),

                  const SizedBox(height: 16),

                  // Privacy Toggles
                  SwitchListTile(
                    title: Text(context.tr('share_modal.redact_notes', 'Redact Private Scout Notes'), style: const TextStyle(fontSize: 14)),
                    subtitle: Text(context.tr('share_modal.redact_notes_desc', 'Strip internal commentary from recipients'), style: const TextStyle(fontSize: 12)),
                    value: _redactPrivateNotes,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _redactPrivateNotes = val),
                  ),
                  SwitchListTile(
                    title: Text(context.tr('share_modal.redact_scouts', 'Hide Scout Names'), style: const TextStyle(fontSize: 14)),
                    subtitle: Text(context.tr('share_modal.redact_scouts_desc', 'Anonymize individual scout attribution'), style: const TextStyle(fontSize: 12)),
                    value: _redactScoutNames,
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setState(() => _redactScoutNames = val),
                  ),

                  const SizedBox(height: 20),

                  // Generate Button
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _isCreating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.link),
                    label: Text(_isCreating ? context.tr('share_modal.btn_creating', 'Generating Link...') : context.tr('share_modal.btn_create', 'Create Share Link')),
                    onPressed: _isCreating ? null : _handleGenerate,
                  ),
                ] else ...[
                  // Success Result View
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _createdShare!.title,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Scope: ${_createdShare!.accessScope.toUpperCase()} • ${_createdShare!.shareMode == 'frozen_snapshot' ? 'Snapshot' : 'Live'}',
                          style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 12),
                        ),
                        const SizedBox(height: 14),
                        Center(
                          child: Container(
                            width: 170,
                            height: 170,
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 8,
                                  spreadRadius: 1,
                                ),
                              ],
                            ),
                            child: Center(
                              child: QrImageView(
                                data: _getShareUrl(),
                                version: QrVersions.auto,
                                size: 150.0,
                                backgroundColor: Colors.white,
                                errorCorrectionLevel: QrErrorCorrectLevel.M,
                                errorStateBuilder: (cxt, err) {
                                  return const Center(
                                    child: Text(
                                      'QR unavailable',
                                      style: TextStyle(color: Colors.red, fontSize: 10),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: isDark ? Colors.black26 : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white10),
                          ),
                          child: SelectableText(
                            _getShareUrl(),
                            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: Text(context.tr('shares.preview', 'Open')),
                                onPressed: () async {
                                  final uri = Uri.tryParse(_getShareUrl());
                                  if (uri != null) {
                                    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
                                      await launchUrl(uri, mode: LaunchMode.platformDefault);
                                    }
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: OutlinedButton.icon(
                                icon: const Icon(Icons.copy, size: 18),
                                label: Text(context.tr('shares.copy_link', 'Copy Link')),
                                onPressed: () {
                                  Clipboard.setData(ClipboardData(text: _getShareUrl()));
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(content: Text(context.tr('shares.copied_to_clipboard', 'Link copied to clipboard!'))),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              child: Text(context.tr('share_modal.btn_done', 'Done')),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getShareUrl() {
    if (_createdShare?.shareUrl != null && _createdShare!.shareUrl!.isNotEmpty) {
      if (_createdShare!.shareUrl!.startsWith('http')) {
        return _createdShare!.shareUrl!;
      }
      return '${widget.apiService.serverUrl}${_createdShare!.shareUrl}';
    }
    return '${widget.apiService.serverUrl}/shared/${_createdShare?.token ?? ''}';
  }

  Widget _buildScopeChip(String value, String label, IconData icon) {
    final isSelected = _accessScope == value;
    final theme = Theme.of(context);
    return ChoiceChip(
      avatar: Icon(icon, size: 16, color: isSelected ? theme.colorScheme.onPrimary : null),
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) setState(() => _accessScope = value);
      },
    );
  }
}
