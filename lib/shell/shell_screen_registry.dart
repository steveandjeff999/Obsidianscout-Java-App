import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';

import '../screens/dashboard_screen.dart';
import '../screens/match_scout_screen.dart';
import '../screens/pit_scout_screen.dart';
import '../screens/qual_scout_screen.dart';
import '../screens/graphs_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/chat_screen.dart';
import '../screens/alliance_selection_screen.dart';
import '../screens/teams_list_screen.dart';
import '../screens/match_list_screen.dart';
import '../screens/config_editor_screen.dart';
import '../screens/prescout_screen.dart';
import '../screens/all_data_screen.dart';
import '../screens/match_data_screen.dart';
import '../screens/pit_data_screen.dart';
import '../screens/qual_data_screen.dart';
import '../screens/data_validation_screen.dart';
import '../screens/scout_history_screen.dart';
import '../screens/custom_analytics_screen.dart';
import '../screens/contact_screen.dart';
import '../screens/predictor_screen.dart';
import '../screens/event_predictor_screen.dart';
import '../screens/users_screen.dart';
import '../screens/cluster_management_screen.dart';
import '../screens/error_reports_screen.dart';
import '../screens/events_screen.dart';
import '../screens/rankings_screen.dart';
import '../screens/qual_rankings_screen.dart';
import '../screens/theme_editor_screen.dart';
import '../screens/my_assignments_screen.dart';
import '../screens/scout_assignments_screen.dart';
import '../screens/match_planning_screen.dart';
import '../screens/match_checklist_screen.dart';
import '../screens/battery_tracker_screen.dart';
import '../screens/team_shared_links_screen.dart';

class MatchScoutParams {
  final String? matchKey;
  final int? matchNumber;
  final int? targetTeamNumber;
  final String? sourceAssignmentId;

  const MatchScoutParams({
    this.matchKey,
    this.matchNumber,
    this.targetTeamNumber,
    this.sourceAssignmentId,
  });
}

class PitScoutParams {
  final int? targetTeamNumber;
  final String? sourceAssignmentId;

  const PitScoutParams({
    this.targetTeamNumber,
    this.sourceAssignmentId,
  });
}

class QualScoutParams {
  final String? matchKey;
  final int? matchNumber;
  final String? allianceColor;
  final int? targetTeamNumber;
  final String? sourceAssignmentId;

  const QualScoutParams({
    this.matchKey,
    this.matchNumber,
    this.allianceColor,
    this.targetTeamNumber,
    this.sourceAssignmentId,
  });
}

/// Registry providing screen definitions, titles, icons, page IDs, and widget builders for the shell.
class ShellScreenRegistry {
  ShellScreenRegistry._();

  /// Total number of shell screens (indices 0 to [screenCount] - 1).
  static const int screenCount = 35;

  static const List<String> titleKeys = [
    'nav.dashboard',
    'nav.match_scout',
    'nav.pit_scout',
    'nav.qual_scout',
    'nav.graphs',
    'nav.settings_cache',
    'nav.team_chat',
    'nav.alliance_selection',
    'nav.teams',
    'nav.matches',
    'nav.config_editor',
    'nav.prescout',
    'nav.all_data',
    'nav.match_data',
    'nav.pit_data',
    'nav.qual_data',
    'nav.data_validation',
    'nav.scout_history',
    'nav.custom_analytics',
    'nav.contact',
    'nav.predictor',
    'nav.event_predictor',
    'nav.users',
    'nav.cluster_management',
    'nav.error_reports',
    'events.title',
    'rankings.title',
    'qual_rankings.title',
    'nav.theme_editor',
    'nav.my_assignments',
    'nav.scout_assignments',
    'nav.match_planning',
    'nav.shared_links',
    'nav.match_checklist',
    'nav.battery_tracker',
  ];

