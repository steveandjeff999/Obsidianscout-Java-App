import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/ported_page_kit.dart';

/// Firebase Cloud Messaging credentials for push alerts (superadmins). Same data as the website's fcm-settings.html.
class FcmSettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const FcmSettingsScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<FcmSettingsScreen> createState() => _FcmSettingsScreenState();
}

class _FcmSettingsScreenState extends State<FcmSettingsScreen> {
  bool _loading = true;
  bool _enabled = false;
  bool _initialized = false;
  bool _hasStoredServiceAccount = false;
  bool _saving = false;
  bool _testing = false;
  String? _alert;
  bool _alertIsError = false;

  final _serviceAccount = TextEditingController();
  final _projectId = TextEditingController();
  final _apiKey = TextEditingController();
  final _appId = TextEditingController();
  final _senderId = TextEditingController();
  final _vapidKey = TextEditingController();

  bool get _isSuper => widget.apiService.currentUserRole.toUpperCase() == 'SUPERADMIN';

  @override
  void initState() {
    super.initState();
    if (_isSuper) _load();
  }

  @override
  void dispose() {
    for (final c in [_serviceAccount, _projectId, _apiKey, _appId, _senderId, _vapidKey]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.apiService.requestJson('GET', '/api/admin/fcm');
    if (!mounted) return;
    final cfg = jsonMap(res.data);
    setState(() {
      _loading = false;
      if (!res.success) return;
      _enabled = jsonBool(cfg['enabled']);
      _initialized = jsonBool(cfg['isInitialized']);
      _hasStoredServiceAccount = jsonBool(cfg['hasServiceAccountJson']);
      _projectId.text = jsonStr(cfg['projectId']);
      _apiKey.text = jsonStr(cfg['apiKey']);
      _appId.text = jsonStr(cfg['appId']);
      _senderId.text = jsonStr(cfg['messagingSenderId']);
      _vapidKey.text = jsonStr(cfg['vapidKey']);
    });
  }

  void _showAlert(String msg, {bool error = false}) => setState(() {
        _alert = msg;
        _alertIsError = error;
      });

  /// Fills the fields from a service-account.json, a google-services.json, or a web firebaseConfig.
  void _parseJson(String text, {required bool serviceAccount}) {
    dynamic parsed;
    try {
      parsed = jsonDecode(text);
    } catch (_) {
      return;
    }
    if (parsed is! Map) return;
    if (parsed['type'] == 'service_account' || parsed['private_key'] != null) {
      if (_serviceAccount.text != text) _serviceAccount.text = text;
      if (parsed['project_id'] != null) _projectId.text = '${parsed['project_id']}';
      _showAlert(context.tr('fcm.service_account_loaded', 'Service Account JSON loaded and Project ID extracted!'));
      return;
    }
    if (parsed['apiKey'] != null) _apiKey.text = '${parsed['apiKey']}';
    if (parsed['appId'] != null) _appId.text = '${parsed['appId']}';
    if (parsed['messagingSenderId'] != null) _senderId.text = '${parsed['messagingSenderId']}';
    if (parsed['projectId'] != null) _projectId.text = '${parsed['projectId']}';
    final info = parsed['project_info'];
    if (info is Map) {
      if (info['project_id'] != null) _projectId.text = '${info['project_id']}';
      if (info['project_number'] != null) _senderId.text = '${info['project_number']}';
    }
    final clients = parsed['client'];
    if (clients is List && clients.isNotEmpty && clients.first is Map) {
      final client = clients.first as Map;
      final appId = client['client_info'] is Map ? (client['client_info'] as Map)['mobilesdk_app_id'] : null;
      if (appId != null) _appId.text = '$appId';
      final keys = client['api_key'];
      if (keys is List && keys.isNotEmpty && keys.first is Map && (keys.first as Map)['current_key'] != null) {
        _apiKey.text = '${(keys.first as Map)['current_key']}';
      }
    }
    _showAlert(serviceAccount
        ? context.tr('fcm.client_config_loaded', 'Client config loaded! API Key, App ID, and Messaging Sender ID extracted.')
        : context.tr('fcm.public_keys_extracted', 'Public client keys (API Key, App ID, Messaging Sender ID) extracted successfully!'));
  }

  Future<void> _pickJson({required bool serviceAccount}) async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: ['json']);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!mounted) return;
    _parseJson(utf8.decode(bytes, allowMalformed: true), serviceAccount: serviceAccount);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final res = await widget.apiService.requestJson('POST', '/api/admin/fcm', body: {
      'enabled': _enabled,
      'projectId': _projectId.text.trim(),
      'apiKey': _apiKey.text.trim(),
      'appId': _appId.text.trim(),
      'messagingSenderId': _senderId.text.trim(),
      'serviceAccountJson': _serviceAccount.text.trim(),
      'vapidKey': _vapidKey.text.trim(),
    });
    if (!mounted) return;
    setState(() => _saving = false);
    if (!res.success) {
      _showAlert('Failed to save FCM settings: ${res.message ?? 'Request failed'}', error: true);
      return;
    }
    if (jsonBool(jsonMap(res.data)['success'])) {
      _showAlert(context.tr('fcm.save_success', 'FCM Settings saved to database successfully!'));
      _serviceAccount.clear();
      await _load();
    } else {
      _showAlert('Settings saved, but Firebase SDK failed to initialize. Please check your credentials.', error: true);
      setState(() => _initialized = false);
    }
  }

  Future<void> _test() async {
    setState(() => _testing = true);
    final res = await widget.apiService.requestJson('POST', '/api/admin/fcm/test');
    if (!mounted) return;
    setState(() => _testing = false);
    final data = jsonMap(res.data);
    _showAlert(jsonStr(data['message'], res.message ?? 'Test FCM failed'), error: !res.success || !jsonBool(data['success']));
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSuper) {
      return PortedLocked(
        title: context.tr('fcm.locked_title', 'Admin Only'),
        message: context.tr('fcm.locked_notice', 'You need admin access to edit FCM Push Notification settings.'),
      );
    }
    final statusText = _enabled && _initialized
        ? context.tr('fcm.status_active', 'FCM Active & Ready')
        : _enabled
            ? context.tr('fcm.status_uninit', 'Enabled (Uninitialized / Check JSON)')
            : context.tr('fcm.status_disabled', 'FCM Disabled');
    final statusColor = _enabled && _initialized ? ObsidianUITheme.successGreen : ObsidianUITheme.warningOrange;
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          icon: Icons.local_fire_department_rounded,
          title: context.tr('fcm.title', 'Firebase Push Notifications (FCM)'),
          subtitle: context.tr('fcm.notice',
              'Configure Google Firebase Cloud Messaging credentials for real-time mobile & browser chat alerts. Saved to database for cluster-wide synchronization.'),
          child: Align(alignment: Alignment.centerLeft, child: PortedBadge(statusText, color: statusColor)),
        ),
        if (_loading) const PortedLoading() else ..._buildForm(context),
      ],
    );
  }

  List<Widget> _buildForm(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return [
      PortedSection(
        title: context.tr('fcm.enable_label', 'Enable Firebase Push Notifications'),
        subtitle: context.tr('fcm.enable_subtext', 'Allow the server to push real-time alerts to Flutter mobile apps and web devices.'),
        child: SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          value: _enabled,
          title: Text(_enabled ? 'On' : 'Off'),
          onChanged: (v) => setState(() => _enabled = v),
        ),
      ),
      PortedSection(
        title: context.tr('fcm.section_service_account', '1. Service Account Credentials (JSON)'),
        subtitle: context
            .tr('fcm.service_account_subtext',
                'Download your service-account.json file from Firebase Console -> Project Settings -> Service Accounts -> Generate New Private Key.')
            .replaceAll(RegExp(r'</?code>'), ''),
        actions: [
          OutlinedButton.icon(
            onPressed: () => _pickJson(serviceAccount: true),
            icon: const Icon(Icons.file_open_rounded, size: 18),
            label: const Text('Load service-account.json'),
          ),
        ],
        child: TextField(
          controller: _serviceAccount,
          minLines: 3,
          maxLines: 8,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          onChanged: (v) => _parseJson(v, serviceAccount: true),
          decoration: InputDecoration(
            labelText: context.tr('fcm.paste_label', 'Or Paste Service Account JSON:'),
            hintText: _hasStoredServiceAccount
                ? context.tr('fcm.placeholder_stored', '(Service Account JSON stored in database. Paste new JSON here to update)')
                : '{ "type": "service_account", "project_id": "your-project-id", ... }',
            hintMaxLines: 3,
          ),
        ),
      ),
      PortedSection(
        title: context.tr('fcm.section_public', '2. Public Firebase Client Settings'),
        subtitle: context
            .tr('fcm.public_subtext', 'Served via /api/config/fcm-public so Flutter apps connect dynamically without rebuilding app binaries.')
            .replaceAll(RegExp(r'</?code>'), ''),
        actions: [
          OutlinedButton.icon(
            onPressed: () => _pickJson(serviceAccount: false),
            icon: const Icon(Icons.phone_android_rounded, size: 18),
            label: const Text('Upload google-services.json'),
          ),
        ],
        child: Column(
          children: [
            TextField(
                controller: _projectId,
                decoration: InputDecoration(labelText: context.tr('fcm.project_id_label', 'Project ID:'), hintText: 'e.g. obsidianscout')),
            TextField(
                controller: _apiKey,
                decoration: InputDecoration(labelText: context.tr('fcm.api_key_label', 'API Key (apiKey):'), hintText: 'AIzaSy...')),
            TextField(
                controller: _appId,
                decoration: InputDecoration(
                    labelText: context.tr('fcm.app_id_label', 'App ID (appId):'), hintText: '1:123456789:android:abcdef')),
            TextField(
                controller: _senderId,
                decoration:
                    InputDecoration(labelText: context.tr('fcm.sender_id_label', 'Messaging Sender ID:'), hintText: '123456789012')),
            TextField(
                controller: _vapidKey,
                decoration: InputDecoration(
                    labelText: context.tr('fcm.vapid_key_label', 'VAPID Web Key (Optional for Web Push):'), hintText: 'BEl62i...')),
          ],
        ),
      ),
      if (_alert != null)
        PortedNotice(_alert!, icon: _alertIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Wrap(spacing: 10, runSpacing: 8, children: [
          OutlinedButton.icon(
            onPressed: _testing ? null : _test,
            icon: const Icon(Icons.notifications_active_rounded, size: 18),
            label: Text(context.tr('fcm.btn_test', 'Send Test Notification')),
          ),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: const Icon(Icons.save_rounded, size: 18),
            label: Text(context.tr('fcm.btn_save', 'Save to Database')),
          ),
        ]),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text('The service account key is sent to your server only.', style: TextStyle(fontSize: 11, color: muted)),
      ),
    ];
  }
}
