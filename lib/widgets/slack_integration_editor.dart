import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../models/api_response.dart';
import '../models/slack_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_feedback.dart';

/// Admin Settings > Integrations > Slack: connect a workspace, pick channels and mentions, choose who sees the
/// banners, and fix how Slack people map to team members. Same server routes as the web page (admin-slack.js).
class SlackIntegrationEditor extends StatefulWidget {
  final ApiService apiService;

  const SlackIntegrationEditor({super.key, required this.apiService});

  @override
  State<SlackIntegrationEditor> createState() => _SlackIntegrationEditorState();
}

class _SlackIntegrationEditorState extends State<SlackIntegrationEditor> {
  static const _roles = ['ADMIN', 'ANALYTICS', 'CUSTOM', 'SCOUT', 'SUPERADMIN'];
  static const _auto = '__auto__';

  final _botToken = TextEditingController();
  final _appToken = TextEditingController();
  final _search = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _loadError;
  SlackIntegration _integration = const SlackIntegration();
  bool _enabled = false;
  List<SlackChannel> _channels = const [];
  String _channelsError = '';
  List<SlackUserGroup> _groups = const [];
  String _groupsMessage = '';
  List<SlackLinkedMember> _members = const [];
  List<SlackPerson> _slackPeople = const [];
  final Map<String, SlackChannelRule> _rules = {};
  Map<String, String> _userLinks = {};

