import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/custom_analytics_models.dart';
import 'package:obsidianscout_app/screens/custom_analytics_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';

class _MockCustomAnalyticsApiService extends ApiService {
  @override
  Future<List<CustomAnalyticsReportRecord>> fetchCustomAnalyticsReports() async => [
        CustomAnalyticsReportRecord(
          id: 'rep_1',
          ownerTeamNumber: 254,
          program: 'FRC',
          userId: 'user_1',
          title: 'Strategy Dashboard',
          category: 'Strategy',
          configJson: jsonEncode(CustomAnalyticsConfig().toJson()),
          createdAt: DateTime.now().toIso8601String(),
          updatedAt: DateTime.now().toIso8601String(),
        ),
      ];

  @override
  Future<CustomAnalyticsDataset?> fetchCustomAnalyticsDataset({
    String? eventKey,
    bool includePrescout = true,
  }) async =>
      CustomAnalyticsDataset(
        generatedAt: DateTime.now().toIso8601String(),
        fields: [
          CustomAnalyticsField(id: 'calc_total_score', label: 'Total Score', type: 'number', source: 'calculated'),
          CustomAnalyticsField(id: 'calc_auto_score', label: 'Auto Score', type: 'number', source: 'calculated'),
          CustomAnalyticsField(id: 'calc_teleop_score', label: 'Teleop Score', type: 'number', source: 'calculated'),
        ],
        matchEntries: [
          {
            'teamNumber': 254,
            'matchNumber': 1,
            'eventKey': '2026cmp',
            'calc_total_score': 85.0,
            'calc_auto_score': 30.0,
            'calc_teleop_score': 55.0,
          },
          {
            'teamNumber': 1678,
            'matchNumber': 1,
            'eventKey': '2026cmp',
            'calc_total_score': 78.0,
            'calc_auto_score': 28.0,
            'calc_teleop_score': 50.0,
          },
        ],
        pitEntries: [],
        qualEntries: [],
        teams: [
          CustomTeamAnalyticsSummary(teamNumber: 254, name: 'The Cheesy Poofs'),
          CustomTeamAnalyticsSummary(teamNumber: 1678, name: 'Citrus Circuits'),
        ],
        totalMatches: 2,
        totalTeams: 2,
      );
}

void main() {
  group('Custom Analytics Math & Formula Tests', () {
    test('computeAggregation calculates statistical metrics correctly', () {
      final numbers = [10.0, 20.0, 30.0, 40.0, 50.0];

      expect(CustomAnalyticsMath.computeAggregation(numbers, 'avg'), 30.0);
      expect(CustomAnalyticsMath.computeAggregation(numbers, 'sum'), 150.0);
      expect(CustomAnalyticsMath.computeAggregation(numbers, 'median'), 30.0);
      expect(CustomAnalyticsMath.computeAggregation(numbers, 'max'), 50.0);
      expect(CustomAnalyticsMath.computeAggregation(numbers, 'min'), 10.0);
      expect(CustomAnalyticsMath.computeAggregation(numbers, 'count'), 5.0);
      expect(CustomAnalyticsMath.computeAggregation(numbers, 'p75'), 40.0);
    });

    test('evaluateFormula parses mathematical expressions with bracketed field IDs', () {
      final entry = {
        'calc_auto_score': 12,
        'calc_teleop_score': 24,
        'bonus_multiplier': 2.0,
      };

      const formula1 = '[calc_auto_score] * 2 + [calc_teleop_score]';
      expect(CustomAnalyticsMath.evaluateFormula(formula1, entry), 48.0);

      const formula2 = '([calc_auto_score] + [calc_teleop_score]) / [bonus_multiplier]';
      expect(CustomAnalyticsMath.evaluateFormula(formula2, entry), 18.0);
    });

    test('CustomAnalyticsConfig JSON round-trip serialization', () {
      final config = CustomAnalyticsConfig(
        title: 'Championship Pick List',
        category: 'Pick List',
        slicers: CustomAnalyticsSlicers(eventKey: '2026cmp', practice: false),
        calculatedMetrics: [
          CustomCalculatedMetric(id: 'calc_offense', name: 'Offense Index', formula: '[calc_auto_score] + [calc_teleop_score]'),
        ],
      );

      final jsonMap = config.toJson();
      final decoded = CustomAnalyticsConfig.fromJson(jsonMap);

      expect(decoded.title, 'Championship Pick List');
      expect(decoded.category, 'Pick List');
      expect(decoded.slicers.eventKey, '2026cmp');
      expect(decoded.slicers.practice, false);
      expect(decoded.calculatedMetrics.length, 1);
      expect(decoded.calculatedMetrics.first.name, 'Offense Index');
      expect(decoded.widgets.isNotEmpty, true);
    });
  });

  group('Custom Analytics Widget Tests', () {
    testWidgets('CustomAnalyticsScreen renders correctly with ApiService', (tester) async {
      final apiService = _MockCustomAnalyticsApiService();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CustomAnalyticsScreen(
              apiService: apiService,
              isVisible: true,
              isBarsVisible: true,
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // Verify that toolbar buttons are present
      expect(find.text('Reports'), findsOneWidget);
      expect(find.text('Templates'), findsOneWidget);
      expect(find.text('New Metric'), findsOneWidget);
      expect(find.text('Add Visual'), findsOneWidget);
    });
  });
}
