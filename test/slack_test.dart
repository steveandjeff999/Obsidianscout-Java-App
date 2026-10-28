import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/slack_models.dart';
import 'package:obsidianscout_app/widgets/obsidian_feedback.dart';
import 'package:obsidianscout_app/widgets/slack_banner_overlay.dart';

SlackBanner _banner(String id, {bool mentioned = false, String url = ''}) => SlackBanner(
      id: id,
      channel: '#general',
      author: 'Ann',
      text: 'message $id',
      url: url,
      mentioned: mentioned,
      createdAt: DateTime.now(),
    );

void main() {
  group('Slack models', () {
    test('banner only opens https Slack links', () {
      expect(_banner('a', url: 'https://team.slack.com/archives/C1/p1').safeUri, isNotNull);
      expect(_banner('b', url: 'javascript:alert(1)').safeUri, isNull);
      expect(_banner('c', url: 'https://evil.example.com/slack.com').safeUri, isNull);
      expect(_banner('d', url: 'http://team.slack.com/x').safeUri, isNull);
    });

    test('channel rule round-trips through JSON', () {
      const rule = SlackChannelRule(
        channelId: 'C1',
        channelName: 'drive',
        trigger: 'ALL_MESSAGES',
        userGroupIds: ['S1'],
        keywords: ['queue'],
        audience: SlackAudience(everyone: false, roles: ['SCOUT'], userIds: ['u1']),
        push: true,
      );
      final back = SlackChannelRule.fromJson(rule.toJson());
      expect(back.toJson(), rule.toJson());
    });

    test('integration parses server payload with defaults', () {
      final i = SlackIntegration.fromJson({
        'configured': true,
        'enabled': true,
        'status': 'connected',
        'rules': [
          {'channelId': 'C1'}
        ],
        'userLinks': {'u1': 'U1'},
        'lastEventAt': null,
      });
      expect(i.rules.single.trigger, 'MENTIONS');
      expect(i.rules.single.audience.everyone, isTrue);
      expect(i.userLinks, {'u1': 'U1'});
      expect(i.lastEventAt, isNull);
    });
  });

  group('SlackBannerOverlay', () {
    Future<void> pumpHost(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(navigatorKey: ObsidianFeedback.navigatorKey, home: const Scaffold()));
    }

    testWidgets('shows a banner once per id and keeps mentions when folding', (tester) async {
      await pumpHost(tester);

      SlackBannerOverlay.show(_banner('m1', mentioned: true));
      SlackBannerOverlay.show(_banner('m1', mentioned: true));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('message m1'), findsOneWidget);

      SlackBannerOverlay.show(_banner('p1'));
      SlackBannerOverlay.show(_banner('p2'));
      SlackBannerOverlay.show(_banner('p3'));
      await tester.pump(const Duration(milliseconds: 300));
      // Three visible: the oldest plain one folded, the mention stayed.
      expect(find.text('message m1'), findsOneWidget);
      expect(find.text('message p1'), findsNothing);
      expect(find.textContaining('+1 more'), findsOneWidget);

      // Plain banners close on their own; the mention stays until dismissed.
      await tester.pump(const Duration(seconds: 11));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('message p3'), findsNothing);
      expect(find.text('message m1'), findsOneWidget);

      SlackBannerOverlay.dismissAll();
      await tester.pump();
      expect(find.text('message m1'), findsNothing);
    });
  });
}