  ApiService get _api => widget.apiService;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _botToken.dispose();
    _appToken.dispose();
    _search.dispose();
    super.dispose();
  }

  String _tr(String key, String fallback) => context.tr(key, fallback);

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _loadError = null;
    });
    final res = await _api.slackRequest('GET', '/integration');
    if (!mounted) return;
    if (!res.success || res.data is! Map<String, dynamic>) {
      setState(() {
        _loading = false;
        _loadError = res.message ?? 'Could not load Slack settings.';
      });
      return;
    }
    _integration = SlackIntegration.fromJson(res.data as Map<String, dynamic>);
    _enabled = _integration.enabled;
    _rules
      ..clear()
      ..addEntries(_integration.rules.map((r) => MapEntry(r.channelId, r)));
    _userLinks = Map.of(_integration.userLinks);
    _botToken.clear();
    _appToken.clear();
    if (_integration.configured) {
      await Future.wait([_loadChannels(false), _loadGroups(), _loadLinks()]);
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadChannels(bool refresh) async {
    final res = await _api.slackRequest('GET', '/channels${refresh ? '?refresh=true' : ''}');
    if (res.success && res.data is List) {
      _channels = (res.data as List).whereType<Map<String, dynamic>>().map(SlackChannel.fromJson).toList();
      _channelsError = '';
      for (final c in _channels) {
        final rule = _rules[c.id];
        if (rule != null) _rules[c.id] = rule.copyWith(channelName: c.name, isPrivate: c.isPrivate);
      }
    } else {
      _channels = const [];
      _channelsError = res.message ?? 'Could not load channels from Slack.';
    }
  }

  Future<void> _loadGroups() async {
    final res = await _api.slackRequest('GET', '/usergroups');
    final data = res.data;
    if (res.success && data is Map<String, dynamic>) {
      _groups = (data['groups'] as List? ?? const []).whereType<Map<String, dynamic>>().map(SlackUserGroup.fromJson).toList();
      _groupsMessage = data['message']?.toString() ?? '';
    }
  }

  Future<void> _loadLinks() async {
    final res = await _api.slackRequest('GET', '/user-links');
    final data = res.data;
    if (res.success && data is Map<String, dynamic>) {
      _members = (data['users'] as List? ?? const []).whereType<Map<String, dynamic>>().map(SlackLinkedMember.fromJson).toList();
      _slackPeople = (data['slackUsers'] as List? ?? const []).whereType<Map<String, dynamic>>().map(SlackPerson.fromJson).toList();
    }
  }

  // ---------- actions ----------

  Future<void> _save() async {
    final bot = _botToken.text.trim();
    final app = _appToken.text.trim();
    final payload = <String, dynamic>{
      'rules': _rules.values.map((r) => r.toJson()).toList(),
      'userLinks': _userLinks,
      if (bot.isNotEmpty) 'botToken': bot,
      if (app.isNotEmpty) 'appToken': app,
      if (_integration.configured) 'enabled': _enabled else if (bot.isNotEmpty && app.isNotEmpty) 'enabled': true,
    };
    setState(() => _saving = true);
    final res = await _api.slackRequest('PUT', '/integration', body: payload);
    if (!mounted) return;
    setState(() => _saving = false);
    if (res.success) {
      ObsidianFeedback.showSuccess(context, message: _tr('slack.saved', 'Slack settings saved.'));
      await _load();
    } else {
      ObsidianFeedback.showError(context, message: res.message ?? _tr('slack.save_failed', 'Could not save Slack settings.'));
    }
  }

  Future<void> _test() async {
    final res = await _api.slackRequest('POST', '/integration/test', body: {
      'botToken': _botToken.text.trim().isEmpty ? null : _botToken.text.trim(),
      'appToken': _appToken.text.trim().isEmpty ? null : _appToken.text.trim(),
    });
    if (!mounted) return;
    final data = res.data;
    final ok = res.success && data is Map && data['ok'] == true;
    final message = (data is Map ? data['message']?.toString() : null) ?? res.message ?? _tr('slack.test_failed', 'Slack test failed.');
    ok ? ObsidianFeedback.showSuccess(context, message: message) : ObsidianFeedback.showError(context, message: message);
  }

  Future<void> _preview() async {
    final res = await _api.slackRequest('POST', '/preview', body: const {});
    if (!mounted || res.success) return;
    ObsidianFeedback.showError(context, message: res.message ?? _tr('slack.preview_failed', 'Could not send the test banner.'));
  }

  Future<void> _disconnect() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Slack'),
        content: Text(_tr('slack.disconnect_confirm',
            'Disconnect Slack? The tokens and channel choices are deleted. To stop Slack from keeping the app, also uninstall it in Slack.')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_tr('common.cancel', 'Cancel'))),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: Text(_tr('slack.disconnect', 'Disconnect'))),
        ],
      ),
    );
    if (confirmed != true) return;
    final res = await _api.slackRequest('DELETE', '/integration');
    if (!mounted) return;
    if (res.success) {
      ObsidianFeedback.showSuccess(context, message: _tr('slack.disconnected', 'Slack disconnected.'));
      await _load();
    } else {
      ObsidianFeedback.showApiResponse(context, res);
    }
  }

  Future<void> _join(SlackChannel c) async {
    final res = await _api.slackRequest('POST', '/channels/${Uri.encodeComponent(c.id)}/join');
    if (!mounted) return;
    if (res.success) {
      await _loadChannels(true);
      if (mounted) setState(() {});
    } else {
      ObsidianFeedback.showError(context, message: res.message ?? _tr('slack.join_failed', 'Could not join the channel.'));
    }
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));
    }
    if (_loadError != null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(children: [
          Text(_loadError!, style: TextStyle(color: ObsidianUITheme.errorRed)),
          TextButton(onPressed: _load, child: Text(_tr('slack.retry', 'Try again'))),
        ]),
      );
    }
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _card(Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _header(),
            if (_integration.configured && _integration.status == 'error' && _integration.statusDetail.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.warning_amber_rounded, size: 16, color: ObsidianUITheme.errorRed),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_integration.statusDetail, style: TextStyle(color: ObsidianUITheme.errorRed, fontSize: 12))),
                ]),
              )
            else if (_integration.configured && _integration.enabled && _integration.statusDetail.isNotEmpty)
              Padding(padding: const EdgeInsets.only(top: 6), child: Text(_integration.statusDetail, style: TextStyle(color: secondary, fontSize: 12))),
            if (_integration.lastEventAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _tr('slack.last_message', 'Last message received: {t}').replaceAll('{t}', _integration.lastEventAt!.toLocal().toString().split('.').first),
                  style: TextStyle(color: secondary, fontSize: 12),
                ),
              ),
            if (!_integration.configured) _setupSteps(),
            const SizedBox(height: 12),
            _tokenField(_botToken, _tr('slack.bot_token', 'Bot token'), _integration.botTokenSet, 'xoxb-...'),
            const SizedBox(height: 10),
            _tokenField(_appToken, _tr('slack.app_token', 'App-level token'), _integration.appTokenSet, 'xapp-...'),
            if (_integration.configured)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _enabled,
                title: Text(_tr('slack.enabled', 'Show Slack messages as banners'), style: const TextStyle(fontSize: 13)),
                onChanged: (v) => setState(() => _enabled = v),
              ),
          ],
        )),
        if (_integration.configured) ...[
          const SizedBox(height: 12),
          _card(_channelsSection()),
          const SizedBox(height: 12),
          _card(_linksSection()),
        ],
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.save_rounded, size: 16),
            label: Text(_tr('slack.save', 'Save Slack settings')),
          ),
          OutlinedButton(onPressed: _test, child: Text(_tr('slack.test', 'Test connection'))),
          if (_integration.configured) ...[
            OutlinedButton.icon(
              onPressed: _preview,
              icon: const Icon(Icons.notifications_active_outlined, size: 16),
              label: Text(_tr('slack.preview', 'Send me a test banner')),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
              onPressed: _disconnect,
              child: Text(_tr('slack.disconnect', 'Disconnect')),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _card(Widget child) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: ObsidianUITheme.getSurfaceColor(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
        ),
        child: child,
      );

  Widget _header() {
    final (label, color) = switch (_integration) {
      SlackIntegration(configured: false) => (_tr('slack.status_not_connected', 'Not connected'), ObsidianUITheme.getSecondaryTextColor(context)),
      SlackIntegration(enabled: false) => (_tr('slack.status_off', 'Off'), ObsidianUITheme.getSecondaryTextColor(context)),
      SlackIntegration(status: 'connected') => (_tr('slack.status_connected', 'Connected'), ObsidianUITheme.successGreen),
      SlackIntegration(status: 'error') => (_tr('slack.status_error', 'Error'), ObsidianUITheme.errorRed),
      SlackIntegration(status: 'reconnecting') => (_tr('slack.status_reconnecting', 'Reconnecting'), ObsidianUITheme.warningOrange),
      _ => (_tr('slack.status_connecting', 'Connecting...'), ObsidianUITheme.warningOrange),
    };
    return Wrap(
      spacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Icon(Icons.tag_rounded, color: ObsidianUITheme.primaryAccent),
        Text('Slack', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(99), border: Border.all(color: color.withValues(alpha: 0.6))),
          child: Text(label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ),
        if (_integration.workspaceName.isNotEmpty)
          Text(_integration.workspaceName, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 12)),
      ],
    );
  }

  Widget _setupSteps() {
    final style = TextStyle(fontSize: 12.5, height: 1.4, color: ObsidianUITheme.getPrimaryTextColor(context));
    Widget step(String n, String text) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 20, child: Text('$n.', style: style)),
            Expanded(child: Text(text, style: style)),
          ]),
        );
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_tr('slack.setup_intro', 'Your team creates its own small Slack app, so nothing outside your server sees your messages. It takes about two minutes:'), style: style),
        step('1', _tr('slack.setup_step1', 'Create the app in Slack from our template: ')),
        Padding(
          padding: const EdgeInsets.only(left: 20, top: 4),
          child: OutlinedButton.icon(
            onPressed: _integration.manifestUrl.isEmpty
                ? null
                : () => launchUrl(Uri.parse(_integration.manifestUrl), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded, size: 16),
            label: Text(_tr('slack.create_app', 'Create Slack app')),
          ),
        ),
        step('2', _tr('slack.setup_step2', 'Pick your workspace and click Create, then Install App > Install to Workspace. Copy the Bot User OAuth Token (starts with xoxb-).')),
        step('3', _tr('slack.setup_step3', 'Go to Basic Information > App-Level Tokens > Generate Token, add the connections:write scope, and copy the token (starts with xapp-).')),
        step('4', _tr('slack.setup_step4', 'Paste both tokens below and click Save. Then pick the channels to watch.')),
      ]),
    );
  }

  Widget _tokenField(TextEditingController controller, String label, bool isSet, String placeholder) => TextField(
        controller: controller,
        obscureText: true,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: isSet ? _tr('slack.token_saved', 'Saved. Paste a new token to replace it.') : placeholder,
          floatingLabelBehavior: FloatingLabelBehavior.always,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
      );

  Widget _channelsSection() {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final known = {for (final c in _channels) c.id: c};
    for (final r in _rules.values) {
      known.putIfAbsent(r.channelId, () => SlackChannel(id: r.channelId, name: r.channelName.isEmpty ? r.channelId : r.channelName, isPrivate: r.isPrivate));
    }
    final missing = _rules.keys.where((id) => !_channels.any((c) => c.id == id)).toSet();
    final q = _search.text.trim().toLowerCase().replaceFirst('#', '');
    final rows = known.values.where((c) => q.isEmpty || c.name.toLowerCase().contains(q)).toList()
      ..sort((a, b) {
        final watched = (_rules.containsKey(b.id) ? 1 : 0) - (_rules.containsKey(a.id) ? 1 : 0);
        return watched != 0 ? watched : a.name.compareTo(b.name);
      });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(_tr('slack.channels', 'Channels'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        Text(_tr('slack.channels_hint', 'Tick a channel to watch it, then choose which messages notify and who sees them.'),
            style: TextStyle(color: secondary, fontSize: 12)),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: _tr('slack.search_channels', 'Search channels'),
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            tooltip: _tr('slack.refresh', 'Refresh'),
            onPressed: () async {
              await _loadChannels(true);
              if (mounted) setState(() {});
            },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ]),
        if (_channelsError.isNotEmpty)
          Padding(padding: const EdgeInsets.only(top: 6), child: Text(_channelsError, style: TextStyle(color: ObsidianUITheme.errorRed, fontSize: 12))),
        const SizedBox(height: 6),
        if (rows.isEmpty) Text(_tr('slack.no_channels', 'No channels found.'), style: TextStyle(color: secondary, fontSize: 12)),
        for (final c in rows.take(150)) _channelRow(c, missing.contains(c.id)),
      ],
    );
  }

  Widget _channelRow(SlackChannel c, bool missing) {
    final rule = _rules[c.id];
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    Widget? trailing;
    if (missing) {
      trailing = Text(_tr('slack.channel_missing', 'Not found in Slack'), style: TextStyle(color: ObsidianUITheme.errorRed, fontSize: 11));
    } else if (!c.isMember && c.isPrivate) {
      trailing = Tooltip(
        message: _tr('slack.invite_hint', 'In Slack, type /invite @Obsidianscout in this channel'),
        child: Icon(Icons.info_outline_rounded, size: 18, color: ObsidianUITheme.warningOrange),
      );
    } else if (!c.isMember) {
      trailing = TextButton(onPressed: () => _join(c), child: Text(_tr('slack.join', 'Add app to channel'), style: const TextStyle(fontSize: 12)));
    }
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: ObsidianUITheme.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Checkbox(
              value: rule != null,
              onChanged: (v) => setState(() {
                if (v == true) {
                  _rules[c.id] = SlackChannelRule(channelId: c.id, channelName: c.name, isPrivate: c.isPrivate);
                } else {
                  _rules.remove(c.id);
                }
              }),
            ),
            if (c.isPrivate) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(Icons.lock_outline_rounded, size: 14, color: secondary)),
            Expanded(child: Text('#${c.name}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
            if (c.memberCount > 0)
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Text(_tr('slack.members', '{n} members').replaceAll('{n}', '${c.memberCount}'), style: TextStyle(color: secondary, fontSize: 11)),
              ),
            if (trailing != null) trailing,
          ]),
          if (rule != null && !c.isMember && !missing)
            Padding(
              padding: const EdgeInsets.only(left: 12, bottom: 4),
              child: Text(
                c.isPrivate
                    ? _tr('slack.invite_hint', 'In Slack, type /invite @Obsidianscout in this channel')
                    : _tr('slack.not_member_warning', "The app isn't in this channel yet, so it can't see its messages."),
                style: TextStyle(color: ObsidianUITheme.warningOrange, fontSize: 11),
              ),
            ),
          if (rule != null) _ruleEditor(rule, c),
        ],
      ),
    );
  }

  void _update(SlackChannelRule rule) => setState(() => _rules[rule.channelId] = rule);

  Widget _check(String label, bool value, ValueChanged<bool> onChanged) => CheckboxListTile(
        dense: true,
        contentPadding: EdgeInsets.zero,
        controlAffinity: ListTileControlAffinity.leading,
        visualDensity: VisualDensity.compact,
        title: Text(label, style: const TextStyle(fontSize: 13)),
        value: value,
        onChanged: (v) => onChanged(v ?? false),
      );

  Widget _ruleEditor(SlackChannelRule rule, SlackChannel c) {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text(_tr('slack.notify_on', 'Notify on'), style: const TextStyle(fontSize: 13)),
            const SizedBox(width: 10),
            DropdownButton<String>(
              value: rule.trigger,
              isDense: true,
              items: [
                DropdownMenuItem(value: 'MENTIONS', child: Text(_tr('slack.trigger_mentions', 'Only mentions and keywords'), style: const TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'ALL_MESSAGES', child: Text(_tr('slack.trigger_all', 'Every message'), style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => _update(rule.copyWith(trigger: v)),
            ),
          ]),
          if (rule.trigger == 'MENTIONS') ...[
            _check(_tr('slack.mention_channel', '@channel, @here and @everyone'), rule.mentionChannel, (v) => _update(rule.copyWith(mentionChannel: v))),
            Text(_tr('slack.user_groups', 'User groups'), style: const TextStyle(fontSize: 13)),
            if (_groups.isEmpty)
              Text(_groupsMessage.isNotEmpty ? _groupsMessage : _tr('slack.no_groups', 'This workspace has no user groups.'),
                  style: TextStyle(color: secondary, fontSize: 11))
            else
              Wrap(spacing: 6, children: [
                for (final g in _groups)
                  FilterChip(
                    label: Text('@${g.handle}', style: const TextStyle(fontSize: 12)),
                    selected: rule.userGroupIds.contains(g.id),
                    onSelected: (v) {
                      final ids = {...rule.userGroupIds};
                      v ? ids.add(g.id) : ids.remove(g.id);
                      _update(rule.copyWith(userGroupIds: ids.toList()));
                    },
                  ),
              ]),
            const SizedBox(height: 6),
            TextFormField(
              key: ValueKey('kw-${rule.channelId}'),
              initialValue: rule.keywords.join(', '),
              decoration: InputDecoration(
                labelText: _tr('slack.keywords', 'Keywords (comma separated)'),
                hintText: _tr('slack.keywords_placeholder', 'queue, drive team'),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              onChanged: (v) => _rules[rule.channelId] = _rules[rule.channelId]!.copyWith(
                keywords: v.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList(),
              ),
            ),
          ],
          _check(_tr('slack.mention_linked', 'A direct @mention notifies that person'), rule.mentionLinkedUsers, (v) => _update(rule.copyWith(mentionLinkedUsers: v))),
          _check(_tr('slack.thread_replies', 'Include thread replies'), rule.includeThreadReplies, (v) => _update(rule.copyWith(includeThreadReplies: v))),
          _audienceEditor(rule, c),
          _check(_tr('slack.push', 'Also send a push notification to phones and browsers'), rule.push, (v) => _update(rule.copyWith(push: v))),
        ],
      ),
    );
  }

  Widget _audienceEditor(SlackChannelRule rule, SlackChannel c) {
    final a = rule.audience;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Text(_tr('slack.who_sees', 'Who sees it'), style: const TextStyle(fontSize: 13)),
          const SizedBox(width: 10),
          Flexible(
            child: DropdownButton<bool>(
              value: a.everyone,
              isDense: true,
              isExpanded: true,
              items: [
                DropdownMenuItem(value: true, child: Text(_tr('slack.audience_everyone', 'Everyone on the team'), style: const TextStyle(fontSize: 13))),
                DropdownMenuItem(value: false, child: Text(_tr('slack.audience_some', 'Only selected roles and people'), style: const TextStyle(fontSize: 13))),
              ],
              onChanged: (v) => _update(rule.copyWith(audience: a.copyWith(everyone: v))),
            ),
          ),
        ]),
        if (a.everyone && c.isPrivate)
          Text(_tr('slack.private_everyone_warning', 'This is a private Slack channel. Everyone on your team will see its messages.'),
              style: TextStyle(color: ObsidianUITheme.warningOrange, fontSize: 11)),
        if (!a.everyone) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 4, children: [
            for (final role in _roles)
              FilterChip(
                label: Text(role[0] + role.substring(1).toLowerCase(), style: const TextStyle(fontSize: 12)),
                selected: a.roles.contains(role),
                onSelected: (v) {
                  final roles = {...a.roles};
                  v ? roles.add(role) : roles.remove(role);
                  _update(rule.copyWith(audience: a.copyWith(roles: roles.toList())));
                },
              ),
          ]),
          if (_members.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(spacing: 6, runSpacing: 4, children: [
              for (final m in _members)
                FilterChip(
                  avatar: const Icon(Icons.person_outline, size: 14),
                  label: Text(m.username, style: const TextStyle(fontSize: 12)),
                  selected: a.userIds.contains(m.userId),
                  onSelected: (v) {
                    final ids = {...a.userIds};
                    v ? ids.add(m.userId) : ids.remove(m.userId);
                    _update(rule.copyWith(audience: a.copyWith(userIds: ids.toList())));
                  },
                ),
            ]),
          ],
        ],
      ],
    );
  }

  Widget _linksSection() {
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final names = {for (final p in _slackPeople) p.id: p.label};
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        title: Text(_tr('slack.people_links', 'Slack accounts of team members'), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        subtitle: Text(
          _tr('slack.links_hint', "Members are matched to Slack by email. Linked members get banners when they are @mentioned directly. Change a match here if it's wrong."),
          style: TextStyle(color: secondary, fontSize: 11),
        ),
        children: [
          if (_members.isEmpty) Text(_tr('slack.no_members', 'No team members found.'), style: TextStyle(color: secondary, fontSize: 12)),
          for (final m in _members)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                SizedBox(width: 120, child: Text(m.username, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13), overflow: TextOverflow.ellipsis)),
                Expanded(
                  child: DropdownButton<String>(
                    isExpanded: true,
                    isDense: true,
                    value: _userLinks.containsKey(m.userId) && (_userLinks[m.userId]!.isEmpty || names.containsKey(_userLinks[m.userId]))
                        ? _userLinks[m.userId]
                        : _auto,
                    items: [
                      DropdownMenuItem(
                        value: _auto,
                        child: Text(
                          m.autoSlackUserId.isNotEmpty
                              ? _tr('slack.link_auto_match', 'Match by email: {name}').replaceAll('{name}', names[m.autoSlackUserId] ?? m.autoSlackUserId)
                              : _tr('slack.link_auto_none', 'Match by email (no match)'),
                          style: const TextStyle(fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(value: '', child: Text(_tr('slack.link_none', "Don't link"), style: const TextStyle(fontSize: 12))),
                      for (final p in _slackPeople)
                        DropdownMenuItem(value: p.id, child: Text(p.label, style: const TextStyle(fontSize: 12), overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() {
                      if (v == null || v == _auto) {
                        _userLinks.remove(m.userId);
                      } else {
                        _userLinks[m.userId] = v;
                      }
                    }),
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// Lets the personal settings screen offer the same three choices as the web.
class SlackPreferenceTile extends StatefulWidget {
  final ApiService apiService;

  const SlackPreferenceTile({super.key, required this.apiService});

  @override
  State<SlackPreferenceTile> createState() => _SlackPreferenceTileState();
}

class _SlackPreferenceTileState extends State<SlackPreferenceTile> {
  String _value = 'all';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    widget.apiService.slackRequest('GET', '/me/preference').then((res) {
      if (!mounted) return;
      final data = res.data;
      setState(() {
        if (data is Map && data['preference'] is String) _value = data['preference'] as String;
        _loaded = true;
      });
    });
  }

  Future<void> _set(String value) async {
    final previous = _value;
    setState(() => _value = value);
    final ApiResponse res = await widget.apiService.slackRequest('PUT', '/me/preference', body: {'preference': value});
    if (!mounted) return;
    if (res.success) {
      ObsidianFeedback.showSuccess(context, message: context.tr('slack.pref_saved', 'Slack banner preference updated'));
    } else {
      setState(() => _value = previous);
      ObsidianFeedback.showApiResponse(context, res);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('slack.personal_pref', 'Slack banners'),
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: ObsidianUITheme.getPrimaryTextColor(context)),
              ),
              const SizedBox(height: 2),
              Text(
                context.tr('slack.personal_pref_desc', 'Popups for messages from the Slack channels your admins picked.'),
                style: TextStyle(fontSize: 12, color: ObsidianUITheme.getSecondaryTextColor(context)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        DropdownButton<String>(
          value: _value,
          onChanged: _loaded ? (v) => v == null ? null : _set(v) : null,
          items: [
            DropdownMenuItem(value: 'all', child: Text(context.tr('slack.pref_all', 'All from watched channels'))),
            DropdownMenuItem(value: 'mentions', child: Text(context.tr('slack.pref_mentions', "Only when I'm mentioned"))),
            DropdownMenuItem(value: 'none', child: Text(context.tr('slack.pref_none', 'Off'))),
          ],
        ),
      ],
    );
  }
}
