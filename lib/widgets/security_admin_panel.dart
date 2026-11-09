import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/security_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_glass_card.dart';

const Color _red = Color(0xFFEF4444);
const Color _amber = Color(0xFFF59E0B);
const Color _green = Color(0xFF10B981);
const Color _sky = Color(0xFF38BDF8);
const Color _slate = Color(0xFF94A3B8);

/// Intrusion detection for superadmins, shown in the Security tab of Server Insights: mode switch, unblock requests,
/// active blocks with unblocking, threat scores, allowlist, protected accounts and the security log.
class SecurityAdminPanel extends StatefulWidget {
  final ApiService apiService;

  const SecurityAdminPanel({super.key, required this.apiService});

  @override
  State<SecurityAdminPanel> createState() => _SecurityAdminPanelState();
}

class _SecurityAdminPanelState extends State<SecurityAdminPanel> {
  static const _logPage = 50;

  SecuritySummary? _summary;
  List<UnblockRequest> _requests = const [];
  List<IpBlock> _blocks = const [];
  List<AllowlistEntry> _allowlist = const [];
  List<ProtectedAccount> _protected = const [];
  List<SecurityEventEntry> _log = const [];
  int _logTotal = 0;
  bool _loading = true;
  String? _error;
  Timer? _timer;

  String _mode = 'observe';
  bool _autoRevoke = false;
  bool _modeDirty = false;

  final _blockIp = TextEditingController();
  final _blockMinutes = TextEditingController(text: '60');
  final _blockReason = TextEditingController();
  final _allowIp = TextEditingController();
  final _allowNote = TextEditingController();
  int? _allowHours = 24;
  final _logIp = TextEditingController();
  final _logUser = TextEditingController();
  String _logType = '';
  String _logSeverity = '';

  String _t(String key, String fallback) => context.tr('security.$key', fallback);

  static const Map<String, String> _typeLabels = {
    'AUTH_FAILURE': 'Failed sign-in',
    'AUTH_FAILURE_UNKNOWN_USER': 'Sign-in, no such account',
    'PASSWORD_SPRAY': 'Password spray',
    'CREDENTIAL_STUFFING': 'Credential stuffing',
    'RATE_LIMITED': 'Rate limited',
    'ROUTE_SCAN': 'Route scan',
    'SCANNER_PATH': 'Scanner probe',
    'INJECTION_PROBE': 'Injection probe',
    'CSRF_FAILURE': 'CSRF failure',
    'FORBIDDEN_ROLE': 'Permission denied',
    'CROSS_TEAM_ACCESS': 'Cross-team access',
    'CLUSTER_SIG_INVALID': 'Forged cluster call',
    'SESSION_ANOMALY': 'Session anomaly',
    'TOKEN_REUSE_REVOKED': 'Revoked session reused',
    'SCRAPING': 'Scraping',
    'FAKE_CRAWLER': 'Fake crawler',
    'CHALLENGE_FAILED': 'Security check failed',
    'ACCOUNT_PROTECTED': 'Account protected',
    'ACCOUNT_PROTECTION_CLEARED': 'Protection cleared',
    'BLOCK_APPLIED': 'Blocked',
    'WOULD_BLOCK': 'Would block',
    'BLOCK_SKIPPED': 'Block skipped',
    'BLOCK_LIFTED': 'Unblocked',
    'UNBLOCK_REQUESTED': 'Unblock requested',
    'UNBLOCK_APPROVED': 'Request approved',
    'UNBLOCK_DENIED': 'Request denied',
    'SESSIONS_REVOKED': 'Sessions signed out',
    'ADMIN_ACTION': 'Superadmin action',
  };

  String _label(String type) => _t('type_${type.toLowerCase()}', _typeLabels[type] ?? type);

