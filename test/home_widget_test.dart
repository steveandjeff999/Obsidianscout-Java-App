import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/services/home_widget_service.dart';

void main() {
  group('MatchModel times', () {
    test('reads the server-adjusted predicted time', () {
      final m = MatchModel.fromJson({
        'matchKey': '2026test_qm12',
        'eventKey': '2026test',
        'compLevel': 'qm',
        'matchNumber': 12,
        'scheduledTime': 1800000000,
        'predictedTime': 1800000480,
        'scheduleOffsetSeconds': 480,
        'eventTimezone': 'America/Chicago',
      });
      expect(m.predictedStart, DateTime.fromMillisecondsSinceEpoch(1800000480 * 1000, isUtc: true));
      expect(m.scheduledStart, DateTime.fromMillisecondsSinceEpoch(1800000000 * 1000, isUtc: true));
      expect(m.scheduleOffsetSeconds, 480);
      expect(m.isPlayed, isFalse);
    });

    test('falls back to the schedule and tolerates old cached JSON without times', () {
      final scheduledOnly = MatchModel.fromJson({'matchKey': 'k_qm1', 'scheduledTime': 1800000000});
      expect(scheduledOnly.predictedStart, scheduledOnly.scheduledStart);

      final old = MatchModel.fromJson({'matchKey': 'k_qm2', 'compLevel': 'qm'});
      expect(old.predictedStart, isNull);
      expect(old.isPlayed, isFalse);
    });

    test('played when it has a score or an actual time different from the schedule', () {
      expect(MatchModel.fromJson({'matchKey': 'a', 'redScore': 0, 'blueScore': 0}).isPlayed, isTrue);
      expect(MatchModel.fromJson({'matchKey': 'b', 'redScore': -1, 'blueScore': -1}).isPlayed, isFalse);
      expect(MatchModel.fromJson({'matchKey': 'c', 'scheduledTime': 100, 'actualTime': 160}).isPlayed, isTrue);
      expect(MatchModel.fromJson({'matchKey': 'd', 'scheduledTime': 100, 'actualTime': 100}).isPlayed, isFalse);
    });
  });

  group('WidgetLaunch', () {
    test('parses page links', () {
      final launch = WidgetLaunch.fromUri(Uri.parse('obsidianscout://widget/page/battery-tracker'));
      expect(launch?.action, 'page');
      expect(launch?.params['page'], 'battery-tracker');
    });

    test('parses row-specific page links for chat, schedule, and rankings', () {
      final chatLaunch = WidgetLaunch.fromUri(
        Uri.parse('obsidianscout://widget/page/chat?group=Drive%20Team'),
      );
      expect(chatLaunch?.action, 'page');
      expect(chatLaunch?.params['page'], 'chat');
      expect(chatLaunch?.params['group'], 'Drive Team');

      final matchLaunch = WidgetLaunch.fromUri(
        Uri.parse('obsidianscout://widget/page/matches?matchKey=2026test_qm24'),
      );
      expect(matchLaunch?.action, 'page');
      expect(matchLaunch?.params['page'], 'matches');
      expect(matchLaunch?.params['matchKey'], '2026test_qm24');

      final rankLaunch = WidgetLaunch.fromUri(
        Uri.parse('obsidianscout://widget/page/rankings?team=254'),
      );
      expect(rankLaunch?.action, 'page');
      expect(rankLaunch?.params['page'], 'rankings');
      expect(rankLaunch?.params['team'], '254');
    });

    test('parses scouting links', () {
      final launch = WidgetLaunch.fromUri(
        Uri.parse('obsidianscout://widget/scout?type=MATCH&id=a1&matchKey=2026test_qm4&number=4&team=254'),
      );
      expect(launch?.action, 'scout');
      expect(launch?.params['team'], '254');
      expect(launch?.params['matchKey'], '2026test_qm4');
    });

    test('ignores links that are not widget links', () {
      expect(WidgetLaunch.fromUri(null), isNull);
      expect(WidgetLaunch.fromUri(Uri.parse('https://example.com/widget/page/chat')), isNull);
      expect(WidgetLaunch.fromUri(Uri.parse('obsidianscout://other/page/chat')), isNull);
      expect(WidgetLaunch.fromUri(Uri.parse('obsidianscout://widget')), isNull);
    });

    test('every widget kind maps to a receiver in the app package', () {
      final ids = HomeWidgetService.kinds.map((k) => k.id).toSet();
      expect(ids, {'next_match', 'schedule', 'predictor', 'assignments', 'battery', 'checklist', 'rankings', 'chat', 'quick_actions'});
      for (final k in HomeWidgetService.kinds) {
        expect(k.qualifiedAndroidName, startsWith('com.obsidianscout.obsidianscout_app.widgets.'));
      }
    });

    test('exposes native SharedPreferences sync keys', () {
      expect(HomeWidgetService.keyEtag, 'widget_snapshot_etag');
      expect(HomeWidgetService.keyFetchedAt, 'widget_snapshot_fetched_at');
      expect(HomeWidgetService.keyAuthExpired, 'widget_auth_expired');
    });
  });
}

