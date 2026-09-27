import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/graph_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';

void main() {
  group('Match 13 EXP Models & Helpers Tests', () {
    test('StatsHistoryModel serialization and deserialization', () {
      final json = {
        'oprs': {'118': 42.5},
        'epaHistory': [
          {'match': 'qm1', 'teams': {'118': {'epa': 42.5}}}
        ],
        'match13History': [
          {
            'match_key': 'qm1',
            'teams': [
              {
                'teamNumber': 118,
                'xpPost': 55.4,
                'xAutoPost': 18.2,
                'xTelePost': 25.0,
                'xEndPost': 12.2,
              }
            ]
          }
        ]
      };

      final model = StatsHistoryModel.fromJson(json);
      expect(model.oprs['118'], equals(42.5));
      expect(model.epaHistory, isNotEmpty);
      expect(model.match13History, isNotEmpty);

      final exported = model.toJson();
      expect(exported['oprs'], isNotNull);
      expect(exported['match13History'], isNotEmpty);
    });

    test('extractTeamExpData correctly locates team in List and Map structures', () {
      final matchObjList = {
        'match_key': 'qm1',
        'teams': [
          {'teamNumber': 118, 'xpPost': 50.0},
          {'team_number': 148, 'xpPost': 48.0},
          {'teamKey': 'frc254', 'xpPost': 60.0},
        ]
      };

      final team118 = extractTeamExpData(matchObjList, 118);
      expect(team118, isNotNull);
      expect(team118['xpPost'], equals(50.0));

      final team148 = extractTeamExpData(matchObjList, 148);
      expect(team148, isNotNull);
      expect(team148['xpPost'], equals(48.0));

      final team254 = extractTeamExpData(matchObjList, 254);
      expect(team254, isNotNull);
      expect(team254['xpPost'], equals(60.0));

      final teamUnknown = extractTeamExpData(matchObjList, 9999);
      expect(teamUnknown, isNull);

      final matchObjMap = {
        'match_key': 'qm2',
        'teams': {
          '118': {'xpPost': 52.0},
          'frc254': {'xpPost': 62.0},
        }
      };

      expect(extractTeamExpData(matchObjMap, 118)?['xpPost'], equals(52.0));
      expect(extractTeamExpData(matchObjMap, 254)?['xpPost'], equals(62.0));
    });

    test('getTeamExpMetricValue extracts proper metric values across various alias keys', () {
      final teamData = {
        'xpPost': 75.5,
        'xAutoPost': 22.0,
        'xTelePost': 38.5,
        'xEndPost': 15.0,
      };

      expect(getTeamExpMetricValue(teamData, 'total_points'), equals(75.5));
      expect(getTeamExpMetricValue(teamData, 'score_auto'), equals(22.0));
      expect(getTeamExpMetricValue(teamData, 'score_teleop'), equals(38.5));
      expect(getTeamExpMetricValue(teamData, 'score_endgame'), equals(15.0));

      // Test alternative key names
      final altData = {
        'exp': 60.0,
        'auto': 15.0,
        'teleop': 30.0,
        'endgame': 15.0,
      };
      expect(getTeamExpMetricValue(altData, 'total_points'), equals(60.0));
      expect(getTeamExpMetricValue(altData, 'score_auto'), equals(15.0));
      expect(getTeamExpMetricValue(altData, 'score_teleop'), equals(30.0));
      expect(getTeamExpMetricValue(altData, 'score_endgame'), equals(15.0));
    });

    test('formatMatchKeyToLabel and getMatchSortWeightFromLabel format & sort properly', () {
      expect(formatMatchKeyToLabel('2026txcmp_qm1'), equals('QM 1'));
      expect(formatMatchKeyToLabel('2026txcmp_sf1m1'), equals('SF 1-1'));
      expect(formatMatchKeyToLabel('2026txcmp_f1m1'), equals('Final 1'));
      expect(formatMatchKeyToLabel('prescout'), equals('PRESCOUT'));

      final wPrescout = getMatchSortWeightFromLabel('Prescout');
      final wQm1 = getMatchSortWeightFromLabel('QM 1');
      final wQm2 = getMatchSortWeightFromLabel('QM 2');
      final wSf1 = getMatchSortWeightFromLabel('SF 1-1');
      final wF1 = getMatchSortWeightFromLabel('Final 1-1');

      expect(wPrescout < wQm1, isTrue);
      expect(wQm1 < wQm2, isTrue);
      expect(wQm2 < wSf1, isTrue);
      expect(wSf1 < wF1, isTrue);
    });

    test('AppSettingsModel handles useMatch13Exp and match13BaseUrl', () {
      final json = {
        'useStatboticsEpa': true,
        'useTbaOpr': false,
        'useMatch13Exp': true,
        'match13BaseUrl': 'https://api.match13.com',
      };

      final settings = AppSettingsModel.fromJson(json);
      expect(settings.useMatch13Exp, isTrue);
      expect(settings.match13BaseUrl, equals('https://api.match13.com'));

      final exported = settings.toJson();
      expect(exported['useMatch13Exp'], isTrue);
      expect(exported['match13BaseUrl'], equals('https://api.match13.com'));

      final copied = settings.copyWith(useMatch13Exp: false);
      expect(copied.useMatch13Exp, isFalse);
      expect(copied.match13BaseUrl, equals('https://api.match13.com'));

      // Test string "true" and alias keys
      final jsonStr = {
        'use_match13_exp': 'true',
        'use_statbotics_epa': 1,
      };
      final settingsStr = AppSettingsModel.fromJson(jsonStr);
      expect(settingsStr.useMatch13Exp, isTrue);
      expect(settingsStr.useStatboticsEpa, isTrue);
    });

    test('TeamModel handles exp and match13Exp fields', () {
      final json = {
        'teamNumber': 118,
        'teamName': 'Robonauts',
        'match13Exp': 58.5,
        'epa': 45.0,
      };

      final team = TeamModel.fromJson(json);
      expect(team.teamNumber, equals(118));
      expect(team.exp, equals(58.5));
      expect(team.match13Exp, equals(58.5));
      expect(team.epa, equals(45.0));
    });
  });
}
