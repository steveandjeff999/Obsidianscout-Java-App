import 'dart:async';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/security_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

/// Shown when the server blocks this network. Counts down to the automatic lift (never more than an hour), lets the
/// user ask an administrator to lift it sooner, and closes itself once the block is gone.
class IpBlockedScreen extends StatefulWidget {
  final ApiService apiService;
  final IpBlockInfo info;

  const IpBlockedScreen({super.key, required this.apiService, required this.info});

  @override
  State<IpBlockedScreen> createState() => _IpBlockedScreenState();
}

class _IpBlockedScreenState extends State<IpBlockedScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _team = TextEditingController();
  final _email = TextEditingController();
  final _message = TextEditingController();

  Timer? _tick;
  Timer? _poll;
  int? _expiresAt;
  String _ip = '';
  bool _requestsEnabled = true;
  String? _requestId;
  String? _requestStatus;
  String? _reviewNote;
  bool _sending = false;
  String? _error;
  bool _closing = false;

  String _t(String key, String fallback) => context.tr('security.$key', fallback);

  @override
  void initState() {
    super.initState();
    _expiresAt = widget.info.expiresAt;
    _requestsEnabled = widget.info.unblockRequestsEnabled;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {});
      if (_expiresAt != null && DateTime.now().millisecondsSinceEpoch >= _expiresAt!) _refresh();
    });
    _poll = Timer.periodic(const Duration(seconds: 15), (_) => _refresh());
    _refresh();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _poll?.cancel();
    _name.dispose();
    _team.dispose();
    _email.dispose();
    _message.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final status = await widget.apiService.fetchBlockStatus();
    if (!mounted || status == null) return;
    if (!status.blocked) {
      _close();
      return;
    }
    UnblockRequestStatus? request;
    final id = status.pendingRequestId ?? _requestId;
    if (id != null) request = await widget.apiService.fetchUnblockRequestStatus(id);
    if (!mounted) return;
    setState(() {
      _ip = status.ip;
      _expiresAt = status.expiresAt ?? _expiresAt;
      _requestsEnabled = status.unblockRequestsEnabled;
      if (id != null) {
        _requestId = id;
        _requestStatus = request?.status ?? status.pendingRequestStatus ?? _requestStatus;
        _reviewNote = request?.reviewNote ?? _reviewNote;
      }
    });
    if (_requestStatus == 'approved') _close();
  }

  void _close() {
    if (_closing) return;
    _closing = true;
    _tick?.cancel();
    _poll?.cancel();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      final result = await widget.apiService.submitUnblockRequest(
        name: _name.text.trim(),
        teamNumber: int.tryParse(_team.text.trim()),
        email: _email.text.trim(),
        message: _message.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _requestId = result.id;
        _requestStatus = result.status;
        _reviewNote = result.reviewNote;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String _countdown() {
    final left = (_expiresAt ?? 0) - DateTime.now().millisecondsSinceEpoch;
    if (left <= 0) return '00:00';
    final m = left ~/ 60000;
    final s = (left % 60000) ~/ 1000;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return PopScope(
      canPop: _closing,
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ObsidianGlassCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        const Icon(Icons.block_rounded, color: Color(0xFFEF4444), size: 32),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(_t('blocked_title', 'Your network is temporarily blocked'),
                              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: primary)),
                        ),
                      ]),
                      const SizedBox(height: 8),
                      Text(
                        _t('blocked_intro',
                                'ObsidianScout saw unusual activity from your network and paused access. Blocks never last more than an hour and lift on their own.') +
                            (_ip.isNotEmpty ? ' ($_ip)' : ''),
                        style: TextStyle(color: secondary),
                      ),
                      const SizedBox(height: 16),
                      Text(_countdown(),
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.bold, color: primary, fontFeatures: const [FontFeature.tabularFigures()])),
                      Text(_t('until_lifted', 'until the block lifts automatically.'), style: TextStyle(color: secondary)),
                      const SizedBox(height: 20),
                      if (_requestStatus != null)
                        _buildStatus(primary, secondary)
                      else if (_requestsEnabled)
                        _buildForm(primary, secondary),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(_error!, style: const TextStyle(color: Color(0xFFEF4444))),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(Color primary, Color secondary) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(_t('need_sooner', 'Need access sooner?'), style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primary)),
          const SizedBox(height: 4),
          Text(_t('need_sooner_desc', "If you're on a shared network at an event or school, ask an administrator to lift the block."),
              style: TextStyle(color: secondary, fontSize: 13)),
          const SizedBox(height: 12),
          TextFormField(
            controller: _name,
            maxLength: 100,
            decoration: InputDecoration(labelText: _t('your_name', 'Your name')),
            validator: (v) => (v == null || v.trim().isEmpty) ? _t('name_required', 'Please enter your name.') : null,
          ),
          TextFormField(
            controller: _team,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: _t('team_optional', 'Team number (optional)')),
            validator: (v) {
              final text = v?.trim() ?? '';
              if (text.isEmpty) return null;
              final n = int.tryParse(text);
              return (n == null || n < 0 || n > 99999) ? _t('team_invalid', "That team number doesn't look right.") : null;
            },
          ),
          TextFormField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            maxLength: 255,
            decoration: InputDecoration(labelText: _t('email_optional', 'Email for a reply (optional)')),
          ),
          TextFormField(
            controller: _message,
            maxLength: 500,
            minLines: 3,
            maxLines: 6,
            decoration: InputDecoration(labelText: _t('what_doing', 'What were you doing when this happened?')),
            validator: (v) => (v == null || v.trim().isEmpty) ? _t('message_required', 'Please say what you were doing.') : null,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _sending ? null : _submit,
              icon: _sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.lock_open_rounded, size: 18),
              label: Text(_sending ? _t('checking', 'Running a quick security check...') : _t('request_unblock', 'Request unblock')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatus(Color primary, Color secondary) {
    final (IconData icon, Color color, String title, String text) = switch (_requestStatus) {
      'approved' => (Icons.check_circle_rounded, const Color(0xFF10B981), _t('approved', 'Approved'),
          _t('approved_desc', 'Your network has been unblocked.')),
      'denied' => (Icons.cancel_rounded, const Color(0xFFEF4444), _t('denied', 'Not approved'),
          '${_reviewNote != null ? '$_reviewNote ' : ''}${_t('denied_desc', 'The block still lifts on its own when the timer runs out.')}'),
      'expired' => (Icons.schedule_rounded, secondary, _t('expired', 'The block has ended'), ''),
      _ => (Icons.pending_actions_rounded, const Color(0xFFF59E0B), _t('request_sent', 'Request sent'),
          _t('request_sent_desc', 'An administrator will review it. This screen updates on its own.')),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
        color: color.withValues(alpha: 0.08),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontWeight: FontWeight.bold, color: primary)),
                if (text.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(text, style: TextStyle(color: secondary, fontSize: 13)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
