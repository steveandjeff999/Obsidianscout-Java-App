import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/api_response.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/screens/config_editor_screen.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';

import 'package:obsidianscout_app/widgets/dynamic_field_widget.dart';

class _MockConfigApiService extends ApiService {
  @override
  Future<ScoutingConfigModel?> fetchMatchConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'ObsidianScout',
        fields: [
          ScoutingFieldModel(id: 'speaker', label: 'Speaker Score', type: 'counter', phase: 'teleop'),
        ],
      );

  @override
  Future<ScoutingConfigModel?> fetchPitConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'ObsidianScout Pit Scouting',
        fields: [
          ScoutingFieldModel(id: 'drivetrain', label: 'Drivetrain', type: 'select'),
        ],
      );

  @override
  Future<ScoutingConfigModel?> fetchQualConfig() async => ScoutingConfigModel(
        version: 1,
        title: 'ObsidianScout Qualitative Scouting',
        fields: [
          ScoutingFieldModel(id: 'driverSkill', label: 'Driver Skill', type: 'rating'),
        ],
      );

  AppSettingsModel mockSettings = AppSettingsModel(
    year: 2026,
    eventCode: 'nytr',
    timezone: 'America/New_York',
    preferredSource: 'tba',
    apiKeys: ApiKeysModel(tbaKey: 'sample_tba_key', firstUsername: 'user1', firstKey: 'key1'),
  );

  @override
  Future<AppSettingsModel?> fetchSettings() async => mockSettings;

  @override
  Future<ApiResponse<AppSettingsModel>> updateSettings(AppSettingsModel settings) async {
    mockSettings = settings;
    return ApiResponse.success(settings, statusCode: 200, message: 'Settings saved');
  }

  @override
  Future<ApiResponse<Map<String, dynamic>>> testApiKey({
    required String api,
    String? tbaKey,
    String? firstUsername,
    String? firstKey,
    String? statboticsBaseUrl,
  }) async {
    return ApiResponse.success({'success': true, 'message': '$api tested successfully'});
  }

  @override
  Future<List<DefaultConfigPresetModel>> fetchDefaultPresets(String configKind) async => [];
}