  static const List<String> subtitleKeys = [
    'subtitle.dashboard',
    'subtitle.match_scout',
    'subtitle.pit_scout',
    'subtitle.qual_scout',
    'subtitle.graphs',
    'subtitle.settings',
    'subtitle.chat',
    'subtitle.alliance_selection',
    'subtitle.teams',
    'subtitle.matches',
    'subtitle.config_editor',
    'subtitle.prescout',
    'subtitle.all_data',
    'subtitle.match_data',
    'subtitle.pit_data',
    'subtitle.qual_data',
    'subtitle.data_validation',
    'subtitle.scout_history',
    'subtitle.custom_analytics',
    'subtitle.contact',
    'subtitle.predictor',
    'subtitle.event_predictor',
    'subtitle.users',
    'subtitle.cluster_management',
    'subtitle.error_reports',
    'events.notice',
    'rankings.notice',
    'qual_rankings.notice',
    'subtitle.theme_editor',
    'subtitle.my_assignments',
    'subtitle.scout_assignments',
    'subtitle.match_planning',
    'subtitle.shared_links',
    'subtitle.match_checklist',
    'subtitle.battery_tracker',
  ];

  static String getTitleKey(int index) {
    if (index >= 0 && index < titleKeys.length) {
      return titleKeys[index];
    }
    return 'nav.dashboard';
  }

  static String getSubtitleKey(int index) {
    if (index >= 0 && index < subtitleKeys.length) {
      return subtitleKeys[index];
    }
    return 'subtitle.dashboard';
  }

  static String getPageIdForIndex(int index) {
    switch (index) {
      case 0:
        return 'dashboard';
      case 1:
        return 'scout';
      case 2:
        return 'pit-scout';
      case 3:
        return 'qual-scout';
      case 4:
        return 'graphs';
      case 5:
        return 'settings';
      case 6:
        return 'chat';
      case 7:
        return 'alliance-selection';
      case 8:
        return 'teams';
      case 9:
        return 'matches';
      case 10:
        return 'admin-settings';
      case 11:
        return 'prescout';
      case 12:
        return 'all-data';
      case 13:
        return 'match-data';
      case 14:
        return 'pit-data';
      case 15:
        return 'qual-data';
      case 16:
        return 'data-validation';
      case 17:
        return 'scout-history';
      case 18:
        return 'custom-analytics';
      case 19:
        return 'contact';
      case 20:
        return 'predictor';
      case 21:
        return 'event-predictor';
      case 22:
        return 'users';
      case 23:
        return 'cluster-management';
      case 24:
        return 'error-reports';
      case 25:
        return 'events';
      case 26:
        return 'rankings';
      case 27:
        return 'qual-rankings';
      case 28:
        return 'theme-editor';
      case 29:
        return 'my-assignments';
      case 30:
        return 'scout-assignments';
      case 31:
        return 'match-planning';
      case 32:
        return 'shared-links';
      case 33:
        return 'match-checklist';
      case 34:
        return 'battery-tracker';
      default:
        return 'dashboard';
    }
  }

  static IconData getScreenIcon(int index) {
    switch (index) {
      case 0:
        return Icons.dashboard_rounded;
      case 1:
        return Icons.sports_esports_rounded;
      case 2:
        return Icons.build_circle_rounded;
      case 3:
        return Icons.rate_review_rounded;
      case 4:
        return Icons.bar_chart_rounded;
      case 5:
        return Icons.settings_suggest_rounded;
      case 6:
        return Icons.chat_bubble_outline_rounded;
      case 7:
        return Icons.stars_rounded;
      case 8:
        return Icons.groups_rounded;
      case 9:
        return Icons.event_note_rounded;
      case 10:
        return Icons.tune_rounded;
      case 11:
        return Icons.history_edu_rounded;
      case 12:
        return Icons.dataset_rounded;
      case 13:
        return Icons.table_chart_rounded;
      case 14:
        return Icons.engineering_rounded;
      case 15:
        return Icons.insights_rounded;
      case 16:
        return Icons.fact_check_rounded;
      case 17:
        return Icons.history_rounded;
      case 18:
        return Icons.auto_graph_rounded;
      case 19:
        return Icons.contact_support_rounded;
      case 20:
        return Icons.auto_awesome_rounded;
      case 21:
        return Icons.leaderboard_rounded;
      case 22:
        return Icons.manage_accounts_rounded;
      case 23:
        return Icons.hub_rounded;
      case 24:
        return Icons.bug_report_rounded;
      case 25:
        return Icons.event_rounded;
      case 26:
        return Icons.leaderboard_rounded;
      case 27:
        return Icons.stars_rounded;
      case 28:
        return Icons.palette_rounded;
      case 29:
        return Icons.assignment_ind_rounded;
      case 30:
        return Icons.assignment_rounded;
      case 31:
        return Icons.draw_rounded;
      case 32:
        return Icons.share_rounded;
      case 33:
        return Icons.checklist_rounded;
      case 34:
        return Icons.battery_charging_full_rounded;
      default:
        return Icons.dashboard_rounded;
    }
  }

