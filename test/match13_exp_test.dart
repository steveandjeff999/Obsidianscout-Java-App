import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/predictor_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/models/validation_models.dart';

void main() {
  group('Match 13 xP Support Tests', () {
    test('AppSettingsModel parses and serializes useMatch13Exp and match13BaseUrl', () {
      final json = {
        'useStatboticsEpa': true,
        'useTbaOpr': true,
        'useMatch13Exp': true,
        'match13BaseUrl': 'https://api.match13.com/v1',
      };

      final settings = AppSettingsModel.fromJson(json);
      expect(settings.useMatch13Exp, isTrue);
      expect(settings.match13BaseUrl, 'https://api.match13.com/v1');

      final serialized = settings.toJson();
      expect(serialized['useMatch13Exp'], isTrue);
      expect(serialized['match13BaseUrl'], 'https://api.match13.com/v1');
    });

    test('ApiKeysModel parses and serializes match13Key', () {
      final json = {
        'statboticsKey': 'sb_123',
        'tbaKey': 'tba_456',
        'match13Key': 'm13_789',
      };

      final keys = ApiKeysModel.fromJson(json);
      expect(keys.match13Key, 'm13_789');

      final serialized = keys.toJson();
      expect(serialized['match13Key'], 'm13_789');
    });

    test('TeamModel calculates weighted performance score with EXP', () {
      final team = TeamModel(
        eventKey: '2026txhou',
        teamKey: 'frc254',
        teamNumber: 254,
        averagePoints: 40.0,
        exp: 42.0,
        epa: 38.0,
        opr: 35.0,
      );

      expect(team.exp, 42.0);
      expect(team.calculatedWeighted, greaterThan(0));
      // Formula: (40.0*1.0 + 42.0*0.9 + 38.0*0.8 + 35.0*0.6) / (1.0 + 0.9 + 0.8 + 0.6)
      // (40 + 37.8 + 30.4 + 21.0) / 3.3 = 129.2 / 3.3 ≈ 39.15
      expect(team.calculatedWeighted, closeTo(39.15, 0.1));
    });

    test('MatchPredictionResponse parses useMatch13Exp, match13Pred, and match13TeamExp', () {
      final json = {
        'matchKey': '2026txhou_qm1',
        'label': 'Quals 1',
        'useMatch13Exp': true,
        'match13Pred': {
          'redWinProb': 0.78,
          'blueWinProb': 0.22,
          'redScore': 124.5,
          'blueScore': 98.2,
          'redRp1': 0.85,
          'redRp2': 0.60,
          'redRp3': 0.40,
          'blueRp1': 0.50,
          'blueRp2': 0.30,
          'blueRp3': 0.10,
        },
        'redAlliance': {
          'totalScoutedScore': 110.0,
          'totalEpa': 115.0,
          'totalOpr': 105.0,
          'totalExp': 124.5,
          'teams': [
            {
              'teamNumber': 254,
              'nickname': 'The Cheesy Poofs',
              'exp': 45.0,
              'match13TeamExp': {
                'xAutoPost': 15.0,
                'xTelePost': 25.0,
                'xEndPost': 5.0,
              },
            }
          ]
        },
        'blueAlliance': {
          'totalScoutedScore': 90.0,
          'totalEpa': 95.0,
          'totalOpr': 88.0,
          'totalExp': 98.2,
          'teams': [
            {
              'teamNumber': 1678,
              'nickname': 'Citrus Circuits',
              'exp': 40.0,
            }
          ]
        }
      };

      final response = MatchPredictionResponse.fromJson(json);
      expect(response.useMatch13Exp, isTrue);
      expect(response.match13Pred, isNotNull);
      expect(response.match13Pred!.redWinProb, 0.78);
      expect(response.match13Pred!.redScore, 124.5);
      expect(response.match13Pred!.redRp1, 0.85);

      expect(response.redAlliance.totalExp, 124.5);
      expect(response.redAlliance.teams.first.exp, 45.0);
      expect(response.redAlliance.teams.first.match13TeamExp?.xAutoPost, 15.0);
    });

    test('ValidationSummaryModel and TeamValidationModel parse exp and expDiff', () {
      final json = {
        'eventKey': '2026txhou',
        'useMatch13Exp': true,
        'teams': [
          {
            'teamNumber': 254,
            'teamKey': 'frc254',
            'nickname': 'The Cheesy Poofs',
            'exp': 42.0,
            'expDiff': -2.5,
          }
        ],
        'matches': []
      };

      final summary = ValidationSummaryModel.fromJson(json);
      expect(summary.useMatch13Exp, isTrue);
      expect(summary.teams.first.exp, 42.0);
      expect(summary.teams.first.expDiff, -2.5);
    });
  });
}