  @override
  void initState() {
    super.initState();
    _loadAll();
    _searchLog();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadAll(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final c in [_blockIp, _blockMinutes, _blockReason, _allowIp, _allowNote, _logIp, _logUser]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadAll({bool silent = false}) async {
    final api = widget.apiService;
    final results = await Future.wait([
      api.fetchSecuritySummary(),
      api.fetchUnblockRequests(),
      api.fetchSecurityBlocks(),
      api.fetchSecurityAllowlist(),
      api.fetchProtectedAccounts(),
    ]);
    if (!mounted) return;
    setState(() {
      _loading = false;
      final summary = results[0] as SecuritySummary?;
      if (summary == null) {
        _error = _t('load_failed', "Couldn't load security data.");
        return;
      }
      _error = null;
      _summary = summary;
      if (!_modeDirty) {
        _mode = summary.mode;
        _autoRevoke = summary.autoRevokeSessions;
      }
      _requests = (results[1] as List<UnblockRequest>?) ?? _requests;
      _blocks = (results[2] as List<IpBlock>?) ?? _blocks;
      _allowlist = (results[3] as List<AllowlistEntry>?) ?? _allowlist;
      _protected = (results[4] as List<ProtectedAccount>?) ?? _protected;
    });
  }

  Future<void> _searchLog({bool append = false}) async {
    final page = await widget.apiService.fetchSecurityEvents(
      ip: _logIp.text.trim(),
      user: _logUser.text.trim(),
      type: _logType,
      severity: _logSeverity,
      offset: append ? _log.length : 0,
      limit: _logPage,
    );
    if (!mounted || page == null) return;
    setState(() {
      _log = append ? [..._log, ...page.events] : page.events;
      _logTotal = page.total;
    });
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? _red : null,
      behavior: SnackBarBehavior.floating,
    ));
  }

  Future<void> _run(Future<SecurityActionResult> action, String done) async {
    final result = await action;
    if (!mounted) return;
    if (result.ok) {
      _snack(done);
      await _loadAll(silent: true);
    } else {
      _snack(result.error ?? _t('action_failed', 'Something went wrong'), error: true);
    }
  }

  String _time(int ms) {
    if (ms <= 0) return '';
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
  }

