import 'app_update_service.dart';

// The web app is always served current, so there is nothing to update.

Future<AppInstallSource> detectInstallSource() async => AppInstallSource.unsupported;

Future<String> downloadPackage(
  AppUpdateInfo update, {
  void Function(int received, int total)? onProgress,
}) {
  throw UnsupportedError('App updates are not available on web');
}

String packageDirOf(String packagePath) => '';

Future<AppUpdateInstallResult> launchInstaller(AppUpdateInfo update, String packagePath) async =>
    const AppUpdateInstallResult(AppUpdateInstallStatus.failed, 'Not available on web');

Future<void> deletePackageDir(String dir) async {}