void main() {
  group('ScoutingConfigModel and Field Serialization Tests', () {
    test('ScoutingFieldModel serializes and deserializes counter correctly', () {
      final field = ScoutingFieldModel(
        id: 'autoSpeaker',
        label: 'Auto Speaker Score',
        type: 'counter',
        phase: 'auto',
        required: true,
        min: 0,
        max: 20,
        step: 1,
        doubleStep: 5,
        pointsPer: 5.0,
      );

      final jsonMap = field.toJson();
      expect(jsonMap['id'], 'autoSpeaker');
      expect(jsonMap['label'], 'Auto Speaker Score');
      expect(jsonMap['type'], 'counter');
      expect(jsonMap['phase'], 'auto');
      expect(jsonMap['required'], true);
      expect(jsonMap['min'], 0);
      expect(jsonMap['max'], 20);
      expect(jsonMap['step'], 1);
      expect(jsonMap['doubleStep'], 5);
      expect(jsonMap['pointsPer'], 5.0);

      final deserialized = ScoutingFieldModel.fromJson(jsonMap);
      expect(deserialized.id, 'autoSpeaker');
      expect(deserialized.label, 'Auto Speaker Score');
      expect(deserialized.type, 'counter');
      expect(deserialized.phase, 'auto');
      expect(deserialized.required, true);
      expect(deserialized.doubleStep, 5);
      expect(deserialized.pointsPer, 5.0);
    });

    test('ScoutingFieldModel handles select dropdown options with points', () {
      final options = [
        ScoutingOptionModel(label: 'None', value: 'none', points: 0.0),
        ScoutingOptionModel(label: 'Park', value: 'park', points: 2.0),
        ScoutingOptionModel(label: 'Deep Climb', value: 'deep', points: 12.0),
      ];

      final field = ScoutingFieldModel(
        id: 'endgameClimb',
        label: 'Endgame Climb',
        type: 'select',
        phase: 'endgame',
        options: options,
      );

      final jsonMap = field.toJson();
      expect(jsonMap['type'], 'select');
      expect((jsonMap['options'] as List).length, 3);
      expect(jsonMap['options'][2]['points'], 12.0);

      final deserialized = ScoutingFieldModel.fromJson(jsonMap);
      expect(deserialized.options.length, 3);
      expect(deserialized.options[2].label, 'Deep Climb');
      expect(deserialized.options[2].points, 12.0);
    });

    test('ScoutingFieldModel ensures static text fields do not allow required flag', () {
      final textField = ScoutingFieldModel(
        id: 'headerNote',
        label: 'Important Rule Instructions',
        type: 'text',
        required: true,
      );

      final jsonMap = textField.toJson();
      expect(jsonMap['type'], 'text');
      expect(jsonMap.containsKey('required'), false);

      final deserialized = ScoutingFieldModel.fromJson({
        'id': 'headerNote',
        'label': 'Important Rule Instructions',
        'type': 'text',
        'required': true,
      });
      expect(deserialized.required, false);
    });

    test('ScoutingConfigModel round-trips full config with role collection and analytics', () {
      final config = ScoutingConfigModel(
        version: 2,
        title: 'FRC 2026 Reefscape Match Scouting',
        enableRobotRoleCollection: true,
        fields: [
          ScoutingFieldModel(
            id: 'coralL1',
            label: 'Coral L1 Count',
            type: 'counter',
            min: 0,
            step: 1,
            pointsPer: 3.0,
          ),
          ScoutingFieldModel(
            id: 'notesSec',
            label: 'Driver Feedback',
            type: 'textarea',
          ),
        ],
      );

      final jsonMap = config.toJson();
      expect(jsonMap['version'], 2);
      expect(jsonMap['title'], 'FRC 2026 Reefscape Match Scouting');
      expect(jsonMap['enable_robot_role_collection'], true);
      expect((jsonMap['fields'] as List).length, 2);

      final str = jsonEncode(jsonMap);
      final decoded = ScoutingConfigModel.fromJson(jsonDecode(str));
      expect(decoded.version, 2);
      expect(decoded.title, 'FRC 2026 Reefscape Match Scouting');
      expect(decoded.enableRobotRoleCollection, true);
      expect(decoded.fields.length, 2);
      expect(decoded.fields[0].pointsPer, 3.0);
    });

    test('DefaultConfigPresetModel parses and exports preset JSON', () {
      final presetJson = {
        'id': 'frc2026_default',
        'name': 'FRC 2026 Reefscape Official',
        'program': 'FRC',
        'config_type': 'match',
        'config_json': '{"version": 1, "title": "FRC 2026"}',
        'is_default': true,
      };

      final preset = DefaultConfigPresetModel.fromJson(presetJson);
      expect(preset.name, 'FRC 2026 Reefscape Official');
      expect(preset.program, 'FRC');
      expect(preset.configType, 'match');
      expect(preset.isDefault, true);

      final outputMap = preset.toJson();
      expect(outputMap['name'], 'FRC 2026 Reefscape Official');
      expect(outputMap['isDefault'], true);
    });
    test('ConfigRevisionModel serializes and deserializes correctly', () {
      final rev = ConfigRevisionModel(
        id: 'rev_123',
        teamNumber: 1234,
        program: 'FRC',
        configKind: 'game',
        version: 3,
        title: 'FRC 2026 Reefscape v3',
        changeSummary: 'Added endgame climb points',
        savedByUsername: 'lead_scout',
        fieldCount: 15,
        createdAt: '2026-03-01T12:00:00Z',
      );

      final json = rev.toJson();
      expect(json['id'], 'rev_123');
      expect(json['version'], 3);
      expect(json['changeSummary'], 'Added endgame climb points');
      expect(json['savedByUsername'], 'lead_scout');

      final parsed = ConfigRevisionModel.fromJson(json);
      expect(parsed.id, 'rev_123');
      expect(parsed.version, 3);
      expect(parsed.fieldCount, 15);
      expect(parsed.title, 'FRC 2026 Reefscape v3');
    });

    test('ConfigSchemaStatusModel and Migration Models deserialize correctly', () {
      final statusJson = {
        'configKind': 'game',
        'entryCount': 42,
        'configVersion': 2,
        'configFields': [
          {'id': 'speaker', 'label': 'Speaker', 'type': 'counter'},
        ],
        'dataKeys': ['speaker', 'oldAmp'],
        'unmatchedDataKeys': ['oldAmp'],
        'newConfigKeys': ['trap'],
      };

      final status = ConfigSchemaStatusModel.fromJson(statusJson);
      expect(status.entryCount, 42);
      expect(status.configVersion, 2);
      expect(status.configFields.length, 1);
      expect(status.unmatchedDataKeys, ['oldAmp']);
      expect(status.newConfigKeys, ['trap']);

      final mapping = ConfigMigrationMappingModel(oldKey: 'oldAmp', newKey: 'amp', action: 'map');
      expect(mapping.toJson()['action'], 'map');

      final resultJson = {
        'success': true,
        'configKind': 'game',
        'migratedCount': 42,
        'updatedKeys': ['oldAmp -> amp'],
        'deletedKeys': [],
        'backfilledKeys': ['trap'],
      };
      final result = ConfigMigrationResultModel.fromJson(resultJson);
      expect(result.success, true);
      expect(result.migratedCount, 42);
      expect(result.backfilledKeys, ['trap']);
    });
  });

  group('ConfigEditorScreen Widget Tests', () {
    testWidgets('ConfigEditorScreen renders correctly and shows controls', (WidgetTester tester) async {
      final apiService = _MockConfigApiService();

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: ConfigEditorScreen(
              apiService: apiService,
              initialKind: 'game',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Verify Screen, Header, and Kind Selectors render
      expect(find.byType(ConfigEditorScreen), findsOneWidget);
      expect(find.text('Scouting Form Editor'), findsOneWidget);
      expect(find.text('Match'), findsOneWidget);
      expect(find.text('Pit'), findsOneWidget);
      expect(find.text('Qualitative'), findsOneWidget);
      expect(find.text('API Settings'), findsOneWidget);

      // Verify Mode Selector Buttons render
      expect(find.text('Visual Form Editor'), findsOneWidget);
      expect(find.text('Raw JSON'), findsOneWidget);
    });

    testWidgets('ConfigEditorScreen does not show phase selection when editing pit config', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apiService = _MockConfigApiService();

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: ConfigEditorScreen(
              apiService: apiService,
              initialKind: 'pit',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Ensure Add Field button is visible and tap it
      await tester.ensureVisible(find.text('Add Field'));
      await tester.tap(find.text('Add Field'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Phase dropdown should NOT be present in pit config add dialog
      expect(find.text('Phase'), findsNothing);
      expect(find.text('Type'), findsOneWidget);
    });

    testWidgets('ConfigEditorScreen does not show phase selection when editing qual config', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apiService = _MockConfigApiService();

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: ConfigEditorScreen(
              apiService: apiService,
              initialKind: 'qual',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Ensure Add Field button is visible and tap it
      await tester.ensureVisible(find.text('Add Field'));
      await tester.tap(find.text('Add Field'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Phase dropdown should NOT be present in qual config add dialog
      expect(find.text('Phase'), findsNothing);
      expect(find.text('Type'), findsOneWidget);
    });

    testWidgets('ConfigEditorScreen shows phase selection when editing match (game) config', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apiService = _MockConfigApiService();

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: ConfigEditorScreen(
              apiService: apiService,
              initialKind: 'game',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // Ensure Add Field button is visible and tap it
      await tester.ensureVisible(find.text('Add Field'));
      await tester.tap(find.text('Add Field'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      // Phase dropdown SHOULD be present in game config add dialog
      expect(find.text('Phase'), findsOneWidget);
      expect(find.text('Type'), findsOneWidget);
    });
  });

  group('DynamicFieldWidget Counter and Double Step Tests', () {
    testWidgets('renders standard counter when doubleStep is not configured', (WidgetTester tester) async {
      int? updatedValue;
      final field = ScoutingFieldModel(
        id: 'speaker',
        label: 'Speaker Score',
        type: 'counter',
        min: 0,
        max: 20,
        step: 1,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: DynamicFieldWidget(
              field: field,
              currentValue: 3,
              onChanged: (val) {
                updatedValue = val as int;
              },
            ),
          ),
        ),
      );

      expect(find.text('Speaker Score'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
      expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline), findsOneWidget);

      await tester.tap(find.byIcon(Icons.add_circle_outline));
      await tester.pump();
      expect(updatedValue, 4);

      await tester.tap(find.byIcon(Icons.remove_circle_outline));
      await tester.pump();
      expect(updatedValue, 2);
    });

    testWidgets('renders 4 double-step buttons when doubleStep is configured', (WidgetTester tester) async {
      int? updatedValue;
      final field = ScoutingFieldModel(
        id: 'coral',
        label: 'Coral Scored',
        type: 'counter',
        min: 0,
        max: 30,
        step: 1,
        doubleStep: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: DynamicFieldWidget(
              field: field,
              currentValue: 10,
              onChanged: (val) {
                updatedValue = val as int;
              },
            ),
          ),
        ),
      );

      expect(find.text('Coral Scored'), findsOneWidget);
      expect(find.text('10'), findsOneWidget);
      expect(find.text('-5'), findsOneWidget);
      expect(find.text('-1'), findsOneWidget);
      expect(find.text('+1'), findsOneWidget);
      expect(find.text('+5'), findsOneWidget);

      // Tap +5
      await tester.tap(find.text('+5'));
      await tester.pump();
      expect(updatedValue, 15);

      // Tap -5
      await tester.tap(find.text('-5'));
      await tester.pump();
      expect(updatedValue, 5);

      // Tap +1
      await tester.tap(find.text('+1'));
      await tester.pump();
      expect(updatedValue, 11);

      // Tap -1
      await tester.tap(find.text('-1'));
      await tester.pump();
      expect(updatedValue, 9);
    });

    testWidgets('clamps to min and max when doubleStep exceeds bounds', (WidgetTester tester) async {
      int? updatedValue;
      final field = ScoutingFieldModel(
        id: 'coral',
        label: 'Coral Scored',
        type: 'counter',
        min: 0,
        max: 12,
        step: 1,
        doubleStep: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: DynamicFieldWidget(
              field: field,
              currentValue: 10,
              onChanged: (val) {
                updatedValue = val as int;
              },
            ),
          ),
        ),
      );

      // 10 + 5 would exceed max 12 -> should clamp to 12
      await tester.tap(find.text('+5'));
      await tester.pump();
      expect(updatedValue, 12);
    });

    testWidgets('enables increment buttons even if max is not set or 0', (WidgetTester tester) async {
      int? updatedValue;
      final field = ScoutingFieldModel(
        id: 'autoFuel',
        label: 'Auto Fuel',
        type: 'counter',
        min: 0,
        max: 0, // max is 0 or not set
        step: 1,
        doubleStep: 5,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: DynamicFieldWidget(
              field: field,
              currentValue: 0,
              onChanged: (val) {
                updatedValue = val as int;
              },
            ),
          ),
        ),
      );

      // Increment buttons should be enabled
      await tester.tap(find.text('+1'));
      await tester.pump();
      expect(updatedValue, 1);

      await tester.tap(find.text('+5'));
      await tester.pump();
      expect(updatedValue, 5);
    });

    testWidgets('renders text as static display and textarea as input field', (WidgetTester tester) async {
      String? updatedTextarea;

      final textField = ScoutingFieldModel(
        id: 'driverComments',
        label: 'Driver Instructions & Notice',
        placeholder: 'Ensure intake is raised before parking',
        type: 'text',
        phase: 'teleop',
      );

      final textareaField = ScoutingFieldModel(
        id: 'robotNotes',
        label: 'Robot Notes',
        type: 'textarea',
        phase: 'teleop',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: Column(
              children: [
                DynamicFieldWidget(
                  field: textField,
                  currentValue: null,
                  onChanged: (val) {},
                ),
                DynamicFieldWidget(
                  field: textareaField,
                  currentValue: 'Initial Area',
                  onChanged: (val) => updatedTextarea = val.toString(),
                ),
              ],
            ),
          ),
        ),
      );

      // Text field is a static display
      expect(find.text('Driver Instructions & Notice'), findsOneWidget);
      expect(find.text('Ensure intake is raised before parking'), findsOneWidget);
      expect(find.byKey(const ValueKey('text_static_driverComments')), findsOneWidget);
      // No editable text input for static text
      expect(find.byKey(const ValueKey('text_driverComments')), findsNothing);

      // Textarea is an editable input field
      expect(find.text('Robot Notes'), findsOneWidget);
      expect(find.text('Initial Area'), findsOneWidget);
      expect(find.byKey(const ValueKey('textarea_robotNotes')), findsOneWidget);

      await tester.enterText(find.byKey(const ValueKey('textarea_robotNotes')), 'Great defense and intake');
      expect(updatedTextarea, 'Great defense and intake');
    });
  });

  group('API Settings Model and UI Tests', () {
    test('AppSettingsModel and ApiKeysModel serialize and deserialize accurately', () {
      final settings = AppSettingsModel(
        year: 2026,
        eventCode: 'nytr',
        eventKey: '2026nytr',
        timezone: 'America/New_York',
        preferredSource: 'tba',
        chatEnabled: true,
        useStatboticsEpa: true,
        useTbaOpr: true,
        apiKeys: ApiKeysModel(
          tbaKey: 'sample_tba_key_123',
          firstUsername: 'sample_user',
          firstKey: 'sample_first_key_456',
        ),
        statboticsBaseUrl: 'https://api.statbotics.io',
      );

      final json = settings.toJson();
      expect(json['year'], 2026);
      expect(json['eventCode'], 'nytr');
      expect(json['eventKey'], '2026nytr');
      expect(json['preferredSource'], 'tba');
      expect(json['useStatboticsEpa'], true);
      expect(json['useTbaOpr'], true);
      expect(json['statboticsBaseUrl'], 'https://api.statbotics.io');
      expect(json['apiKeys']['tbaKey'], 'sample_tba_key_123');
      expect(json['apiKeys']['firstUsername'], 'sample_user');
      expect(json['apiKeys']['firstKey'], 'sample_first_key_456');

      final deserialized = AppSettingsModel.fromJson(json);
      expect(deserialized.year, 2026);
      expect(deserialized.eventCode, 'nytr');
      expect(deserialized.eventKey, '2026nytr');
      expect(deserialized.apiKeys.tbaKey, 'sample_tba_key_123');
      expect(deserialized.apiKeys.firstUsername, 'sample_user');
      expect(deserialized.apiKeys.firstKey, 'sample_first_key_456');
    });

    testWidgets('ConfigEditorScreen renders API Settings tab and allows editing and saving', (WidgetTester tester) async {
      tester.view.physicalSize = const Size(1200, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final apiService = _MockConfigApiService();

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: Scaffold(
            body: ConfigEditorScreen(
              apiService: apiService,
              initialKind: 'api',
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Check API Settings UI elements
      expect(find.text('Event & Season Configuration'), findsOneWidget);
      expect(find.text('The Blue Alliance (TBA)'), findsOneWidget);
      expect(find.text('FIRST API'), findsOneWidget);
      expect(find.text('Statbotics API'), findsOneWidget);
      expect(find.text('Save API Settings'), findsOneWidget);

      // Verify initial values
      expect(find.text('2026'), findsOneWidget);
      expect(find.text('nytr'), findsOneWidget);

      // Test connection button
      expect(find.text('Test Connection'), findsOneWidget);
      await tester.tap(find.text('Test Connection'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Test FIRST API button
      expect(find.text('Test FIRST API'), findsOneWidget);
      await tester.tap(find.text('Test FIRST API'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Save settings
      await tester.tap(find.text('Save API Settings'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(apiService.mockSettings.eventCode, 'nytr');
    });
  });
}
