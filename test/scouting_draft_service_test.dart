import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/data/local_store.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/services/scouting_draft_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalStore.debugForcePrefsBackend = true;
  });

  tearDown(() {
    LocalStore.instance.resetForTesting();
  });

  group('ScoutingDraftService - hasMeaningfulData', () {
    test('returns false for empty or metadata-only data', () {
      expect(ScoutingDraftService.hasMeaningfulData({}), isFalse);
      expect(
        ScoutingDraftService.hasMeaningfulData({
          'eventKey': '2026cmp',
          'matchKey': '2026cmp_qm1',
          'matchNumber': 1,
          'targetTeamNumber': 254,
          '_internalState': 'xyz',
        }),
        isFalse,
      );
    });

    test('detects meaningful generic changes without config', () {
      expect(ScoutingDraftService.hasMeaningfulData({'auto_coral': 1}), isTrue);
      expect(ScoutingDraftService.hasMeaningfulData({'climb': true}), isTrue);
      expect(ScoutingDraftService.hasMeaningfulData({'notes': 'Defensive robot'}), isTrue);
      expect(ScoutingDraftService.hasMeaningfulData({'zones': ['left', 'center']}), isTrue);

      // Blank/Zero entries
      expect(ScoutingDraftService.hasMeaningfulData({'auto_coral': 0}), isFalse);
      expect(ScoutingDraftService.hasMeaningfulData({'climb': false}), isFalse);
      expect(ScoutingDraftService.hasMeaningfulData({'notes': '   '}), isFalse);
      expect(ScoutingDraftService.hasMeaningfulData({'zones': []}), isFalse);
    });

    test('respects config default values', () {
      final config = ScoutingConfigModel(
        title: 'FRC 2026',
        fields: [
          ScoutingFieldModel(id: 'counter_1', label: 'Counter', type: 'counter', defaultValue: 0),
          ScoutingFieldModel(id: 'rating_1', label: 'Rating', type: 'rating', defaultValue: 1, min: 1),
          ScoutingFieldModel(id: 'toggle_1', label: 'Toggle', type: 'boolean', defaultValue: false),
          ScoutingFieldModel(id: 'dropdown_1', label: 'Select', type: 'select', defaultValue: 'A', options: [
            ScoutingOptionModel(label: 'Option A', value: 'A'),
            ScoutingOptionModel(label: 'Option B', value: 'B'),
          ]),
        ],
      );

      // All at defaults -> not meaningful
      expect(
        ScoutingDraftService.hasMeaningfulData({
          'counter_1': 0,
          'rating_1': 1,
          'toggle_1': false,
          'dropdown_1': 'A',
        }, config),
        isFalse,
      );

      // Modifying counter -> meaningful
      expect(
        ScoutingDraftService.hasMeaningfulData({
          'counter_1': 2,
          'rating_1': 1,
          'toggle_1': false,
          'dropdown_1': 'A',
        }, config),
        isTrue,
      );

      // Modifying rating -> meaningful
      expect(
        ScoutingDraftService.hasMeaningfulData({
          'counter_1': 0,
          'rating_1': 4,
          'toggle_1': false,
          'dropdown_1': 'A',
        }, config),
        isTrue,
      );

      // Modifying toggle -> meaningful
      expect(
        ScoutingDraftService.hasMeaningfulData({
          'counter_1': 0,
          'rating_1': 1,
          'toggle_1': true,
          'dropdown_1': 'A',
        }, config),
        isTrue,
      );

      // Modifying dropdown -> meaningful
      expect(
        ScoutingDraftService.hasMeaningfulData({
          'counter_1': 0,
          'rating_1': 1,
          'toggle_1': false,
          'dropdown_1': 'B',
        }, config),
        isTrue,
      );
    });
  });

  group('ScoutingDraftService - save, load and clear lifecycle', () {
    test('saves and loads a match draft with metadata', () async {
      await ScoutingDraftService.saveDraft(
        formType: 'match',
        data: {'teleop_points': 14, 'driver_skill': 5},
        teamNumber: 1678,
        matchKey: '2026casf_qm12',
        matchNumber: 12,
        eventKey: '2026casf',
      );

      final loaded = await ScoutingDraftService.loadDraft('match');
      expect(loaded, isNotNull);
      expect(loaded!.formType, 'match');
      expect(loaded.teamNumber, 1678);
      expect(loaded.matchKey, '2026casf_qm12');
      expect(loaded.matchNumber, 12);
      expect(loaded.eventKey, '2026casf');
      expect(loaded.data['teleop_points'], 14);
      expect(loaded.data['driver_skill'], 5);
      expect(loaded.contextDescription(), 'QM12 · Team 1678');
      expect(loaded.ageDescription(), 'just now');

      // Clear draft
      await ScoutingDraftService.clearDraft('match');
      final cleared = await ScoutingDraftService.loadDraft('match');
      expect(cleared, isNull);
    });

    test('auto-clears draft if saved with empty data and no selections', () async {
      await ScoutingDraftService.saveDraft(
        formType: 'match',
        data: {'teleop_points': 10},
        teamNumber: 254,
      );
      expect(await ScoutingDraftService.loadDraft('match'), isNotNull);

      // Save again with blank/zero data and null team
      await ScoutingDraftService.saveDraft(
        formType: 'match',
        data: {'teleop_points': 0},
        teamNumber: null,
      );
      expect(await ScoutingDraftService.loadDraft('match'), isNull);
    });

    test('saves and loads pit draft independently from match draft', () async {
      await ScoutingDraftService.saveDraft(
        formType: 'pit',
        data: {'drivetrain': 'Swerve', 'weight_lbs': 115},
        teamNumber: 254,
        eventKey: '2026casf',
      );

      final pitDraft = await ScoutingDraftService.loadDraft('pit');
      final matchDraft = await ScoutingDraftService.loadDraft('match');

      expect(pitDraft, isNotNull);
      expect(pitDraft!.formType, 'pit');
      expect(pitDraft.teamNumber, 254);
      expect(pitDraft.contextDescription(), 'Team 254');
      expect(pitDraft.data['drivetrain'], 'Swerve');
      expect(matchDraft, isNull);

      await ScoutingDraftService.clearDraft('pit');
      expect(await ScoutingDraftService.loadDraft('pit'), isNull);
    });
  });
}
