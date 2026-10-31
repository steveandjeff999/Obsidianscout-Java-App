import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_nav_search.dart';
import 'obsidian_user_avatar.dart';

class ObsidianDesktopSidebar extends StatefulWidget {
  final ApiService apiService;
  final int currentIndex;
  final Function(int) onSelectScreen;
  final VoidCallback onOpenQrScanner;
  final VoidCallback onLogout;
  /// Opens the account switcher; the profile card is tappable when set.
  final VoidCallback? onOpenAccounts;
  final bool isCollapsed;
  final ValueChanged<bool>? onToggleCollapse;
  /// Bumped by the shell's Ctrl+K shortcut to expand the sidebar and focus its search box.
  final ValueNotifier<int>? searchRequests;

  const ObsidianDesktopSidebar({
    super.key,
    required this.apiService,
    required this.currentIndex,
    required this.onSelectScreen,
    required this.onOpenQrScanner,
    required this.onLogout,
    this.onOpenAccounts,
    this.isCollapsed = false,
    this.onToggleCollapse,
    this.searchRequests,
  });

  @override
  State<ObsidianDesktopSidebar> createState() => _ObsidianDesktopSidebarState();
}

class _ObsidianDesktopSidebarState extends State<ObsidianDesktopSidebar> {
  late bool _collapsed;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  String _query = '';
  int _selectedMatch = 0;
  List<Map<String, dynamic>> _matches = const [];

  @override
  void initState() {
    super.initState();
    _collapsed = widget.isCollapsed;
    widget.searchRequests?.addListener(_focusSearch);
  }

