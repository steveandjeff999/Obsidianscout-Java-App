import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/app_update_service.dart';

void main() {
  group('AppUpdateService.compareVersions', () {
    test('orders four-part release versions numerically', () {
      expect(AppUpdateService.compareVersions('1.2.0.10', '1.2.0.9'), greaterThan(0));
      expect(AppUpdateService.compareVersions('1.2.0.9', '1.2.1.0'), lessThan(0));
      expect(AppUpdateService.compareVersions('1.2.0.9', '1.2.0.9'), 0);
    });

    test('treats missing parts as zero and ignores build suffixes', () {
      expect(AppUpdateService.compareVersions('1.2.1', '1.2.1.0'), 0);
      expect(AppUpdateService.compareVersions('1.2.1+1210', '1.2.1.1'), lessThan(0));
      expect(AppUpdateService.compareVersions('v1.3.0.0', '1.2.9.9'), greaterThan(0));
    });
  });
}
