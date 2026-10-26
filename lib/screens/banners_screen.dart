import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Alerts pinned across the top of the app and website (admins; superadmins can target any team or everyone).
/// Same data as the website's banners.html.
class BannersScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const BannersScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<BannersScreen> createState() => _BannersScreenState();
}

const _bannerColors = {
  'info': Color(0xFF3B82F6),
  'warning': Color(0xFFF59E0B),
  'success': Color(0xFF10B981),
  'danger': Color(0xFFEF4444),
};

class _BannersScreenState extends State<BannersScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _banners = [];

  @override
  void initState() {
    super.initState();
    if (widget.apiService.isAdmin) _load();
  }

  @override
  void didUpdateWidget(covariant BannersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible && widget.apiService.isAdmin) _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final res = await widget.apiService.requestJson('GET', '/api/admin/banners');
    if (!mounted) return;
    if (!res.success) {
      ObsidianFeedback.showError(context, message: '${context.tr('banners.err_load', 'Failed to load banners list: ')}${res.message ?? ''}');
    }
    setState(() {
      _banners = res.success ? jsonMaps(res.data) : [];
      _loading = false;
    });
  }

  Future<void> _edit(Map<String, dynamic>? banner) async {
    final body = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => _BannerDialog(
        banner: banner,
        myTeam: widget.apiService.currentUser?.teamNumber ?? 0,
        isSuper: widget.apiService.currentUserRole.toUpperCase() == 'SUPERADMIN',
      ),
    );
    if (body == null || !mounted) return;
    final res = banner == null
        ? await widget.apiService.requestJson('POST', '/api/admin/banners', body: body)
        : await widget.apiService.requestJson('PUT', '/api/admin/banners/${banner['id']}', body: body);
    if (!mounted) return;
    final ok = reportResult(context, res,
        action: banner == null ? context.tr('banners.btn_create', 'Create Banner') : context.tr('banners.btn_edit', 'Edit'),
        success: banner == null
            ? context.tr('banners.toast_created', 'Banner created successfully!')
            : context.tr('banners.toast_updated', 'Banner updated successfully!'));
    if (ok) _load();
  }

  Future<void> _delete(Map<String, dynamic> banner) async {
    final ok = await confirmPortedAction(context,
        title: context.tr('banners.btn_delete', 'Delete'),
        message: context.tr('banners.confirm_delete', 'Are you sure you want to delete this banner?'),
        destructive: true);
    if (!ok || !mounted) return;
    final res = await widget.apiService.requestJson('DELETE', '/api/admin/banners/${banner['id']}');
    if (!mounted) return;
    if (reportResult(context, res,
        action: context.tr('banners.btn_delete', 'Delete'), success: context.tr('banners.toast_deleted', 'Banner deleted successfully!'))) {
      _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.apiService.isAdmin) {
      return PortedLocked(
        title: context.tr('config.admin_only', 'Admin only'),
        message: context.tr('banners.admin_locked_msg', 'You need admin or superadmin access to manage banners.'),
      );
    }
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.tr('banners.title', 'Banner Management'),
          subtitle: context.tr('banners.subtitle', 'Create and manage alerts that are pinned across the top of the application layout.'),
          actions: [
            FilledButton.icon(
              onPressed: () => _edit(null),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(context.tr('banners.btn_create', 'Create Banner')),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Text(context.tr('banners.current_banners', 'Current Banners'),
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: ObsidianUITheme.getPrimaryTextColor(context))),
        ),
        if (_loading)
          const PortedLoading()
        else if (_banners.isEmpty)
          PortedNotice(context.tr('banners.no_banners', 'No banners created yet.'))
        else
          for (final b in _banners) _buildBanner(context, b),
      ],
    );
  }

  Widget _buildBanner(BuildContext context, Map<String, dynamic> b) {
    final type = jsonStr(b['bannerType'], 'info');
    final color = _bannerColors[type] ?? _bannerColors['info']!;
    final typeLabel = {
          'info': context.tr('banners.type_info', 'Info'),
          'warning': context.tr('banners.type_warning', 'Warning'),
          'success': context.tr('banners.type_success', 'Success'),
          'danger': context.tr('banners.type_danger', 'Danger'),
        }[type] ??
        type;
    final team = jsonInt(b['teamNumber']) ?? 0;
    final props = [
      if (!jsonBool(b['isDismissible'])) context.tr('banners.prop_immutable', 'Immutable'),
      if (jsonBool(b['isExpandable'])) context.tr('banners.prop_expandable', 'Expandable'),
      if (jsonBool(b['showOnLogin'])) context.tr('banners.prop_show_on_login', 'Login Page'),
    ];
    final active = jsonBool(b['isActive']);
    return ObsidianGlassCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 5, horizontal: 16),
      child: Container(
        padding: const EdgeInsets.only(left: 10),
        decoration: BoxDecoration(border: Border(left: BorderSide(color: color, width: 3))),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(jsonStr(b['message']),
                style: TextStyle(fontWeight: FontWeight.w700, color: ObsidianUITheme.getPrimaryTextColor(context))),
            if (jsonBool(b['isExpandable']) && jsonStr(b['expandableMessage']).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(jsonStr(b['expandableMessage']),
                  style: TextStyle(fontSize: 12.5, color: ObsidianUITheme.getSecondaryTextColor(context))),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 4, children: [
              PortedBadge(typeLabel, color: color),
              PortedBadge(team == 0
                  ? context.tr('banners.scope_global', 'Global')
                  : '${context.tr('banners.scope_team', 'Team')} $team'),
              PortedBadge(props.isEmpty ? context.tr('banners.prop_standard', 'Standard') : props.join(', '),
                  color: ObsidianUITheme.getSecondaryTextColor(context)),
              PortedBadge(
                active ? context.tr('banners.status_active', 'Active') : context.tr('banners.status_inactive', 'Inactive'),
                color: active ? ObsidianUITheme.successGreen : ObsidianUITheme.getSecondaryTextColor(context),
              ),
            ]),
            Wrap(spacing: 4, children: [
              TextButton(onPressed: () => _edit(b), child: Text(context.tr('banners.btn_edit', 'Edit'))),
              TextButton(
                onPressed: () => _delete(b),
                style: TextButton.styleFrom(foregroundColor: ObsidianUITheme.errorRed),
                child: Text(context.tr('banners.btn_delete', 'Delete')),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

class _BannerDialog extends StatefulWidget {
  final Map<String, dynamic>? banner;
  final int myTeam;
  final bool isSuper;
  const _BannerDialog({this.banner, required this.myTeam, required this.isSuper});

  @override
  State<_BannerDialog> createState() => _BannerDialogState();
}

class _BannerDialogState extends State<_BannerDialog> {
  late final _message = TextEditingController(text: jsonStr(widget.banner?['message']));
  late final _expandMessage = TextEditingController(text: jsonStr(widget.banner?['expandableMessage']));
  late final _teamNumber = TextEditingController();
  late String _type = jsonStr(widget.banner?['bannerType'], 'info');
  late String _audience;
  late bool _immutable = widget.banner != null && !jsonBool(widget.banner!['isDismissible']);
  late bool _expandable = jsonBool(widget.banner?['isExpandable']);
  late bool _showOnLogin = jsonBool(widget.banner?['showOnLogin']);
  late bool _active = widget.banner == null || jsonBool(widget.banner!['isActive']);
  String? _error;

  @override
  void initState() {
    super.initState();
    final team = jsonInt(widget.banner?['teamNumber']);
    if (team == 0) {
      _audience = 'global';
    } else if (team == null || team == widget.myTeam) {
      _audience = 'team';
    } else {
      _audience = 'custom';
      _teamNumber.text = '$team';
    }
  }

  @override
  void dispose() {
    _message.dispose();
    _expandMessage.dispose();
    _teamNumber.dispose();
    super.dispose();
  }

  void _submit() {
    if (_message.text.trim().isEmpty) {
      setState(() => _error = 'Required');
      return;
    }
    int team = widget.myTeam;
    if (_audience == 'global') team = 0;
    if (_audience == 'custom') {
      final n = int.tryParse(_teamNumber.text.trim());
      if (n == null || n < 1) {
        ObsidianFeedback.showError(context,
            message: context.tr('banners.err_invalid_custom_team', 'Please enter a valid team number for the custom target scope.'));
        return;
      }
      team = n;
    }
    Navigator.pop(context, {
      'message': _message.text,
      'bannerType': _type,
      'teamNumber': team,
      'isDismissible': !_immutable,
      'isExpandable': _expandable,
      'expandableMessage': _expandable ? _expandMessage.text : '',
      'showOnLogin': _showOnLogin,
      'isActive': _active,
    });
  }

  @override
  Widget build(BuildContext context) {
    final surface = ObsidianUITheme.getSurfaceColor(context);
    return AlertDialog(
      backgroundColor: surface,
      title: Text(widget.banner == null
          ? context.tr('banners.btn_create', 'Create Banner')
          : context.tr('banners.btn_edit', 'Edit')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _message,
              autofocus: true,
              decoration: InputDecoration(
                labelText: context.tr('banners.message', 'Banner Message'),
                hintText: context.tr('banners.placeholder_message', 'Enter banner headline...'),
                errorText: _error,
              ),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _type,
              dropdownColor: surface,
              decoration: InputDecoration(labelText: context.tr('banners.style_type', 'Style Color / Type'), isDense: true),
              items: [
                DropdownMenuItem(value: 'info', child: Text(context.tr('banners.type_info', 'Info (Blue)'))),
                DropdownMenuItem(value: 'warning', child: Text(context.tr('banners.type_warning', 'Warning (Amber)'))),
                DropdownMenuItem(value: 'success', child: Text(context.tr('banners.type_success', 'Success (Green)'))),
                DropdownMenuItem(value: 'danger', child: Text(context.tr('banners.type_danger', 'Danger (Red)'))),
              ],
              onChanged: (v) => setState(() => _type = v ?? 'info'),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _audience,
              dropdownColor: surface,
              decoration: InputDecoration(labelText: context.tr('banners.target_audience', 'Target Audience'), isDense: true),
              items: [
                DropdownMenuItem(value: 'team', child: Text(context.tr('banners.audience_my_team', 'My Team'))),
                if (widget.isSuper || _audience == 'global')
                  DropdownMenuItem(value: 'global', child: Text(context.tr('banners.audience_global', 'Global (Sitewide)'))),
                if (widget.isSuper || _audience == 'custom')
                  DropdownMenuItem(value: 'custom', child: Text(context.tr('banners.audience_custom', 'Custom Team'))),
              ],
              onChanged: (v) => setState(() => _audience = v ?? 'team'),
            ),
            if (_audience == 'custom')
              TextField(
                controller: _teamNumber,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: context.tr('banners.target_team_num', 'Target Team Number'),
                  hintText: context.tr('banners.placeholder_team_num', 'e.g. 254'),
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _immutable,
              title: Text(context.tr('banners.immutable', 'Immutable (cannot be closed or hidden by users)')),
              onChanged: (v) => setState(() => _immutable = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _expandable,
              title: Text(context.tr('banners.expandable', 'Expandable (supports detailed dropdown content)')),
              onChanged: (v) => setState(() => _expandable = v ?? false),
            ),
            if (_expandable)
              TextField(
                controller: _expandMessage,
                minLines: 2,
                maxLines: 5,
                decoration: InputDecoration(
                  labelText: context.tr('banners.expandable_message', 'Expanded Dropdown Content'),
                  hintText: context.tr('banners.placeholder_expandable', 'Provide extra instructions or information...'),
                ),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _showOnLogin,
              title: Text(context.tr('banners.show_on_login', 'Show on login page')),
              onChanged: (v) => setState(() => _showOnLogin = v ?? false),
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              title: Text(context.tr('banners.active', 'Active')),
              onChanged: (v) => setState(() => _active = v ?? true),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel', 'Cancel'))),
        FilledButton(onPressed: _submit, child: Text(context.tr('common.save', 'Save'))),
      ],
    );
  }
}
