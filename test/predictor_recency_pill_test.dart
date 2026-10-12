import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/predictor_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/screens/predictor_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';

class _MockPredictorApiService extends ApiService {
  final MatchPredictionResponse prediction;
  _MockPredictorApiService(this.prediction);

  @override
  bool get isOnline => true;

  @override
  Future<AppSettingsModel?> getCachedSettings() async => AppSettingsModel(eventKey: '2026test');

  @override
  Future<String?> getCachedEventKey() async => '2026test';

  @override
  Future<List<MatchModel>> getCachedMatches(String? eventKey) async => [];

  @override
  Future<List<MatchModel>> fetchMatches(String? eventKey) async => [
        MatchModel(matchKey: '2026test_qm1', eventKey: '2026test', compLevel: 'qm', matchNumber: 1, label: 'QM 1'),
      ];

  @override
  Future<MatchPredictionResponse?> getCachedMatchPrediction({
    required String eventKey,
    required String matchKey,
    bool usePrescout = false,
  }) async =>
      null;

  @override
  Future<MatchPredictionResponse?> fetchMatchPrediction(String matchKey, {String? eventKey, bool usePrescout = false}) async =>
      prediction;
}

MatchTeamPrediction _team(int number, {bool weighted = false}) => MatchTeamPrediction(
      teamNumber: number,
      nickname: 'Team $number',
      averageScoutedScore: 50,
      scoutedMatchesCount: 6,
      recencyWeighted: weighted,
    );

void main() {
  testWidgets('predictor shows the recency pill only on weighted teams, with a tooltip', (tester) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    final prediction = MatchPredictionResponse(
      matchKey: '2026test_qm1',
      label: 'QM 1',
      redAlliance: AlliancePrediction(teams: [_team(1706, weighted: true), _team(2), _team(3)], totalScoutedScore: 150),
      blueAlliance: AlliancePrediction(teams: [_team(4), _team(5), _team(6)], totalScoutedScore: 150),
    );

    await tester.pumpWidget(MaterialApp(
      theme: ObsidianUITheme.darkTheme,
      home: Scaffold(
        body: PredictorScreen(apiService: _MockPredictorApiService(prediction), initialMatchKey: '2026test_qm1'),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final pill = find.text('Recency-weighted');
    expect(pill, findsOneWidget);

    await tester.ensureVisible(pill);
    await tester.tap(pill);
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.textContaining("Recent matches count more in this team's scouted average"), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