  @override
  void didUpdateWidget(ObsidianDesktopSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchRequests != widget.searchRequests) {
      oldWidget.searchRequests?.removeListener(_focusSearch);
      widget.searchRequests?.addListener(_focusSearch);
    }
  }

  @override
  void dispose() {
    widget.searchRequests?.removeListener(_focusSearch);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Expands the sidebar if needed, then focuses and selects the search box.
  void _focusSearch() {
    if (!mounted) return;
    if (_collapsed) setState(() => _collapsed = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchFocus.requestFocus();
      _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
    });
  }

  void _setQuery(String value) {
    setState(() {
      _query = value;
      _selectedMatch = 0;
    });
  }

  void _moveSelection(int delta) {
    if (_matches.isEmpty) return;
    setState(() => _selectedMatch = (_selectedMatch + delta) % _matches.length);
  }

  void _openItem(Map<String, dynamic> item) {
    if (item['isAction'] == true) {
      final action = item['action'] as VoidCallback?;
      action?.call();
    } else if (item['index'] is int) {
      widget.onSelectScreen(item['index'] as int);
    }
  }

  void _openSelectedMatch() {
    if (_matches.isEmpty) return;
    _openItem(_matches[_selectedMatch.clamp(0, _matches.length - 1)]);
    _searchController.clear();
    _setQuery('');
    _searchFocus.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final sidebarBg = isDark
        ? ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.88)
        : ObsidianUITheme.getSurfaceColor(context).withValues(alpha: 0.95);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final headerTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final sectionLabelColor = ObsidianUITheme.getSecondaryTextColor(context);
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);
    final itemRadius = ObsidianUITheme.getButtonRadius(context, fallback: 10.0).clamp(4.0, 16.0);

    final user = widget.apiService.currentUser;
    final username = user?.username.isNotEmpty == true
        ? user!.username
        : (widget.apiService.savedUsername.isNotEmpty ? widget.apiService.savedUsername : 'Scout Operator');
    final roleLabel = user?.roleDisplayLabel ?? (widget.apiService.currentUserRole == 'SUPERADMIN' ? 'Site Admin' : 'Scout');
    final program = widget.apiService.currentProgram;

    final sections = [
      {
        'titleKey': null,
        'items': [
          {
            'pageId': 'dashboard',
            'index': 0,
            'icon': Icons.dashboard_rounded,
            'labelKey': 'nav.dashboard',
            'subKey': 'subtitle.dashboard',
          },
          {
            'pageId': 'event-info',
            'index': 51,
            'icon': Icons.campaign_outlined,
            'labelKey': 'nav.event_info',
            'subKey': 'event_info.subtitle',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.scouting',
        'items': [
          {
            // Shown only while the team has match predictions on (see ApiService.hasPageAccess).
            'pageId': 'match-predictions',
            'index': 36,
            'icon': Icons.emoji_events_rounded,
            'labelKey': 'nav.match_predictions',
            'subKey': 'subtitle.match_predictions',
          },
          {
            'pageId': 'my-assignments',
            'index': 29,
            'icon': Icons.assignment_ind_rounded,
            'labelKey': 'nav.my_assignments',
            'subKey': 'subtitle.my_assignments',
          },
          {
            'pageId': 'pit-scout',
            'index': 2,
            'icon': Icons.build_circle_rounded,
            'labelKey': 'nav.pit_scout',
            'subKey': 'subtitle.pit_scout',
          },
          {
            'pageId': 'prediction-leaderboard',
            'index': 50,
            'icon': Icons.emoji_events_outlined,
            'labelKey': 'nav.prediction_leaderboard',
            'subKey': 'leaderboard.notice',
          },
          {
            'pageId': 'prescout',
            'index': 11,
            'icon': Icons.history_edu_rounded,
            'labelKey': 'nav.prescout',
            'subKey': 'subtitle.prescout',
          },
          {
            'pageId': 'qr-scanner',
            'isAction': true,
            'action': widget.onOpenQrScanner,
            'icon': Icons.qr_code_scanner_rounded,
            'labelKey': 'scanner.title',
            'subKey': 'scanner.scan_qr',
          },
          {
            'pageId': 'qual-scout',
            'index': 3,
            'icon': Icons.rate_review_rounded,
            'labelKey': 'nav.qual_scout',
            'subKey': 'subtitle.qual_scout',
          },
          {
            'pageId': 'scout',
            'index': 1,
            'icon': Icons.sports_esports_rounded,
            'labelKey': 'nav.match_scout',
            'subKey': 'subtitle.match_scout',
          },
          {
            'pageId': 'scout-history',
            'index': 17,
            'icon': Icons.history_rounded,
            'labelKey': 'nav.scout_history',
            'subKey': 'subtitle.scout_history',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.data',
        'items': [
          {
            'pageId': 'all-data',
            'index': 12,
            'icon': Icons.dataset_rounded,
            'labelKey': 'nav.all-data',
            'subKey': 'subtitle.all-data',
          },
          {
            'pageId': 'analytics',
            'index': 37,
            'icon': Icons.insert_chart_rounded,
            'labelKey': 'nav.analytics',
            'subKey': 'analytics.notice',
          },
          {
            'pageId': 'compare',
            'index': 38,
            'icon': Icons.compare_arrows_rounded,
            'labelKey': 'nav.compare',
            'subKey': 'compare.notice',
          },
          {
            'pageId': 'custom-analytics',
            'index': 18,
            'icon': Icons.auto_graph_rounded,
            'labelKey': 'nav.custom_analytics',
            'subKey': 'subtitle.custom_analytics',
          },
          {
            'pageId': 'data-validation',
            'index': 16,
            'icon': Icons.fact_check_rounded,
            'labelKey': 'nav.data-validation',
            'subKey': 'subtitle.data-validation',
          },
          {
            'pageId': 'graphs',
            'index': 4,
            'icon': Icons.bar_chart_rounded,
            'labelKey': 'nav.graphs',
            'subKey': 'subtitle.graphs',
          },
          {
            'pageId': 'match-data',
            'index': 13,
            'icon': Icons.table_chart_rounded,
            'labelKey': 'nav.match-data',
            'subKey': 'subtitle.match-data',
          },
          {
            'pageId': 'matches',
            'index': 9,
            'icon': Icons.event_note_rounded,
            'labelKey': 'nav.matches',
            'subKey': 'subtitle.matches',
          },
          {
            'pageId': 'pit-data',
            'index': 14,
            'icon': Icons.engineering_rounded,
            'labelKey': 'nav.pit-data',
            'subKey': 'subtitle.pit-data',
          },
          {
            'pageId': 'projected-rankings',
            'index': 39,
            'icon': Icons.trending_up_rounded,
            'labelKey': 'nav.projected_rankings',
            'subKey': 'projected.notice',
          },
          {
            'pageId': 'qual-data',
            'index': 15,
            'icon': Icons.insights_rounded,
            'labelKey': 'nav.qual-data',
            'subKey': 'subtitle.qual-data',
          },
          {
            'pageId': 'qual-rankings',
            'index': 27,
            'icon': Icons.stars_rounded,
            'labelKey': 'nav.qual_rankings',
            'subKey': 'qual_rankings.notice',
          },
          {
            'pageId': 'rankings',
            'index': 26,
            'icon': Icons.leaderboard_rounded,
            'labelKey': 'nav.rankings',
            'subKey': 'rankings.notice',
          },
          {
            'pageId': 'teams',
            'index': 8,
            'icon': Icons.groups_rounded,
            'labelKey': 'nav.teams',
            'subKey': 'subtitle.teams',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.strategy',
        'items': [
          {
            'pageId': 'alliance-selection',
            'index': 7,
            'icon': Icons.stars_rounded,
            'labelKey': 'nav.alliance_selection',
            'subKey': 'subtitle.alliance_selection',
          },
          {
            'pageId': 'alliances',
            'index': 41,
            'icon': Icons.handshake_rounded,
            'labelKey': 'nav.alliances',
            'subKey': 'alliances.create_alliances_with_partner_',
          },
          {
            'pageId': 'event-predictor',
            'index': 21,
            'icon': Icons.leaderboard_rounded,
            'labelKey': 'nav.event_predictor',
            'subKey': 'subtitle.event_predictor',
          },
          {
            'pageId': 'match-planning',
            'index': 31,
            'icon': Icons.draw_rounded,
            'labelKey': 'nav.match_planning',
            'subKey': 'subtitle.match_planning',
          },
          {
            'pageId': 'pick-list',
            'index': 35,
            'icon': Icons.format_list_numbered_rounded,
            'labelKey': 'nav.pick_list',
            'subKey': 'subtitle.pick_list',
          },
          {
            'pageId': 'predictor',
            'index': 20,
            'icon': Icons.auto_awesome_rounded,
            'labelKey': 'nav.predictor',
            'subKey': 'subtitle.predictor',
          },
        ],
      },
      {
        // Shown only when Settings > Non-Scouting Tools is on (see ApiService.hasPageAccess).
        'titleKey': 'sidebar.section.non_scouting',
        'items': [
          {
            'pageId': 'battery-tracker',
            'index': 34,
            'icon': Icons.battery_charging_full_rounded,
            'labelKey': 'nav.battery_tracker',
            'subKey': 'subtitle.battery_tracker',
          },
          {
            'pageId': 'match-checklist',
            'index': 33,
            'icon': Icons.checklist_rounded,
            'labelKey': 'nav.match_checklist',
            'subKey': 'subtitle.match_checklist',
          },
        ],
      },
      {
        'titleKey': 'sidebar.section.admin',
        'items': [
          {
            'pageId': 'admin-settings',
            'index': 10,
            'icon': Icons.tune_rounded,
            'labelKey': 'nav.config_editor',
            'subKey': 'subtitle.config_editor',
          },
          {
            'pageId': 'banners',
            'index': 47,
            'icon': Icons.campaign_rounded,
            'labelKey': 'nav.banners',
            'subKey': 'banners.subtitle',
          },
          {
            'pageId': 'chat',
            'index': 6,
            'icon': Icons.chat_bubble_outline_rounded,
            'labelKey': 'nav.team_chat',
            'subKey': 'subtitle.chat',
          },
          {
            'pageId': 'config-migration',
            'index': 44,
            'icon': Icons.sync_alt_rounded,
            'labelKey': 'nav.config_migration',
            'subKey': 'subtitle.config_migration',
          },
          {
            'pageId': 'contact',
            'index': 19,
            'icon': Icons.contact_support_rounded,
            'labelKey': 'nav.contact',
            'subKey': 'subtitle.contact',
          },
          {
            'pageId': 'backup',
            'index': 49,
            'icon': Icons.import_export_rounded,
            'labelKey': 'nav.backup',
            'subKey': 'subtitle.backup',
          },
          {
            'pageId': 'default-configs',
            'index': 42,
            'icon': Icons.library_books_rounded,
            'labelKey': 'nav.default_configs',
            'subKey': 'subtitle.default_configs',
          },
          {
            'pageId': 'error-reports',
            'index': 24,
            'icon': Icons.bug_report_rounded,
            'labelKey': 'nav.error_reports',
            'subKey': 'subtitle.error_reports',
          },
          {
            'pageId': 'events',
            'index': 25,
            'icon': Icons.event_rounded,
            'labelKey': 'events.title',
            'subKey': 'events.notice',
          },
          {
            'pageId': 'fcm-settings',
            'index': 46,
            'icon': Icons.notifications_active_rounded,
            'labelKey': 'nav.fcm_settings',
            'subKey': 'subtitle.fcm_settings',
          },
          {
            'pageId': 'migration',
            'index': 45,
            'icon': Icons.move_down_rounded,
            'labelKey': 'nav.migration',
            'subKey': 'migration.notice',
          },
          {
            'pageId': 'schema-history',
            'index': 43,
            'icon': Icons.history_edu_rounded,
            'labelKey': 'nav.schema_history',
            'subKey': 'subtitle.schema_history',
          },
          {
            'pageId': 'scout-assignments',
            'index': 30,
            'icon': Icons.assignment_rounded,
            'labelKey': 'nav.scout_assignments',
            'subKey': 'subtitle.scout_assignments',
          },
          {
            'pageId': 'scouter-report',
            'index': 40,
            'icon': Icons.summarize_rounded,
            'labelKey': 'nav.scouter-report',
            'subKey': 'scouter-report.notice',
          },
          {
            'pageId': 'cluster-management',
            'index': 23,
            'icon': Icons.hub_rounded,
            'labelKey': 'nav.cluster_management',
            'subKey': 'subtitle.cluster_management',
          },
          {
            'pageId': 'settings',
            'index': 5,
            'icon': Icons.settings_suggest_rounded,
            'labelKey': 'nav.settings_cache',
            'subKey': 'subtitle.settings',
          },
          {
            'pageId': 'shared-links',
            'index': 32,
            'icon': Icons.share_rounded,
            'labelKey': 'nav.shared_links',
            'subKey': 'subtitle.shared_links',
          },
          {
            'pageId': 'storage-manager',
            'index': 48,
            'icon': Icons.storage_rounded,
            'labelKey': 'nav.storage_manager',
            'subKey': 'subtitle.storage_manager',
          },
          {
            'pageId': 'theme-editor',
            'index': 28,
            'icon': Icons.palette_rounded,
            'labelKey': 'nav.theme_editor',
            'subKey': 'subtitle.theme_editor',
          },
          {
            'pageId': 'users',
            'index': 22,
            'icon': Icons.manage_accounts_rounded,
            'labelKey': 'nav.users',
            'subKey': 'subtitle.users',
          },
        ],
      },
    ];

    final isSearching = !_collapsed && _query.trim().isNotEmpty;
    // Pages the user can open, narrowed by the search box when it has text.
    final visibleSections = sections
        .map((section) => {
              'titleKey': section['titleKey'],
              'items': (section['items'] as List<Map<String, dynamic>>)
                  .where((item) =>
                      widget.apiService.hasPageAccess(item['pageId'] as String) &&
                      (!isSearching || navItemMatchesQuery(context, item, _query)))
                  .toList(),
            })
        .where((section) => (section['items'] as List).isNotEmpty)
        .toList();
    _matches = isSearching
        ? visibleSections.expand((s) => s['items'] as List<Map<String, dynamic>>).toList()
        : const [];
    final highlighted = _matches.isEmpty ? null : _matches[_selectedMatch.clamp(0, _matches.length - 1)];

    final width = _collapsed ? 72.0 : 240.0;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: sidebarBg,
        border: Border(right: BorderSide(color: borderColor, width: 1.0)),
      ),
      child: Column(
        children: [
          // Header: Brand & Collapse Toggle
          Container(
            height: 60.0,
            padding: EdgeInsets.symmetric(horizontal: _collapsed ? 12.0 : 16.0),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Row(
              mainAxisAlignment: _collapsed ? MainAxisAlignment.center : MainAxisAlignment.spaceBetween,
              children: [
                if (!_collapsed)
                  Expanded(
                    child: Row(
                      children: [
                        Image.asset(
                          'assets/images/obsidian-512.png',
                          width: 28.0,
                          height: 28.0,
                          cacheWidth: 56,
                          cacheHeight: 56,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.shield_rounded,
                            color: ObsidianUITheme.primaryAccent,
                            size: 24.0,
                          ),
                        ),
                        const SizedBox(width: 8.0),
                        Expanded(
                          child: Text(
                            program.isNotEmpty ? 'ObsidianScout $program' : 'ObsidianScout',
                            style: TextStyle(
                              fontSize: 14.0,
                              fontWeight: FontWeight.bold,
                              color: headerTextColor,
                              letterSpacing: 0.3,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                IconButton(
                  icon: Icon(
                    _collapsed ? Icons.chevron_right_rounded : Icons.chevron_left_rounded,
                    color: headerTextColor.withValues(alpha: 0.7),
                    size: 20.0,
                  ),
                  tooltip: _collapsed ? 'Expand Sidebar' : 'Collapse Sidebar',
                  onPressed: () => setState(() {
                    _collapsed = !_collapsed;
                    if (_collapsed) {
                      _searchController.clear();
                      _query = '';
                    }
                  }),
                  constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
          ),

          // User Profile Compact Card
          if (!_collapsed)
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Material(
                color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(itemRadius),
                  side: BorderSide(color: borderColor),
                ),
                child: InkWell(
                  onTap: widget.onOpenAccounts,
                  borderRadius: BorderRadius.circular(itemRadius),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14.0, vertical: 10.0),
                    child: Row(
                      children: [
                        ObsidianUserAvatar(
                          profilePicture: user?.profilePicture,
                          username: username,
                          size: 32,
                          serverUrl: widget.apiService.currentServerUrl,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                username,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: headerTextColor,
                                ),
                              ),
                              Text(
                                roleLabel,
                                style: TextStyle(
                                  fontSize: 10.0,
                                  fontWeight: FontWeight.w600,
                                  color: primaryAccent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (widget.onOpenAccounts != null)
                          Icon(Icons.unfold_more_rounded, size: 18.0, color: sectionLabelColor),
                      ],
                    ),
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10.0),
              child: Tooltip(
                message: '$username ($roleLabel)',
                child: ObsidianUserAvatar(
                  profilePicture: user?.profilePicture,
                  username: username,
                  size: 36,
                  serverUrl: widget.apiService.currentServerUrl,
                  onTap: widget.onOpenAccounts,
                ),
              ),
            ),

          if (!_collapsed)
            Padding(
              padding: const EdgeInsets.fromLTRB(8.0, 0.0, 8.0, 4.0),
              child: ObsidianNavSearchField(
                controller: _searchController,
                focusNode: _searchFocus,
                compact: true,
                shortcutHint: 'Ctrl K',
                onChanged: _setQuery,
                onSubmitted: _openSelectedMatch,
                onMoveSelection: _moveSelection,
              ),
            ),

          // Navigation Links
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
              children: [
                if (_collapsed)
                  Tooltip(
                    message: context.tr('sidebar.search.placeholder', 'Search pages...'),
                    preferBelow: false,
                    child: Material(
                      color: Colors.transparent,
                      borderRadius: BorderRadius.circular(itemRadius),
                      child: InkWell(
                        onTap: _focusSearch,
                        borderRadius: BorderRadius.circular(itemRadius),
                        child: SizedBox(
                          height: 40.0,
                          child: Icon(Icons.search_rounded, size: 20.0, color: sectionLabelColor),
                        ),
                      ),
                    ),
                  ),
                if (isSearching && _matches.isEmpty) const ObsidianNavSearchEmpty(),
                ...visibleSections.expand((section) {
                  final visibleItems = section['items'] as List<Map<String, dynamic>>;
                  final titleKey = section['titleKey'] as String?;

                  return [
                    if (titleKey != null && !_collapsed)
                      Padding(
                        padding: const EdgeInsets.only(left: 10.0, top: 12.0, bottom: 4.0),
                        child: Text(
                          context.tr(titleKey).toUpperCase(),
                          style: TextStyle(
                            color: sectionLabelColor,
                            fontSize: 9.5,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 1.0,
                          ),
                        ),
                      )
                    else if (titleKey != null && _collapsed)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6.0),
                        child: Divider(color: borderColor, height: 1),
                      ),
                    ...visibleItems.map((item) {
                      final isAction = item['isAction'] == true;
                      final idx = item['index'] as int?;
                      final isSelected = !isAction && idx == widget.currentIndex;
                      final label = context.tr(item['labelKey'] as String);

                      final unselectedItemColor =
                          isDark ? Colors.white.withValues(alpha: 0.8) : const Color(0xFF334155);
                      final unselectedIconColor = isDark ? Colors.white60 : const Color(0xFF64748B);

                      if (_collapsed) {
                        return Tooltip(
                          message: label,
                          preferBelow: false,
                          child: Container(
                            margin: const EdgeInsets.symmetric(vertical: 2.0),
                            child: Material(
                              color: isSelected
                                  ? primaryAccent.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(itemRadius),
                              child: InkWell(
                                onTap: () {
                                  if (isAction) {
                                    final action = item['action'] as VoidCallback?;
                                    action?.call();
                                  } else if (idx != null) {
                                    widget.onSelectScreen(idx);
                                  }
                                },
                                borderRadius: BorderRadius.circular(itemRadius),
                                child: Container(
                                  height: 40.0,
                                  alignment: Alignment.center,
                                  decoration: isSelected
                                      ? BoxDecoration(
                                          borderRadius: BorderRadius.circular(itemRadius),
                                          border: Border.all(
                                            color: primaryAccent.withValues(alpha: 0.5),
                                            width: 1.0,
                                          ),
                                        )
                                      : null,
                                  child: Icon(
                                    item['icon'] as IconData,
                                    size: 20.0,
                                    color: isSelected ? primaryAccent : unselectedIconColor,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      }

                      final isHighlighted = identical(item, highlighted);
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 1.5),
                        child: Material(
                          color: isSelected
                              ? primaryAccent.withValues(alpha: 0.18)
                              : (isHighlighted ? primaryAccent.withValues(alpha: 0.10) : Colors.transparent),
                          borderRadius: BorderRadius.circular(itemRadius),
                          child: InkWell(
                            onTap: () => _openItem(item),
                            borderRadius: BorderRadius.circular(itemRadius),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 7.0),
                              decoration: isSelected
                                  ? BoxDecoration(
                                      borderRadius: BorderRadius.circular(itemRadius),
                                      border: Border.all(
                                        color: primaryAccent.withValues(alpha: 0.4),
                                        width: 1.0,
                                      ),
                                    )
                                  : null,
                              child: Row(
                                children: [
                                  Icon(
                                    item['icon'] as IconData,
                                    size: 18.0,
                                    color: isSelected ? primaryAccent : unselectedIconColor,
                                  ),
                                  const SizedBox(width: 10.0),
                                  Expanded(
                                    child: Text(
                                      label,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                                        color: isSelected
                                            ? (isDark ? Colors.white : primaryAccent)
                                            : unselectedItemColor,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (isSelected)
                                    Container(
                                      width: 5,
                                      height: 5,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: primaryAccent,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ];
                }),
              ],
            ),
          ),

          // Footer: Quick Theme toggle & Logout
          Container(
            padding: EdgeInsets.symmetric(horizontal: _collapsed ? 6.0 : 10.0, vertical: 8.0),
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: borderColor)),
            ),
            child: _collapsed
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(
                          widget.apiService.themeMode == ThemeMode.light
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          size: 18.0,
                          color: widget.apiService.themeMode == ThemeMode.light
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFFFB703),
                        ),
                        tooltip: widget.apiService.themeMode == ThemeMode.light
                            ? 'Switch to Dark Mode'
                            : 'Switch to Light Mode',
                        onPressed: () {
                          final nextMode = widget.apiService.themeMode == ThemeMode.light
                              ? ThemeMode.dark
                              : ThemeMode.light;
                          widget.apiService.setThemeMode(nextMode);
                        },
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 4.0),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 18.0, color: ObsidianUITheme.errorRed),
                        tooltip: 'Sign Out',
                        onPressed: widget.onLogout,
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(
                          widget.apiService.themeMode == ThemeMode.light
                              ? Icons.dark_mode_rounded
                              : Icons.light_mode_rounded,
                          size: 18.0,
                          color: widget.apiService.themeMode == ThemeMode.light
                              ? const Color(0xFF4F46E5)
                              : const Color(0xFFFFB703),
                        ),
                        tooltip: widget.apiService.themeMode == ThemeMode.light
                            ? 'Switch to Dark Mode'
                            : 'Switch to Light Mode',
                        onPressed: () {
                          final nextMode = widget.apiService.themeMode == ThemeMode.light
                              ? ThemeMode.dark
                              : ThemeMode.light;
                          widget.apiService.setThemeMode(nextMode);
                        },
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                      Expanded(
                        child: Text(
                          'ObsidianScout PC',
                          style: TextStyle(fontSize: 10.5, color: sectionLabelColor),
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.logout_rounded, size: 18.0, color: ObsidianUITheme.errorRed),
                        tooltip: 'Sign Out',
                        onPressed: widget.onLogout,
                        constraints: const BoxConstraints(minWidth: 32.0, minHeight: 32.0),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}
