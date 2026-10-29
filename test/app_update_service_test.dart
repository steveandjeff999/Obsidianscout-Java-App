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

  group('AppUpdateService.pickAsset', () {
    final assets = [
      'app-release.apk',
      'checksums.txt',
      'ObsidianScout-Linux.tar.gz',
      'ObsidianScout-MicrosoftStore-UploadOnly-DoNotInstall.zip',
      'ObsidianScout-WinArm64-MSIX-Bundle.zip',
      'ObsidianScout-WinArm64-Portable.zip',
      'ObsidianScout-Windows-MSIX-Bundle.zip',
      'ObsidianScout-Windows-Portable.zip',
    ].map((name) => {'name': name}).toList();

    String? pick(AppInstallSource source, {bool arm64 = false}) =>
        AppUpdateService.pickAsset(assets, source, arm64: arm64)?['name'] as String?;

    test('x64 Windows installs get the x64 packages', () {
      expect(pick(AppInstallSource.githubMsix), 'ObsidianScout-Windows-MSIX-Bundle.zip');
      expect(pick(AppInstallSource.githubPortable), 'ObsidianScout-Windows-Portable.zip');
    });

    test('ARM64 Windows installs get the ARM64 packages', () {
      expect(pick(AppInstallSource.githubMsix, arm64: true), 'ObsidianScout-WinArm64-MSIX-Bundle.zip');
      expect(pick(AppInstallSource.githubPortable, arm64: true), 'ObsidianScout-WinArm64-Portable.zip');
    });

    test('a Store MSIX in the release is never picked', () {
      final withStore = [
        {'name': 'ObsidianScout-Store-1.2.11.0.msix'},
        ...assets,
      ];
      expect(
        AppUpdateService.pickAsset(withStore, AppInstallSource.githubMsix)?['name'],
        'ObsidianScout-Windows-MSIX-Bundle.zip',
      );
    });

    test('Android gets the APK and stores get nothing', () {
      expect(pick(AppInstallSource.githubApk), 'app-release.apk');
      expect(pick(AppInstallSource.store), isNull);
    });
  });
}