  String _left(int expiresAt) {
    final left = expiresAt - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) return '0:00';
    return '${left ~/ 60000}:${((left % 60000) ~/ 1000).toString().padLeft(2, '0')}';
  }

  // ------------------------------------------------------------------------------------------- dialogs

  /// Asks for a note and, for unblocking, whether to reset the block count and allowlist the address.
  Future<({String note, bool reset, String allowFor})?> _askLift({
    required String title,
    required String description,
    required String confirm,
    String noteLabel = 'Reason',
    bool liftOptions = true,
    bool noteRequired = false,
  }) {
    final note = TextEditingController();
    var reset = true;
    var allowFor = 'none';
    return showDialog<({String note, bool reset, String allowFor})>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(title),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(description),
                const SizedBox(height: 12),
                TextField(
                  controller: note,
                  maxLength: 500,
                  maxLines: 3,
                  decoration: InputDecoration(labelText: noteLabel),
                ),
                if (liftOptions) ...[
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: reset,
                    onChanged: (v) => setLocal(() => reset = v ?? true),
                    title: Text(_t('reset_strikes', 'Reset the block count, so a next block starts at 5 minutes')),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: allowFor,
                    decoration: InputDecoration(labelText: _t('allowlist_address', 'Allowlist this address')),
                    items: [
                      DropdownMenuItem(value: 'none', child: Text(_t('allow_no', 'No'))),
                      DropdownMenuItem(value: '24h', child: Text(_t('allow_24h', 'For 24 hours'))),
                      DropdownMenuItem(value: '7d', child: Text(_t('allow_7d', 'For 7 days'))),
                      DropdownMenuItem(value: 'permanent', child: Text(_t('allow_permanent', 'Until removed'))),
                    ],
                    onChanged: (v) => setLocal(() => allowFor = v ?? 'none'),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: Text(_t('cancel', 'Cancel'))),
            FilledButton(
              onPressed: () {
                if (noteRequired && note.text.trim().isEmpty) return;
                Navigator.pop(context, (note: note.text.trim(), reset: reset, allowFor: allowFor));
              },
              child: Text(confirm),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _liftBlock(IpBlock block) async {
    final answer = await _askLift(
      title: '${_t('unblock', 'Unblock')} ${block.ipOrCidr}',
      description: _t('unblock_desc', 'The address is let through on every node right away and its threat score is reset.'),
      confirm: _t('unblock', 'Unblock'),
    );
    if (answer == null) return;
    await _run(
      widget.apiService.liftSecurityBlock(block.id, reason: answer.note, resetStrikes: answer.reset, allowlistFor: answer.allowFor),
      '${block.ipOrCidr} ${_t('unblocked', 'unblocked')}',
    );
  }

  Future<void> _unblockAll() async {
    final answer = await _askLift(
      title: _t('unblock_all_title', 'Unblock every address'),
      description: _t('unblock_all_desc', 'For when a rule has caught legitimate users, for example everyone at an event.'),
      confirm: _t('unblock_all', 'Unblock all'),
      liftOptions: false,
      noteRequired: true,
    );
    if (answer == null) return;
    await _run(widget.apiService.unblockAllSecurityBlocks(answer.note), _t('all_unblocked', 'Every block lifted'));
  }

  Future<void> _approve(UnblockRequest r) async {
    final answer = await _askLift(
      title: _t('approve_title', 'Approve unblock request'),
      description: _t('approve_desc', 'Lifts the block. The requester is emailed if they left an address.'),
      confirm: _t('approve', 'Approve'),
      noteLabel: _t('note_optional', 'Note to the requester (optional)'),
    );
    if (answer == null) return;
    await _run(
      widget.apiService.approveUnblockRequest(r.id, note: answer.note, resetStrikes: answer.reset, allowlistFor: answer.allowFor),
      _t('approved_done', 'Request approved and block lifted'),
    );
  }

  Future<void> _deny(UnblockRequest r) async {
    final answer = await _askLift(
      title: _t('deny_title', 'Deny unblock request'),
      description: _t('deny_desc', 'The block stays until it runs out (an hour at most).'),
      confirm: _t('deny', 'Deny'),
      noteLabel: _t('note_optional', 'Note to the requester (optional)'),
      liftOptions: false,
    );
    if (answer == null) return;
    await _run(widget.apiService.denyUnblockRequest(r.id, note: answer.note), _t('denied_done', 'Request denied'));
  }

  Future<void> _saveMode() async {
    if (_mode == 'enforce' && _summary?.mode != 'enforce') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_t('enforce_confirm_title', 'Switch to Enforce?')),
          content: Text(_t('enforce_confirm',
              'Hostile addresses will start being blocked (up to an hour each) and risky sign-ins will get a security check.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: Text(_t('cancel', 'Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(_t('enforce', 'Enforce'))),
          ],
        ),
      );
      if (ok != true) return;
    }
    _modeDirty = false;
    await _run(widget.apiService.updateSecuritySettings(mode: _mode, autoRevokeSessions: _autoRevoke),
        _t('settings_saved', 'Security settings saved'));
  }

  // ------------------------------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    if (_loading && _summary == null) {
      return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()));
    }
    final summary = _summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_error != null && summary == null)
          ObsidianGlassCard(child: Text(_error!, style: const TextStyle(color: _red))),
        if (summary != null) ...[
          _modeCard(summary, primary, secondary),
          _timelineCard(summary, primary, secondary),
          _requestsCard(primary, secondary),
          _blocksCard(primary, secondary),
          _offendersCard(summary, primary, secondary),
          _allowlistCard(primary, secondary),
          _protectedCard(primary, secondary),
          _logCard(primary, secondary),
        ],
      ],
    );
  }

  Widget _header(IconData icon, Color color, String title, Color primary, {Widget? trailing, int? badge}) {
    return Row(children: [
      Icon(icon, color: color),
      const SizedBox(width: 8),
      Flexible(child: Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary))),
      if (badge != null && badge > 0) ...[
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(999)),
          child: Text('$badge', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
        ),
      ],
      const Spacer(),
      if (trailing != null) trailing,
    ]);
  }

  Widget _pill(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          border: Border.all(color: color.withValues(alpha: 0.4)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(text, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
      );

  Widget _network(int users) {
    if (users >= 3) return _pill('${_t('shared_network', 'Shared network')} ($users)', _amber);
    if (users > 0) return _pill('$users ${_t('users_signed_in', 'signed in')}', _slate);
    return const SizedBox.shrink();
  }

  Widget _stat(String label, String value, Color primary, Color secondary, {bool alert = false}) => SizedBox(
        width: 140,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 11, color: secondary)),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: alert ? _red : primary)),
        ]),
      );

  Widget _modeCard(SecuritySummary s, Color primary, Color secondary) {
    final high = s.timeline.fold<int>(0, (n, b) => n + b.high);
    final failed = (s.eventsLast24h['AUTH_FAILURE'] ?? 0) + (s.eventsLast24h['AUTH_FAILURE_UNKNOWN_USER'] ?? 0);
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.shield_rounded, _sky, _t('title', 'Intrusion detection'), primary),
        const SizedBox(height: 8),
        Text(
          !s.enabled
              ? _t('disabled', 'Detection is turned off in app-config.json.')
              : s.enforcing
                  ? _t('enforcing_desc',
                      'Enforcing: hostile addresses are blocked (never more than an hour), risky sign-ins get a security check, and targeted accounts are protected.')
                  : _t('observing_desc',
                      'Observing: everything is detected, logged and alerted, but nothing is blocked. Switch to Enforce once the alerts look right.'),
          style: TextStyle(color: secondary, fontSize: 13),
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
          SizedBox(
            width: 260,
            child: DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: InputDecoration(labelText: _t('mode', 'Mode'), isDense: true),
              items: [
                DropdownMenuItem(value: 'observe', child: Text(_t('mode_observe', 'Observe (log and alert only)'))),
                DropdownMenuItem(value: 'enforce', child: Text(_t('mode_enforce', 'Enforce (block, challenge, protect)'))),
              ],
              onChanged: (v) => setState(() {
                _mode = v ?? 'observe';
                _modeDirty = true;
              }),
            ),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            Switch(
              value: _autoRevoke,
              onChanged: (v) => setState(() {
                _autoRevoke = v;
                _modeDirty = true;
              }),
            ),
            Flexible(child: Text(_t('auto_revoke', 'Sign out stolen sessions automatically'), style: TextStyle(color: primary, fontSize: 13))),
          ]),
          FilledButton.tonal(onPressed: _saveMode, child: Text(_t('save', 'Save'))),
        ]),
        const SizedBox(height: 16),
        Wrap(spacing: 16, runSpacing: 12, children: [
          _stat(_t('active_blocks', 'Active blocks'), '${s.activeBlocks}', primary, secondary, alert: s.activeBlocks > 0),
          _stat(_t('pending_requests', 'Unblock requests'), '${s.pendingUnblockRequests}', primary, secondary,
              alert: s.pendingUnblockRequests > 0),
          _stat(_t('protected_accounts', 'Protected accounts'), '${s.protectedAccounts}', primary, secondary,
              alert: s.protectedAccounts > 0),
          _stat(_t('high_events', 'High events (24 h)'), '$high', primary, secondary, alert: high > 0),
          _stat(_t('failed_signins', 'Failed sign-ins (24 h)'), '$failed', primary, secondary),
          _stat(_t('stuffing', 'Credential stuffing'),
              s.credentialStuffingActive ? _t('under_way', 'Under way') : _t('none', 'None'), primary, secondary,
              alert: s.credentialStuffingActive),
          if (s.droppedEvents > 0)
            _stat(_t('dropped', 'Dropped events'), '${s.droppedEvents}', primary, secondary, alert: true),
        ]),
      ]),
    );
  }

  Widget _timelineCard(SecuritySummary s, Color primary, Color secondary) {
    final peak = s.timeline.fold<int>(1, (m, b) => b.total > m ? b.total : m);
    final types = s.eventsLast24h.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.timeline_rounded, _sky, _t('timeline', 'Events in the last 24 hours'), primary),
        const SizedBox(height: 12),
        SizedBox(
          height: 100,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in s.timeline)
                Expanded(
                  child: Tooltip(
                    message: '${DateTime.fromMillisecondsSinceEpoch(b.hourStart).hour}:00  ${b.total}',
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 1),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          for (final (count, color) in [(b.high, _red), (b.medium, _amber), (b.low, _sky), (b.info, _slate)])
                            if (count > 0) Container(height: 100.0 * count / peak, color: color),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final e in types) _pill('${_label(e.key)}: ${e.value}', _slate),
          if (types.isEmpty) Text(_t('no_events', 'No security events in the last 24 hours.'), style: TextStyle(color: secondary)),
        ]),
      ]),
    );
  }

  Widget _requestsCard(Color primary, Color secondary) {
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.pending_actions_rounded, _amber, _t('requests', 'Unblock requests'), primary, badge: _requests.length),
        const SizedBox(height: 8),
        if (_requests.isEmpty) Text(_t('no_requests', 'No requests waiting.'), style: TextStyle(color: secondary)),
        for (final r in _requests)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text(r.name + (r.teamNumber != null ? ' (${_t('team', 'team')} ${r.teamNumber})' : ''),
                    style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                if (r.highRisk) _pill(_t('high_risk', 'High risk'), _red),
                _network(r.recentDistinctUsers),
              ]),
              const SizedBox(height: 2),
              Text('${r.ip}${r.email != null ? ' · ${r.email}' : ''} · ${_time(r.createdAt)}',
                  style: TextStyle(color: secondary, fontSize: 12)),
              const SizedBox(height: 4),
              Text(r.message, style: TextStyle(color: primary, fontSize: 13)),
              if (r.blockReason != null) ...[
                const SizedBox(height: 4),
                Text('${_t('why_blocked', 'Why blocked')}: ${r.blockReason}'
                    '${r.blockExpiresAt != null ? ' (${_left(r.blockExpiresAt!)} ${_t('left', 'left')})' : ''}',
                    style: TextStyle(color: secondary, fontSize: 12)),
              ],
              const SizedBox(height: 6),
              Wrap(spacing: 8, children: [
                FilledButton(onPressed: () => _approve(r), child: Text(_t('approve', 'Approve'))),
                OutlinedButton(onPressed: () => _deny(r), child: Text(_t('deny', 'Deny'))),
              ]),
            ]),
          ),
      ]),
    );
  }

  Widget _blocksCard(Color primary, Color secondary) {
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.block_rounded, _red, _t('blocks', 'Active blocks'), primary,
            trailing: TextButton(onPressed: _blocks.isEmpty ? null : _unblockAll, child: Text(_t('unblock_all', 'Unblock all')))),
        const SizedBox(height: 4),
        Text(_t('blocks_desc', 'No block lasts more than an hour. Lifting one lets the address through on every node within a second.'),
            style: TextStyle(color: secondary, fontSize: 12)),
        const SizedBox(height: 8),
        if (_blocks.isEmpty) Text(_t('no_blocks', 'Nothing is blocked.'), style: TextStyle(color: secondary)),
        for (final b in _blocks)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    Text(b.ipOrCidr, style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                    _pill('${_left(b.expiresAt)} ${_t('left', 'left')}', _red),
                    if (b.pendingRequestId != null) _pill(_t('request_waiting', 'Request waiting'), _amber),
                    _network(b.recentDistinctUsers),
                  ]),
                  const SizedBox(height: 2),
                  Text(b.reason, style: TextStyle(color: secondary, fontSize: 12)),
                  Text('${_t('block_number', 'Block')} #${b.strike} · ${b.hits} ${_t('hits', 'hits')} · ${b.createdBy}',
                      style: TextStyle(color: secondary, fontSize: 11)),
                ]),
              ),
              FilledButton.icon(
                onPressed: () => _liftBlock(b),
                icon: const Icon(Icons.lock_open_rounded, size: 16),
                label: Text(_t('unblock', 'Unblock')),
              ),
            ]),
          ),
        const Divider(height: 24),
        Text(_t('block_address', 'Block an address or range'), style: TextStyle(fontWeight: FontWeight.w600, color: primary)),
        const SizedBox(height: 4),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(
            width: 220,
            child: TextField(
              controller: _blockIp,
              decoration: const InputDecoration(hintText: '203.0.113.7 or 203.0.113.0/24', isDense: true),
            ),
          ),
          SizedBox(
            width: 110,
            child: TextField(
              controller: _blockMinutes,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(labelText: _t('minutes_max', 'Minutes (max 60)'), isDense: true),
            ),
          ),
          SizedBox(
            width: 220,
            child: TextField(controller: _blockReason, decoration: InputDecoration(labelText: _t('reason', 'Reason'), isDense: true)),
          ),
          OutlinedButton(
            onPressed: () async {
              final ip = _blockIp.text.trim();
              if (ip.isEmpty) return;
              final minutes = (int.tryParse(_blockMinutes.text.trim()) ?? 60).clamp(1, 60);
              await _run(widget.apiService.blockAddress(ip, minutes: minutes, reason: _blockReason.text.trim()),
                  '$ip ${_t('blocked_for', 'blocked for')} $minutes min');
              _blockIp.clear();
              _blockReason.clear();
            },
            child: Text(_t('block', 'Block')),
          ),
        ]),
      ]),
    );
  }

  Widget _offendersCard(SecuritySummary s, Color primary, Color secondary) {
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.gpp_maybe_rounded, _amber, _t('offenders', 'Highest threat scores (this node)'), primary),
        const SizedBox(height: 8),
        if (s.topOffenders.isEmpty) Text(_t('no_offenders', 'No address has a notable score right now.'), style: TextStyle(color: secondary)),
        for (final o in s.topOffenders)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(o.ip, style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
            subtitle: Text(
              '${_t('score', 'Score')} ${o.score.toStringAsFixed(1)} · ${o.level}'
              '${o.lastEventAt > 0 ? ' · ${_label(o.lastEventType)} ${_time(o.lastEventAt)}' : ''}',
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            trailing: Wrap(spacing: 4, children: [
              IconButton(
                tooltip: _t('show_events', 'Show events'),
                icon: const Icon(Icons.manage_search_rounded),
                onPressed: () {
                  _logIp.text = o.ip;
                  _searchLog();
                },
              ),
              IconButton(
                tooltip: _t('block', 'Block'),
                icon: const Icon(Icons.block_rounded, color: _red),
                onPressed: () => setState(() => _blockIp.text = o.ip),
              ),
            ]),
          ),
      ]),
    );
  }

  Widget _allowlistCard(Color primary, Color secondary) {
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.verified_user_rounded, _green, _t('allowlist', 'Allowlist (never blocked automatically)'), primary),
        const SizedBox(height: 8),
        if (_allowlist.isEmpty)
          Text(_t('no_allowlist', 'No entries. Add a venue or school network to keep it from being blocked.'), style: TextStyle(color: secondary)),
        for (final e in _allowlist)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(e.ipOrCidr, style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
            subtitle: Text(
              [
                if (e.note.isNotEmpty) e.note,
                e.fromConfig ? 'app-config.json' : e.createdBy,
                e.expiresAt != null ? '${_t('expires', 'expires')} ${_time(e.expiresAt!)}' : _t('never_expires', 'never expires'),
              ].join(' · '),
              style: TextStyle(color: secondary, fontSize: 12),
            ),
            trailing: e.fromConfig
                ? null
                : IconButton(
                    tooltip: _t('remove', 'Remove'),
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => _run(widget.apiService.removeAllowlistEntry(e.id), _t('removed', 'Removed from the allowlist')),
                  ),
          ),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(
            width: 200,
            child: TextField(controller: _allowIp, decoration: const InputDecoration(hintText: '198.51.100.0/24', isDense: true)),
          ),
          SizedBox(
            width: 200,
            child: TextField(controller: _allowNote, decoration: InputDecoration(labelText: _t('note', 'Note'), isDense: true)),
          ),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<int?>(
              initialValue: _allowHours,
              decoration: InputDecoration(labelText: _t('for', 'For'), isDense: true),
              items: [
                DropdownMenuItem(value: 24, child: Text(_t('allow_24h', 'For 24 hours'))),
                DropdownMenuItem(value: 168, child: Text(_t('allow_7d', 'For 7 days'))),
                DropdownMenuItem(value: null, child: Text(_t('allow_permanent', 'Until removed'))),
              ],
              onChanged: (v) => setState(() => _allowHours = v),
            ),
          ),
          OutlinedButton(
            onPressed: () async {
              final ip = _allowIp.text.trim();
              if (ip.isEmpty) return;
              await _run(widget.apiService.addAllowlistEntry(ip, note: _allowNote.text.trim(), expiresInHours: _allowHours),
                  '$ip ${_t('allowlisted', 'allowlisted')}');
              _allowIp.clear();
              _allowNote.clear();
            },
            child: Text(_t('add', 'Add')),
          ),
        ]),
      ]),
    );
  }

  Widget _protectedCard(Color primary, Color secondary) {
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.lock_reset_rounded, _amber, _t('protected', 'Protected accounts'), primary),
        const SizedBox(height: 4),
        Text(_t('protected_desc', 'These accounts need a passkey or a password reset to sign in, after a password spray or many failed sign-ins.'),
            style: TextStyle(color: secondary, fontSize: 12)),
        const SizedBox(height: 8),
        if (_protected.isEmpty) Text(_t('no_protected', 'No accounts are protected.'), style: TextStyle(color: secondary)),
        for (final a in _protected)
          ListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: Text(a.label, style: TextStyle(color: primary, fontWeight: FontWeight.bold)),
            subtitle: Text('${_t('until', 'Until')} ${_time(a.protectedUntil)}', style: TextStyle(color: secondary, fontSize: 12)),
            trailing: TextButton(
              onPressed: () => _run(widget.apiService.clearAccountProtection(a.account),
                  '${a.label} ${_t('can_sign_in', 'can sign in with a password again')}'),
              child: Text(_t('clear', 'Clear')),
            ),
          ),
      ]),
    );
  }

  Widget _logCard(Color primary, Color secondary) {
    Color severityColor(String s) => switch (s) { 'HIGH' => _red, 'MEDIUM' => _amber, 'LOW' => _sky, _ => _slate };
    return ObsidianGlassCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _header(Icons.manage_search_rounded, _sky, _t('log', 'Security log'), primary),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.end, children: [
          SizedBox(width: 150, child: TextField(controller: _logIp, decoration: const InputDecoration(labelText: 'IP', isDense: true))),
          SizedBox(
            width: 150,
            child: TextField(controller: _logUser, decoration: InputDecoration(labelText: _t('user', 'User'), isDense: true)),
          ),
          SizedBox(
            width: 200,
            child: DropdownButtonFormField<String>(
              initialValue: _logType,
              isExpanded: true,
              decoration: InputDecoration(labelText: _t('type', 'Type'), isDense: true),
              items: [
                DropdownMenuItem(value: '', child: Text(_t('any', 'Any'))),
                for (final type in _typeLabels.keys) DropdownMenuItem(value: type, child: Text(_label(type))),
              ],
              onChanged: (v) => setState(() => _logType = v ?? ''),
            ),
          ),
          SizedBox(
            width: 130,
            child: DropdownButtonFormField<String>(
              initialValue: _logSeverity,
              decoration: InputDecoration(labelText: _t('severity', 'Severity'), isDense: true),
              items: [
                DropdownMenuItem(value: '', child: Text(_t('any', 'Any'))),
                for (final s in const ['HIGH', 'MEDIUM', 'LOW', 'INFO']) DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(() => _logSeverity = v ?? ''),
            ),
          ),
          OutlinedButton(onPressed: () => _searchLog(), child: Text(_t('search', 'Search'))),
        ]),
        const SizedBox(height: 8),
        if (_log.isEmpty) Text(_t('no_matching', 'No matching events.'), style: TextStyle(color: secondary)),
        for (final e in _log)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                _pill(_label(e.type), severityColor(e.severity)),
                Text(_time(e.at), style: TextStyle(color: secondary, fontSize: 11)),
                Text(e.ip, style: TextStyle(color: secondary, fontSize: 11)),
                if (e.username != null)
                  Text('${e.username}${e.teamNumber != null ? ' (${e.teamNumber})' : ''}',
                      style: TextStyle(color: primary, fontSize: 12, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 2),
              Text(e.details.isNotEmpty ? e.details : '${e.method} ${e.path}', style: TextStyle(color: secondary, fontSize: 12)),
            ]),
          ),
        if (_log.length < _logTotal)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => _searchLog(append: true),
              child: Text('${_t('load_more', 'Load more')} (${_log.length} / $_logTotal)'),
            ),
          ),
      ]),
    );
  }
}
