import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/config_models.dart';
import 'package:obsidianscout_app/models/predictor_models.dart';

void main() {
  test('recency bias round-trips through settings JSON', () {
    final settings = AppSettingsModel.fromJson({
      'settings': {
        'year': 2026,
        'recencyBias': {
          'enabled': true,
          'mode': 'lastN',
          'halfLifeMatches': 3.5,
          'windowSize': 5,
          'minMatches': 3,
          'prescoutWeight': 0.25,
        },
      },
    });

    final r = settings.recencyBias!;
    expect(r.enabled, isTrue);
    expect(r.mode, RecencyBiasSettingsModel.modeLastN);
    expect(r.windowSize, 5);
    expect(settings.toJson()['recencyBias'], r.toJson());
  });

  test('missing recency bias stays null and is not sent on save', () {
    final settings = AppSettingsModel.fromJson({'settings': {'year': 2026}});
    expect(settings.recencyBias, isNull);
    expect(settings.toJson().containsKey('recencyBias'), isFalse);
  });

  test('values are clamped like the server', () {
    final r = RecencyBiasSettingsModel.fromJson({
      'mode': 'bogus',
      'halfLifeMatches': 0,
      'windowSize': 500,
      'minMatches': -2,
      'prescoutWeight': 3,
    });
    expect(r.mode, RecencyBiasSettingsModel.modeExponential);
    expect(r.halfLifeMatches, 1.0);
    expect(r.windowSize, 30);
    expect(r.minMatches, 1);
    expect(r.prescoutWeight, 1.0);
  });

  test('weight preview matches the server formula', () {
    const exp = RecencyBiasSettingsModel(halfLifeMatches: 2);
    expect(exp.weightForAge(0), 1.0);
    expect(exp.weightForAge(2), closeTo(0.5, 1e-9));
    const lastN = RecencyBiasSettingsModel(mode: RecencyBiasSettingsModel.modeLastN, windowSize: 3);
    expect(lastN.weightForAge(2), 1.0);
    expect(lastN.weightForAge(3), 0.0);
  });

  test('predictions parse the recency-weighted flag', () {
    final t = MatchTeamPrediction.fromJson({'teamNumber': 254, 'recencyWeighted': true});
    expect(t.recencyWeighted, isTrue);
    expect(MatchTeamPrediction.fromJson({'teamNumber': 254}).recencyWeighted, isFalse);
  });
}
