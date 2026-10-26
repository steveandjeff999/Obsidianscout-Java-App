import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/ported_page_kit.dart';

/// Export the team's data to a backup file and import one back (admins; superadmins can use the global scope).
/// Same data as the website's backup.html (Data Sharing).
class BackupScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const BackupScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends State<BackupScreen> {
  String _exportType = 'scouting';
  String _exportFormat = 'obsidiandb';
  String _exportScope = 'team';
  String _importScope = 'team';
  bool _exporting = false;
  bool _importing = false;
  String? _fileName;
  Uint8List? _fileBytes;
  Map<String, dynamic>? _report;

  bool get _isSuper => widget.apiService.currentUserRole.toUpperCase() == 'SUPERADMIN';

  Future<void> _export() async {
    setState(() => _exporting = true);
    final scope = _isSuper ? _exportScope : 'team';
    final res = await widget.apiService.requestBytes('/api/admin/export',
        query: {'type': _exportType, 'format': _exportFormat, 'scope': scope});
    if (!mounted) return;
    setState(() => _exporting = false);
    final ext = _exportFormat == 'obsidiandb' ? 'obsidiandb' : 'zip';
    final team = widget.apiService.currentUser?.teamNumber ?? 0;
    final name = scope == 'global' ? 'global_backup_$_exportType.$ext' : 'team_${team}_backup_$_exportType.$ext';
    await saveDownloadedBytes(context, res, name, ext == 'zip' ? 'application/zip' : 'application/octet-stream');
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['obsidiandb', 'json', 'zip']);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    setState(() {
      _fileName = picked.name;
      _fileBytes = bytes;
    });
  }

  Future<void> _import() async {
    final bytes = _fileBytes;
    final name = _fileName;
    if (bytes == null || name == null) return;
    setState(() {
      _importing = true;
      _report = null;
    });
    final res = await widget.apiService.uploadFile('/api/admin/import',
        bytes: bytes, filename: name, query: {'scope': _isSuper ? _importScope : 'team'});
    if (!mounted) return;
    setState(() {
      _importing = false;
      _fileName = null;
      _fileBytes = null;
      if (res.success) _report = jsonMap(res.data);
    });
    if (res.success) {
      ObsidianFeedback.showSuccess(context, message: 'Data imported successfully');
    } else {
      reportResult(context, res, action: 'Import failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.apiService.isAdmin) {
      return const PortedLocked(title: 'Admin only', message: 'You need admin access to export or import team data.');
    }
    final surface = ObsidianUITheme.getSurfaceColor(context);
    return PortedPageList(
      onRefresh: () async {},
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.tr('nav.backup', 'Data Sharing'),
          subtitle:
              "Export your team's configuration, users, and scouting records to share with other servers or download locally. You can also import data files back into this server instance.",
        ),
        PortedSection(
          icon: Icons.download_rounded,
          title: 'Export Data',
          subtitle: "Download a backup of your team's scouting data or the entire team database.",
          actions: [
            FilledButton(
              onPressed: _exporting ? null : _export,
              child: Text(_exporting ? 'Generating export...' : 'Export and Download'),
            ),
          ],
          child: Column(children: [
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _exportType,
              dropdownColor: surface,
              decoration: const InputDecoration(labelText: 'Data to Export', isDense: true),
              items: const [
                DropdownMenuItem(value: 'scouting', child: Text('Scouting Data Only (Entries)')),
                DropdownMenuItem(value: 'entire', child: Text('Entire Team Database (Users, Configs, Settings & Entries)')),
              ],
              onChanged: (v) => setState(() => _exportType = v ?? 'scouting'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              isExpanded: true,
              initialValue: _exportFormat,
              dropdownColor: surface,
              decoration: const InputDecoration(labelText: 'Export Format', isDense: true),
              items: const [
                DropdownMenuItem(value: 'obsidiandb', child: Text('Custom Backup (.obsidiandb)')),
                DropdownMenuItem(value: 'csv', child: Text('Standard CSV Archive (.zip)')),
              ],
              onChanged: (v) => setState(() => _exportFormat = v ?? 'obsidiandb'),
            ),
            if (_isSuper) ...[
              const SizedBox(height: 10),
              _scopeDropdown('Backup Scope', _exportScope, (v) => setState(() => _exportScope = v)),
            ],
          ]),
        ),
        PortedSection(
          icon: Icons.upload_rounded,
          title: 'Import Data',
          subtitle: 'Upload a previously exported .obsidiandb or .zip file to import records.',
          actions: [
            OutlinedButton.icon(
              onPressed: _importing ? null : _pick,
              icon: const Icon(Icons.folder_open_rounded, size: 18),
              label: const Text('Select Backup File'),
            ),
            FilledButton(
              onPressed: _fileBytes == null || _importing ? null : _import,
              child: Text(_importing ? 'Uploading & Importing...' : 'Import Data'),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _fileBytes == null
                    ? 'Supports .obsidiandb, .json, and .zip formats'
                    : 'Selected file: $_fileName (${(_fileBytes!.length / 1024).toStringAsFixed(1)} KB)',
                style: TextStyle(
                  fontSize: 12.5,
                  color: _fileBytes == null ? ObsidianUITheme.getSecondaryTextColor(context) : ObsidianUITheme.primaryAccent,
                ),
              ),
              if (_isSuper) ...[
                const SizedBox(height: 10),
                _scopeDropdown('Import Scope', _importScope, (v) => setState(() => _importScope = v)),
              ],
            ],
          ),
        ),
        if (_report != null) _buildReport(context, _report!),
      ],
    );
  }

  Widget _scopeDropdown(String label, String value, ValueChanged<String> onChanged) => DropdownButtonFormField<String>(
        isExpanded: true,
        initialValue: value,
        dropdownColor: ObsidianUITheme.getSurfaceColor(context),
        decoration: InputDecoration(labelText: label, isDense: true),
        items: const [
          DropdownMenuItem(value: 'team', child: Text('My Team Only')),
          DropdownMenuItem(value: 'global', child: Text('All Teams & System Data (Superadmin)')),
        ],
        onChanged: (v) => onChanged(v ?? 'team'),
      );

  Widget _buildReport(BuildContext context, Map<String, dynamic> r) {
    final entire = r['type'] == 'entire';
    final global = r['scope'] == 'global';
    final items = <(String, String, String, String)>[
      if (entire) ...[
        ('Users', 'usersImported', 'usersSkipped', 'Created'),
        ('Form Configs', 'configsImported', 'configsUpdated', 'Updated'),
        ('App Settings', 'settingsImported', 'settingsUpdated', 'Updated'),
        ('Alliances', 'alliancesImported', 'alliancesSkipped', 'Created'),
        ('Banners', 'bannersImported', 'bannersSkipped', 'Created'),
        ('Chat Messages', 'chatsImported', 'chatsSkipped', 'Created'),
      ],
      ('Scouting Entries', 'scoutingEntriesImported', 'scoutingEntriesSkipped', 'Created'),
      ('Pit Scouting Entries', 'pitEntriesImported', 'pitEntriesSkipped', 'Created'),
      ('Qualitative Scouting Entries', 'qualEntriesImported', 'qualEntriesSkipped', 'Created'),
      if (global) ...[
        ('API Events (TBA)', 'apiEventsImported', 'apiEventsSkipped', 'Created/Updated'),
        ('API Teams (TBA)', 'apiTeamsImported', 'apiTeamsSkipped', 'Created/Updated'),
        ('API Matches (TBA)', 'apiMatchesImported', 'apiMatchesSkipped', 'Created/Updated'),
        ('EPA/OPR History Cache', 'epaOprHistoryCacheImported', 'epaOprHistoryCacheSkipped', 'Created/Updated'),
        ('Alliance Selections', 'allianceSelectionsImported', 'allianceSelectionsSkipped', 'Created/Updated'),
        ('Push Subscriptions', 'pushSubscriptionsImported', 'pushSubscriptionsSkipped', 'Created'),
        ('User Chat Last Reads', 'chatLastReadsImported', 'chatLastReadsSkipped', 'Created/Updated'),
        ('Password Reset Tokens', 'passwordResetTokensImported', 'passwordResetTokensSkipped', 'Created'),
      ],
    ];
    return PortedSection(
      title: 'Import Report',
      subtitle:
          'Summary: ${jsonStr(r['message'], 'Success')}. Imported type: ${entire ? 'Entire Database' : 'Scouting Data Only'} (${global ? 'Global Scope' : 'Team Scope'}).',
      child: Column(
        children: [
          for (final item in items)
            Builder(builder: (context) {
              final imported = jsonInt(r[item.$2]) ?? 0;
              final skipped = jsonInt(r[item.$3]) ?? 0;
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(children: [
                  Expanded(child: Text(item.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                  Text('$imported / $skipped', style: const TextStyle(fontSize: 13)),
                  const SizedBox(width: 8),
                  imported > 0
                      ? PortedBadge(item.$4, color: ObsidianUITheme.successGreen)
                      : PortedBadge(skipped > 0 ? 'No Change' : '-', color: ObsidianUITheme.getSecondaryTextColor(context)),
                ]),
              );
            }),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerRight,
            child: Text('Imported / Skipped', style: TextStyle(fontSize: 11, color: ObsidianUITheme.getSecondaryTextColor(context))),
          ),
        ],
      ),
    );
  }
}