  static String getScreenDisplayName(BuildContext context, int index) {
    switch (index) {
      case 0:
        return context.tr('nav.dashboard', 'Dashboard');
      case 1:
        return context.tr('nav.scout', context.tr('nav.match_scout', 'Match Scout'));
      case 2:
        return context.tr('nav.pit-scout', context.tr('nav.pit_scout', 'Pit Scout'));
      case 3:
        return context.tr('nav.qual-scout', context.tr('nav.qual_scout', 'Qual Scout'));
      case 4:
        return context.tr('nav.graphs', 'Graphs');
      case 5:
        return context.tr('nav.settings', context.tr('nav.settings_cache', 'Settings'));
      case 6:
        return context.tr('nav.team_chat', context.tr('nav.chat', 'Team Chat'));
      case 7:
        return context.tr('nav.alliance-selection', context.tr('nav.alliance_selection', 'Alliance Selection'));
      case 8:
        return context.tr('nav.teams', 'Teams');
      case 9:
        return context.tr('nav.matches', 'Matches');
      case 10:
        return context.tr('nav.config_editor', 'Config Editor');
      case 11:
        return context.tr('nav.prescout', 'Prescout');
      case 12:
        return context.tr('nav.all-data', context.tr('nav.all_data', 'All Data'));
      case 13:
        return context.tr('nav.match-data', context.tr('nav.match_data', 'Match Data'));
      case 14:
        return context.tr('nav.pit-data', context.tr('nav.pit_data', 'Pit Data'));
      case 15:
        return context.tr('nav.qual-data', context.tr('nav.qual_data', 'Qual Data'));
      case 16:
        return context.tr('nav.data-validation', context.tr('nav.data_validation', 'Data Validation'));
      case 17:
        return context.tr('nav.scout-history', context.tr('nav.scout_history', 'Scout History'));
      case 18:
        return context.tr('nav.custom_analytics', context.tr('nav.analytics', 'Analytics'));
      case 19:
        return context.tr('nav.contact', 'Contact');
      case 20:
        return context.tr('nav.predictor', 'Predictor');
      case 21:
        return context.tr('nav.event-predictor', context.tr('nav.event_predictor', 'Event Predictor'));
      case 22:
        return context.tr('nav.users', 'Users');
      case 23:
        return context.tr('nav.cluster-management', context.tr('nav.cluster_management', 'Cluster'));
      case 24:
        return context.tr('nav.error-reports', context.tr('nav.error_reports', 'Error Reports'));
      case 25:
        return context.tr('events.title', 'Events');
      case 26:
        return context.tr('rankings.title', 'Team Rankings');
      case 27:
        return context.tr('qual_rankings.title', 'Qualitative Rankings');
      case 28:
        return 'Theme Customizer';
      case 29:
        return context.tr('nav.my_assignments', 'My Assignments');
      case 30:
        return context.tr('nav.scout_assignments', 'Scout Assignments');
      case 31:
        return context.tr('nav.match_planning', 'Match Planning');
      case 32:
        return context.tr('nav.shared_links', 'Shared Links');
      case 33:
        return context.tr('nav.match_checklist', 'Match Checklist');
      case 34:
        return context.tr('nav.battery_tracker', 'Battery Tracker');
      default:
        return 'Dashboard';
    }
  }

