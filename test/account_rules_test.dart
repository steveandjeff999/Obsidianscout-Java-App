import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/account_rules.dart';
import 'package:obsidianscout_app/models/config_models.dart';

void main() {
  group('AccountRules (mirrors server validation)', () {
    test('passwords need at least 8 characters', () {
      expect(AccountRules.validatePassword(null), isNotNull);
      expect(AccountRules.validatePassword(''), isNotNull);
      expect(AccountRules.validatePassword('1234567'), contains('8'));
      expect(AccountRules.validatePassword('12345678'), isNull);
    });

    test('usernames reject path, markup and control characters', () {
      for (final bad in ['', '   ', '../5455/alice', 'a/b', r'a\b', '<img>', 'x\u0000y', '..', 'a:b', 'a|b', 'a`b']) {
        expect(AccountRules.validateUsername(bad), isNotNull, reason: 'should reject "$bad"');
      }
      expect(AccountRules.validateUsername('x' * 65), isNotNull);
    });

    test('usernames allow spaces and ordinary punctuation', () {
      for (final ok in ['Seth Herod', 'scout_1', 'team-lead', "o'brien", 'a.b']) {
        expect(AccountRules.validateUsername(ok), isNull, reason: 'should allow "$ok"');
      }
    });
  });

  group('AppSettingsModel.selfRegisterRoles', () {
    test('parses roles from the server and sends them back', () {
      final model = AppSettingsModel.fromJson({
        'settings': {'registrationLocked': false, 'selfRegisterRoles': ['scout', 'ADMIN']},
      });
      expect(model.selfRegisterRoles, ['SCOUT', 'ADMIN']);
      expect(model.toJson()['selfRegisterRoles'], ['SCOUT', 'ADMIN']);
    });

    test('older servers without the field: value stays null and is not sent', () {
      final model = AppSettingsModel.fromJson({
        'settings': {'registrationLocked': true},
      });
      expect(model.selfRegisterRoles, isNull);
      expect(model.toJson().containsKey('selfRegisterRoles'), isFalse);
    });

    test('copyWith keeps or replaces the roles', () {
      final model = AppSettingsModel.fromJson({
        'settings': {'selfRegisterRoles': ['ADMIN', 'ANALYTICS', 'SCOUT']},
      });
      expect(model.copyWith(chatEnabled: false).selfRegisterRoles, ['ADMIN', 'ANALYTICS', 'SCOUT']);
      expect(model.copyWith(selfRegisterRoles: ['SCOUT']).selfRegisterRoles, ['SCOUT']);
    });
  });

  group('UserModel.canEdit', () {
    test('admins can only edit users on their own team and program', () {
      final admin = UserModel.fromJson({'id': 'a', 'username': 'lead', 'teamNumber': 1234, 'program': 'FRC', 'role': 'ADMIN'});
      final sameTeam = UserModel.fromJson({'id': 'b', 'username': 's1', 'teamNumber': 1234, 'program': 'FRC', 'role': 'SCOUT'});
      final otherProgram = UserModel.fromJson({'id': 'c', 'username': 's2', 'teamNumber': 1234, 'program': 'FTC', 'role': 'SCOUT'});
      expect(admin.canEdit(sameTeam), isTrue);
      expect(admin.canEdit(otherProgram), isFalse);
    });
  });
}
