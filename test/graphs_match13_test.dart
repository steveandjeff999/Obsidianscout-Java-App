import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/graph_models.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';

void main() {
  group('Match 13 xP Models & Helpers Tests', () {
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

    test('extractTeamxPData correctly locates team in List and Map structures', () {
      final matchObjList = {
        'match_key': 'qm1',
        'teams': [
          {'teamNumber': 118, 'xpPost': 50.0},
          {'team_number': 148, 'xpPost': 48.0},
          {'teamKey': 'frc254', 'xpPost': 60.0},
        ]
      };

      final team118 = extractTeamxPData(matchObjList, 118);
      expect(team118, isNotNull);
      expect(team118['xpPost'], equals(50.0));

      final team148 = extractTeamxPData(matchObjList, 148);
      expect(team148, isNotNull);
      expect(team148['xpPost'], equals(48.0));

      final team254 = extractTeamxPData(matchObjList, 254);
      expect(team254, isNotNull);
      expect(team254['xpPost'], equals(60.0));

      final teamUnknown = extractTeamxPData(matchObjList, 9999);
      expect(teamUnknown, isNull);

      final matchObjMap = {
        'match_key': 'qm2',
        'teams': {
          '118': {'xpPost': 52.0},
          'frc254': {'xpPost': 62.0},
        }
      };

      expect(extractTeamxPData(matchObjMap, 118)?['xpPost'], equals(52.0));
      expect(extractTeamxPData(matchObjMap, 254)?['xpPost'], equals(62.0));
    });

    test('getTeamxPMetricValue extracts proper metric values across various alias keys', () {
      final teamData = {
        'xpPost': 75.5,
        'xAutoPost': 22.0,
        'xTelePost': 38.5,
        'xEndPost': 15.0,
      };

      expect(getTeamxPMetricValue(teamData, 'total_points'), equals(75.5));
      expect(getTeamxPMetricValue(teamData, 'score_auto'), equals(22.0));
      expect(getTeamxPMetricValue(teamData, 'score_teleop'), equals(38.5));
      expect(getTeamxPMetricValue(teamData, 'score_endgame'), equals(15.0));

      // Test alternative and legacy key names
      final altData = {
        'xP': 60.0,
        'auto': 15.0,
        'teleop': 30.0,
        'endgame': 15.0,
      };
      expect(getTeamxPMetricValue(altData, 'total_points'), equals(60.0));
      expect(getTeamxPMetricValue(altData, 'score_auto'), equals(15.0));
      expect(getTeamxPMetricValue(altData, 'score_teleop'), equals(30.0));
      expect(getTeamxPMetricValue(altData, 'score_endgame'), equals(15.0));
      expect(getTeamxPMetricValue({'exp': 42.0}, 'total_points'), equals(42.0));
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

    test('AppSettingsModel handles useMatch13xP and match13BaseUrl', () {
      final json = {
        'useStatboticsEpa': true,
        'useTbaOpr': false,
        'useMatch13xP': true,
        'match13BaseUrl': 'https://api.match13.com',
      };

      final settings = AppSettingsModel.fromJson(json);
      expect(settings.useMatch13xP, isTrue);
      expect(settings.match13BaseUrl, equals('https://api.match13.com'));

      final exported = settings.toJson();
      expect(exported['useMatch13xP'], isTrue);
      expect(exported['match13BaseUrl'], equals('https://api.match13.com'));

      final copied = settings.copyWith(useMatch13xP: false);
      expect(copied.useMatch13xP, isFalse);
      expect(copied.match13BaseUrl, equals('https://api.match13.com'));

      // Test string "true" and legacy/alias keys
      final jsonStr = {
        'use_match13_exp': 'true',
        'use_statbotics_epa': 1,
      };
      final settingsStr = AppSettingsModel.fromJson(jsonStr);
      expect(settingsStr.useMatch13xP, isTrue);
      expect(settingsStr.useStatboticsEpa, isTrue);
      expect(AppSettingsModel.fromJson({'useMatch13Exp': true}).useMatch13xP, isTrue);
    });

    test('TeamModel handles xP and match13xP fields (and legacy exp keys)', () {
      final json = {
        'teamNumber': 118,
        'teamName': 'Robonauts',
        'match13xP': 58.5,
        'epa': 45.0,
      };

      final team = TeamModel.fromJson(json);
      expect(team.teamNumber, equals(118));
      expect(team.xP, equals(58.5));
      expect(team.match13xP, equals(58.5));
      expect(team.epa, equals(45.0));

      final legacyTeam = TeamModel.fromJson({
        'teamNumber': 254,
        'match13Exp': 61.0,
      });
      expect(legacyTeam.xP, equals(61.0));
      expect(legacyTeam.match13xP, equals(61.0));
    });
  });
}