  static Widget buildScreenByIndex({
    required int screenIndex,
    required ApiService apiService,
    required bool isTabActive,
    required int currentIndex,
    required bool isBarsVisible,
    String? chatChannel,
    String? pendingChatChannel,
    MatchScoutParams? pendingMatchParams,
    PitScoutParams? pendingPitParams,
    QualScoutParams? pendingQualParams,
    required void Function(int index) onNavigateScreen,
    required VoidCallback onOpenQrScanner,
    required Future<void> Function() onLogout,
    required void Function({String? matchKey, int? matchNumber, int? targetTeamNumber, String? sourceAssignmentId}) onNavigateToMatchScout,
    required void Function({int? targetTeamNumber, String? sourceAssignmentId}) onNavigateToPitScout,
    required void Function({String? matchKey, int? matchNumber, String? allianceColor, int? targetTeamNumber, String? sourceAssignmentId}) onNavigateToQualScout,
  }) {
    switch (screenIndex) {
      case 0:
        return DashboardScreen(
          apiService: apiService,
          onNavigateMatch: () => onNavigateScreen(1),
          onNavigatePit: () => onNavigateScreen(2),
          onNavigateAnalytics: () => onNavigateScreen(4),
          onNavigateQrScanner: onOpenQrScanner,
          onNavigateAlliance: () => onNavigateScreen(7),
          onNavigatePrescout: () => onNavigateScreen(11),
          onNavigateHistory: () => onNavigateScreen(17),
          isVisible: isTabActive && currentIndex == 0,
          isBarsVisible: isBarsVisible,
        );
      case 1:
        return MatchScoutScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 1,
          isBarsVisible: isBarsVisible,
          initialMatchKey: pendingMatchParams?.matchKey,
          initialMatchNumber: pendingMatchParams?.matchNumber,
          initialTargetTeamNumber: pendingMatchParams?.targetTeamNumber,
          sourceAssignmentId: pendingMatchParams?.sourceAssignmentId,
        );
      case 2:
        return PitScoutScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 2,
          isBarsVisible: isBarsVisible,
          initialTargetTeamNumber: pendingPitParams?.targetTeamNumber,
          sourceAssignmentId: pendingPitParams?.sourceAssignmentId,
        );
      case 3:
        return QualScoutScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 3,
          isBarsVisible: isBarsVisible,
          initialMatchKey: pendingQualParams?.matchKey,
          initialMatchNumber: pendingQualParams?.matchNumber,
          initialAllianceColor: pendingQualParams?.allianceColor,
          initialTargetTeamNumber: pendingQualParams?.targetTeamNumber,
          sourceAssignmentId: pendingQualParams?.sourceAssignmentId,
        );
      case 4:
        return GraphsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 4,
          isBarsVisible: isBarsVisible,
        );
      case 5:
        return SettingsScreen(
          apiService: apiService,
          onLogout: onLogout,
          onNavigateConfigEditor: () => onNavigateScreen(10),
          onNavigateUsers: () => onNavigateScreen(22),
          onNavigateErrorReports: () => onNavigateScreen(24),
          onNavigateThemeEditor: () => onNavigateScreen(28),
          isVisible: isTabActive && currentIndex == 5,
          isBarsVisible: isBarsVisible,
        );
      case 6:
        return ChatScreen(
          apiService: apiService,
          initialChannel: chatChannel ?? pendingChatChannel,
          isVisible: isTabActive && currentIndex == 6,
          isBarsVisible: isBarsVisible,
        );
      case 7:
        return AllianceSelectionScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 7,
          isBarsVisible: isBarsVisible,
        );
      case 8:
        return TeamsListScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 8,
          isBarsVisible: isBarsVisible,
        );
      case 9:
        return MatchListScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 9,
          isBarsVisible: isBarsVisible,
        );
      case 10:
        return ConfigEditorScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 10,
          isBarsVisible: isBarsVisible,
        );
      case 11:
        return PrescoutScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 11,
          isBarsVisible: isBarsVisible,
        );
      case 12:
        return AllDataScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 12,
          isBarsVisible: isBarsVisible,
        );
      case 13:
        return MatchDataScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 13,
          isBarsVisible: isBarsVisible,
        );
      case 14:
        return PitDataScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 14,
          isBarsVisible: isBarsVisible,
        );
      case 15:
        return QualDataScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 15,
          isBarsVisible: isBarsVisible,
        );
      case 16:
        return DataValidationScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 16,
          isBarsVisible: isBarsVisible,
        );
      case 17:
        return ScoutHistoryScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 17,
          isBarsVisible: isBarsVisible,
        );
      case 18:
        return CustomAnalyticsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 18,
          isBarsVisible: isBarsVisible,
        );
      case 19:
        return ContactScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 19,
          isBarsVisible: isBarsVisible,
        );
      case 20:
        return PredictorScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 20,
          isBarsVisible: isBarsVisible,
        );
      case 21:
        return EventPredictorScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 21,
          isBarsVisible: isBarsVisible,
        );
      case 22:
        return UsersScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 22,
          isBarsVisible: isBarsVisible,
        );
      case 23:
        return ClusterManagementScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 23,
          isBarsVisible: isBarsVisible,
          onNavigateErrorReports: () => onNavigateScreen(24),
        );
      case 24:
        return ErrorReportsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 24,
          isBarsVisible: isBarsVisible,
          onNavigateCluster: () => onNavigateScreen(23),
        );
      case 25:
        return EventsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 25,
          isBarsVisible: isBarsVisible,
        );
      case 26:
        return RankingsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 26,
          isBarsVisible: isBarsVisible,
        );
      case 27:
        return QualRankingsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 27,
          isBarsVisible: isBarsVisible,
        );
      case 28:
        return ThemeEditorScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 28,
          isBarsVisible: isBarsVisible,
          onBack: () => onNavigateScreen(5),
        );
      case 29:
        return MyAssignmentsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 29,
          isBarsVisible: isBarsVisible,
          onNavigateMatch: (matchKey, matchNum, teamNum, assignmentId) {
            onNavigateToMatchScout(
              matchKey: matchKey,
              matchNumber: matchNum,
              targetTeamNumber: teamNum,
              sourceAssignmentId: assignmentId,
            );
          },
          onNavigatePit: (teamNum, assignmentId) {
            onNavigateToPitScout(
              targetTeamNumber: teamNum,
              sourceAssignmentId: assignmentId,
            );
          },
          onNavigateQual: (matchKey, matchNum, allianceColor, teamNum, assignmentId) {
            onNavigateToQualScout(
              matchKey: matchKey,
              matchNumber: matchNum,
              allianceColor: allianceColor,
              targetTeamNumber: teamNum,
              sourceAssignmentId: assignmentId,
            );
          },
        );
      case 30:
        return ScoutAssignmentsScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 30,
          isBarsVisible: isBarsVisible,
        );
      case 31:
        return MatchPlanningScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 31,
          isBarsVisible: isBarsVisible,
        );
      case 32:
        return TeamSharedLinksScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 32,
          isBarsVisible: isBarsVisible,
        );
      case 33:
        return MatchChecklistScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 33,
          isBarsVisible: isBarsVisible,
          onOpenSettings: () => onNavigateScreen(5),
        );
      case 34:
        return BatteryTrackerScreen(
          apiService: apiService,
          isVisible: isTabActive && currentIndex == 34,
          isBarsVisible: isBarsVisible,
          onOpenSettings: () => onNavigateScreen(5),
          onOpenChecklist: () => onNavigateScreen(33),
        );
      default:
        return DashboardScreen(
          apiService: apiService,
          onNavigateMatch: () => onNavigateScreen(1),
          onNavigatePit: () => onNavigateScreen(2),
          onNavigateAnalytics: () => onNavigateScreen(4),
          onNavigateQrScanner: onOpenQrScanner,
          onNavigateAlliance: () => onNavigateScreen(7),
          onNavigatePrescout: () => onNavigateScreen(11),
          onNavigateHistory: () => onNavigateScreen(17),
          isVisible: isTabActive && currentIndex == 0,
          isBarsVisible: isBarsVisible,
        );
    }
  }
}
