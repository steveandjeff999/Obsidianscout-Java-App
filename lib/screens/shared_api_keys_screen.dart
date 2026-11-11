import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/server_compat.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/ported_page_kit.dart';

/// Server-wide TBA / FIRST / Match 13 keys that teams without their own fall back to (superadmins). Same data as
/// the "Shared API Keys" card on the website's Admin Settings page. Needs server API level
/// [kSharedApiKeysServerApiLevel]; callers only open it from that level on.
class SharedApiKeysScreen extends StatefulWidget {
  final ApiService apiService;

  const SharedApiKeysScreen({super.key, required this.apiService});

  @override
  State<SharedApiKeysScreen> createState() => _SharedApiKeysScreenState();
}

class _SharedApiKeysScreenState extends State<SharedApiKeysScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  String? _alert;
  bool _alertIsError = false;
  List<String> _rateLimited = const [];

  final _frcTba = TextEditingController();
  final _frcFirstUser = TextEditingController();
  final _frcFirstKey = TextEditingController();
  final _frcMatch13 = TextEditingController();
  final _ftcFirstUser = TextEditingController();
  final _ftcFirstKey = TextEditingController();

  static const _sourceNames = {'tba': 'The Blue Alliance', 'first': 'FIRST API', 'match13': 'Match 13'};

  bool get _isSuper => widget.apiService.currentUserRole.toUpperCase() == 'SUPERADMIN';

  @override
  void initState() {
    super.initState();
    if (_isSuper) _load();
  }

  @override
  void dispose() {
    for (final c in [_frcTba, _frcFirstUser, _frcFirstKey, _frcMatch13, _ftcFirstUser, _ftcFirstKey]) {
      c.dispose();
    }
    super.dispose();
  }

  /// Fills the form from the server's answer. Secrets come back masked ("********"); sending the mask back keeps
  /// the stored value.
  void _fill(dynamic data) {
    final body = jsonMap(data);
    final frc = jsonMap(body['frc']);
    final ftc = jsonMap(body['ftc']);
    final frcKeys = jsonMap(frc['keys']);
    final ftcKeys = jsonMap(ftc['keys']);
    _frcTba.text = jsonStr(frcKeys['tbaKey']);
    _frcFirstUser.text = jsonStr(frcKeys['firstUsername']);
    _frcFirstKey.text = jsonStr(frcKeys['firstKey']);
    _frcMatch13.text = jsonStr(frcKeys['match13Key']);
    _ftcFirstUser.text = jsonStr(ftcKeys['firstUsername']);
    _ftcFirstKey.text = jsonStr(ftcKeys['firstKey']);
    _rateLimited = [
      for (final s in jsonList(frc['rateLimited'])) 'FRC ${_sourceNames['$s'] ?? s}',
      for (final s in jsonList(ftc['rateLimited'])) 'FTC ${_sourceNames['$s'] ?? s}',
    ];
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await widget.apiService.requestJson('GET', '/api/admin/shared-api-keys');
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (res.success) {
        _fill(res.data);
      } else {
        _loadError = res.message ?? 'Request failed';
      }
    });
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    final res = await widget.apiService.requestJson('PUT', '/api/admin/shared-api-keys', body: {
      'frc': {
        'tbaKey': _frcTba.text.trim(),
        'firstUsername': _frcFirstUser.text.trim(),
        'firstKey': _frcFirstKey.text.trim(),
        'match13Key': _frcMatch13.text.trim(),
      },
      'ftc': {
        'firstUsername': _ftcFirstUser.text.trim(),
        'firstKey': _ftcFirstKey.text.trim(),
      },
    });
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (res.success) {
        _fill(res.data);
        _alert = context.tr('shared_keys.saved', 'Shared API keys saved.');
        _alertIsError = false;
      } else {
        _alert = 'Failed to save shared API keys: ${res.message ?? 'Request failed'}';
        _alertIsError = true;
      }
    });
  }

  Widget _field(TextEditingController controller, String label, {bool secret = false}) => TextField(
        controller: controller,
        obscureText: secret,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(labelText: label),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: ObsidianUITheme.getBackgroundColor(context),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: Text(context.tr('shared_keys.title', 'Shared API Keys')),
      ),
      body: !_isSuper
          ? PortedLocked(
              title: context.tr('shared_keys.locked_title', 'Superadmin Only'),
              message: context.tr('shared_keys.locked_notice', 'Only superadmins can edit the shared API keys.'),
            )
          : PortedPageList(
              onRefresh: _load,
              isBarsVisible: false,
              children: [
                PortedSection(
                  icon: Icons.key_rounded,
                  title: context.tr('shared_keys.title', 'Shared API Keys'),
                  subtitle: context.tr('shared_keys.desc',
                      "Used by every team that has no key of its own for a source. A team's own key, or one from its alliance, always comes first. Teams on a shared key see a banner asking them to add their own, and a warning when the shared key hits its rate limit."),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: PortedBadge(context.tr('shared_keys.beta', 'Beta'), color: ObsidianUITheme.warningOrange),
                  ),
                ),
                if (_loading)
                  const PortedLoading()
                else if (_loadError != null)
                  PortedError(message: _loadError!, onRetry: _load)
                else ..._buildForm(context),
              ],
            ),
    );
  }

  List<Widget> _buildForm(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return [
      if (_rateLimited.isNotEmpty)
        PortedNotice('Rate-limited right now: ${_rateLimited.join(', ')}.', icon: Icons.warning_amber_rounded),
      PortedSection(
        title: 'FRC',
        child: Column(children: [
          _field(_frcTba, context.tr('config.tba_key', 'TBA key'), secret: true),
          _field(_frcFirstUser, context.tr('config.first_username', 'FIRST username')),
          _field(_frcFirstKey, context.tr('config.first_key', 'FIRST key'), secret: true),
          _field(_frcMatch13, context.tr('config.match13_key', 'Match 13 API Key (optional)'), secret: true),
        ]),
      ),
      PortedSection(
        title: 'FTC',
        child: Column(children: [
          _field(_ftcFirstUser, context.tr('config.first_username', 'FIRST username')),
          _field(_ftcFirstKey, context.tr('config.first_key', 'FIRST key'), secret: true),
        ]),
      ),
      if (_alert != null)
        PortedNotice(_alert!, icon: _alertIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_rounded, size: 18),
          label: Text(context.tr('shared_keys.save', 'Save shared keys')),
        ),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Text(
          context.tr('shared_keys.clear_hint', 'Clear a field and save to stop sharing that key.'),
          style: TextStyle(fontSize: 11, color: muted),
        ),
      ),
    ];
  }
}
