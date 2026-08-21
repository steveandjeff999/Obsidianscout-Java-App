import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/screens/all_data_screen.dart';
import 'package:obsidianscout_app/screens/match_data_screen.dart';
import 'package:obsidianscout_app/screens/pit_data_screen.dart';
import 'package:obsidianscout_app/screens/qual_data_screen.dart';
import 'package:obsidianscout_app/services/csv_export_service.dart';
import 'package:obsidianscout_app/widgets/csv_export_modal.dart';

void main() {
  group('CsvExportService Unit Tests', () {
    test('formatCell handles null, numbers, booleans, and strings with quotes/commas', () {
      expect(CsvExportService.formatCell(null), '');
      expect(CsvExportService.formatCell(42), '42');
      expect(CsvExportService.formatCell(3.14), '3.14');
      expect(CsvExportService.formatCell(true), 'TRUE');
      expect(CsvExportService.formatCell(false), 'FALSE');
      expect(CsvExportService.formatCell('simple'), 'simple');
      expect(CsvExportService.formatCell('hello, world'), '"hello, world"');
      expect(CsvExportService.formatCell('say "hello"'), '"say ""hello"""');
      expect(CsvExportService.formatCell('line1\nline2'), '"line1\nline2"');
      expect(CsvExportService.formatCell(['alpha', 'beta']), '"alpha; beta"');
      expect(CsvExportService.formatCell({'key': 'value'}), '"{\""key\"":\""value\""}"');
    });

    test('exportMatchData flattens config schema fields into separate columns', () {
      final config = ScoutingConfigModel(
        title: 'FRC 2026',
        version: 1,
        fields: [
          ScoutingFieldModel(id: 'sec_1', label: 'Auto Section', type: 'section'),
          ScoutingFieldModel(id: 'auto_speaker', label: 'Speaker Notes', type: 'counter', phase: 'auto'),
          ScoutingFieldModel(id: 'teleop_amp', label: 'Amp Notes', type: 'counter', phase: 'teleop'),
          ScoutingFieldModel(id: 'climbed', label: 'Climbed', type: 'boolean', phase: 'endgame'),
        ],
      );

      final records = [
        MatchScoutingRecord(
          id: 'rec_1',
          targetTeamNumber: 1234,
          eventKey: '2026txcmp',
          matchNumber: 1,
          scoutUsername: 'Alex',
          createdAt: '2026-08-21T10:00:00Z',
          hasDiscrepancy: false,
          data: {
            'auto_speaker': 4,
            'teleop_amp': 2,
            'climbed': true,
            'custom_note': 'Fast cycles',
          },
        ),
        MatchScoutingRecord(
          id: 'rec_2',
          targetTeamNumber: 5678,
          eventKey: '2026txcmp',
          matchNumber: 1,
          scoutUsername: 'Sam',
          createdAt: '2026-08-21T10:05:00Z',
          hasDiscrepancy: true,
          data: {
            'auto_speaker': 1,
            'teleop_amp': 5,
            'climbed': false,
          },
        ),
      ];

      final export = CsvExportService.exportMatchData(
        records: records,
        config: config,
        eventKey: '2026txcmp',
      );

      expect(export.rowCount, 2);
      expect(export.columnCount, 11); // 7 base + 3 config fields (excluding section) + 1 extra dynamic key
      expect(export.headers, contains('[Auto] Speaker Notes'));
      expect(export.headers, contains('[Teleop] Amp Notes'));
      expect(export.headers, contains('[Endgame] Climbed'));
      expect(export.headers, contains('custom_note'));
      expect(export.headers, isNot(contains('Auto Section')));

      final lines = export.csvContent.trim().split('\n');
      expect(lines.length, 3); // header + 2 rows
      expect(lines[1], contains('1234'));
      expect(lines[1], contains('Alex'));
      expect(lines[1], contains('Fast cycles'));
      expect(lines[2], contains('5678'));
      expect(lines[2], contains('TRUE')); // hasDiscrepancy
    });

    test('exportPitData formats team coverage and pit fields into CSV', () {
      final config = ScoutingConfigModel(
        title: 'Pit Config',
        version: 1,
        fields: [
          ScoutingFieldModel(id: 'drivetrain', label: 'Drive Type', type: 'select'),
          ScoutingFieldModel(id: 'weight', label: 'Robot Weight', type: 'number'),
        ],
      );

      final items = [
        TeamPitCoverageItem(
          teamNumber: 1234,
          nickname: 'Tech Knights',
          hasPitData: true,
          lastUpdated: '2026-08-21T09:00:00Z',
          scoutUsername: 'Chris',
          pitData: {
            'drivetrain': 'Swerve',
            'weight': 115,
          },
        ),
        TeamPitCoverageItem(
          teamNumber: 9999,
          nickname: 'Rookies',
          hasPitData: false,
          pitData: {},
        ),
      ];

      final export = CsvExportService.exportPitData(
        items: items,
        config: config,
        eventKey: '2026txcmp',
      );

      expect(export.rowCount, 2);
      expect(export.columnCount, 7); // 5 base + 2 config fields
      expect(export.headers, contains('Drive Type'));
      expect(export.headers, contains('Robot Weight'));

      expect(export.csvContent, contains('Complete'));
      expect(export.csvContent, contains('Missing'));
      expect(export.csvContent, contains('Swerve'));
      expect(export.csvContent, contains('115'));
    });

    test('exportQualData formats qualitative records into CSV', () {
      final config = ScoutingConfigModel(
        title: 'Qual Config',
        version: 1,
        fields: [
          ScoutingFieldModel(id: 'driver_skill', label: 'Driver Rating', type: 'rating'),
          ScoutingFieldModel(id: 'defense_impact', label: 'Defense Impact', type: 'rating'),
        ],
      );

      final records = [
        QualScoutingRecord(
          id: 'q_1',
          targetTeamNumber: 1234,
          eventKey: '2026txcmp',
          matchNumber: 3,
          scoutUsername: 'Jordan',
          createdAt: '2026-08-21T11:00:00Z',
          data: {
            'driver_skill': 5,
            'defense_impact': 4,
          },
        ),
      ];

      final export = CsvExportService.exportQualData(
        records: records,
        config: config,
        eventKey: '2026txcmp',
      );

      expect(export.rowCount, 1);
      expect(export.columnCount, 8); // 6 base + 2 fields
      expect(export.headers, contains('Driver Rating'));
      expect(export.headers, contains('Defense Impact'));
      expect(export.csvContent, contains('Jordan'));
      expect(export.csvContent, contains('5'));
    });

    test('exportUnifiedData merges match, pit, and qual configs without collisions', () {
      final matchConfig = ScoutingConfigModel(
        title: 'Match',
        version: 1,
        fields: [
          ScoutingFieldModel(id: 'auto_pts', label: 'Auto Points', type: 'counter'),
        ],
      );
      final pitConfig = ScoutingConfigModel(
        title: 'Pit',
        version: 1,
        fields: [
          ScoutingFieldModel(id: 'drive_type', label: 'Drive Base', type: 'text'),
        ],
      );

      final entries = [
        UnifiedScoutingEntry(
          id: 'u_1',
          originalId: 'm_1',
          type: 'Match',
          targetTeamNumber: 1234,
          eventKey: '2026txcmp',
          matchNumber: 1,
          scoutUsername: 'Alex',
          data: {'auto_pts': 15},
        ),
        UnifiedScoutingEntry(
          id: 'u_2',
          originalId: 'p_1',
          type: 'Pit',
          targetTeamNumber: 1234,
          eventKey: '2026txcmp',
          scoutUsername: 'Taylor',
          data: {'drive_type': 'Tank'},
        ),
      ];

      final export = CsvExportService.exportUnifiedData(
        entries: entries,
        matchConfig: matchConfig,
        pitConfig: pitConfig,
        eventKey: '2026txcmp',
      );

      expect(export.rowCount, 2);
      expect(export.headers, contains('[Match] Auto Points'));
      expect(export.headers, contains('[Pit] Drive Base'));
      expect(export.csvContent, contains('Match'));
      expect(export.csvContent, contains('Pit'));
    });
  });

  group('CsvExportModal Widget Tests', () {
    testWidgets('renders metadata badges, preview table, and action buttons', (tester) async {
      final exportData = CsvExportData(
        csvContent: 'ID,Team,Score\n1,1234,95\n2,5678,88\n',
        rowCount: 2,
        columnCount: 3,
        headers: ['ID', 'Team', 'Score'],
        sampleRows: [
          ['1', '1234', '95'],
          ['2', '5678', '88'],
        ],
        suggestedFilename: 'test_export.csv',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: CsvExportModal(
              title: 'Export Test Scouting Data',
              exportData: exportData,
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Export Test Scouting Data'), findsOneWidget);
      expect(find.text('test_export.csv'), findsOneWidget);
      expect(find.text('Rows'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('Columns'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('Data Structure Preview'), findsOneWidget);
      expect(find.text('Download CSV File'), findsOneWidget);
      expect(find.text('Copy Text'), findsOneWidget);

      // Toggle to Raw CSV
      await tester.tap(find.text('Raw CSV'));
      await tester.pumpAndSettle();

      expect(find.text('Table View'), findsOneWidget);
      expect(find.textContaining('ID,Team,Score'), findsOneWidget);

      String? clipboardText;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          clipboardText = (methodCall.arguments as Map)['text'];
          return null;
        }
        return null;
      });

      // Tap Copy Text
      await tester.tap(find.text('Copy Text'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(clipboardText, contains('ID,Team,Score'));

      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });
  });
}
