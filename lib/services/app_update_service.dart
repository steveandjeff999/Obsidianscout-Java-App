import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'app_update_io.dart'
    if (dart.library.html) 'app_update_web.dart' as platform_updater;

/// Where this copy of the app came from. Store installs are updated by their store; only copies
/// installed from a GitHub release asset update themselves.
enum AppInstallSource { store, githubApk, githubMsix, githubPortable, unsupported }

/// A GitHub release newer than the installed app, with the asset for this install's platform.
class AppUpdateInfo {
  final String tag;
  final String version;
  final String assetName;
  final String downloadUrl;
  final int size;
  final String notes;
  final String releaseUrl;
  final AppInstallSource source;

  const AppUpdateInfo({
    required this.tag,
    required this.version,
    required this.assetName,
    required this.downloadUrl,
    required this.size,
    required this.notes,
    required this.releaseUrl,
    required this.source,
  });
}

enum AppUpdateInstallStatus { started, needsPermission, failed }

class AppUpdateInstallResult {
  final AppUpdateInstallStatus status;
  final String? message;

  const AppUpdateInstallResult(this.status, [this.message]);
}

/// Checks GitHub releases for a newer build of a sideloaded install, downloads its package and
/// opens the platform installer. Downloaded packages are deleted once the new version runs.
class AppUpdateService {
  AppUpdateService._();
  static final AppUpdateService instance = AppUpdateService._();

  static const String repo = 'steveandjeff999/Obsidianscout-Java-App';
  static const String releasesUrl = 'https://github.com/$repo/releases';

  /// Release version this build was made from (e.g. 1.2.0.9), set by CI with
  /// --dart-define=OBSIDIAN_RELEASE_VERSION. Empty for local and debug builds, which never self-update.
  static const String installedVersion = String.fromEnvironment('OBSIDIAN_RELEASE_VERSION');

  // GitHub allows 60 unauthenticated API calls an hour per IP, and a team often shares one venue
  // network, so the latest release is cached between checks.
  static const Duration _checkInterval = Duration(hours: 4);
  static const String _lastCheckKey = 'app_update.last_check';
  static const String _cachedReleaseKey = 'app_update.cached_release';
  static const String _pendingKey = 'app_update.pending';

  AppInstallSource? _source;
  bool _checkedThisLaunch = false;

  Future<AppInstallSource> installSource() async {
    if (_source != null) return _source!;
    try {
      _source = await platform_updater.detectInstallSource();
    } catch (e) {
      debugPrint('[AppUpdate] Install source check failed: $e');
      _source = AppInstallSource.unsupported;
    }
    return _source!;
  }

  /// Runs once per launch: removes packages from an update that has since installed, then returns
  /// the newer release if this is a GitHub install and one exists.
  Future<AppUpdateInfo?> checkOnLaunch() async {
    if (_checkedThisLaunch) return null;
    _checkedThisLaunch = true;
    await _cleanUpInstalledUpdate();
    return checkForUpdate();
  }

  Future<AppUpdateInfo?> checkForUpdate({bool force = false}) async {
    if (kDebugMode || installedVersion.isEmpty) return null;
    final source = await installSource();
    if (source == AppInstallSource.store || source == AppInstallSource.unsupported) return null;

    final release = await _latestRelease(force: force);
    if (release == null) return null;

    final tag = release['tag_name']?.toString() ?? '';
    final version = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (compareVersions(version, installedVersion) <= 0) return null;

    final assets = (release['assets'] as List? ?? const []).whereType<Map>().toList();
    final asset = _pickAsset(assets, source);
    if (asset == null) {
      debugPrint('[AppUpdate] Release $tag has no package for $source');
      return null;
    }

    return AppUpdateInfo(
      tag: tag,
      version: version,
      assetName: asset['name'].toString(),
      downloadUrl: asset['browser_download_url'].toString(),
      size: (asset['size'] as num?)?.toInt() ?? 0,
      notes: release['body']?.toString() ?? '',
      releaseUrl: release['html_url']?.toString() ?? releasesUrl,
      source: source,
    );
  }

  /// Downloads the update package, reusing a finished download of the same release.
  Future<String> download(
    AppUpdateInfo update, {
    void Function(int received, int total)? onProgress,
  }) async {
    final path = await platform_updater.downloadPackage(update, onProgress: onProgress);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _pendingKey,
      jsonEncode({'version': update.version, 'dir': platform_updater.packageDirOf(path)}),
    );
    return path;
  }

  /// Opens the platform installer for a downloaded package. On Windows the app then closes so its
  /// files can be replaced.
  Future<AppUpdateInstallResult> install(AppUpdateInfo update, String packagePath) {
    return platform_updater.launchInstaller(update, packagePath);
  }

  Future<void> _cleanUpInstalledUpdate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_pendingKey);
      if (raw == null) return;
      final pending = jsonDecode(raw) as Map<String, dynamic>;
      final version = pending['version']?.toString() ?? '';
      // Keep the package while the update hasn't installed yet, so a retry needn't download it again.
      if (installedVersion.isNotEmpty && compareVersions(installedVersion, version) < 0) return;
      final dir = pending['dir']?.toString();
      if (dir != null && dir.isNotEmpty) await platform_updater.deletePackageDir(dir);
      await prefs.remove(_pendingKey);
    } catch (e) {
      debugPrint('[AppUpdate] Cleanup failed: $e');
    }
  }

  Future<Map<String, dynamic>?> _latestRelease({required bool force}) async {
    final prefs = await SharedPreferences.getInstance();
    final lastCheck = DateTime.fromMillisecondsSinceEpoch(prefs.getInt(_lastCheckKey) ?? 0);
    final cached = prefs.getString(_cachedReleaseKey);
    if (!force && cached != null && DateTime.now().difference(lastCheck) < _checkInterval) {
      try {
        return jsonDecode(cached) as Map<String, dynamic>;
      } catch (_) {}
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.github.com/repos/$repo/releases/latest'),
        headers: const {'Accept': 'application/vnd.github+json', 'User-Agent': 'ObsidianScout-App'},
      ).timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        debugPrint('[AppUpdate] GitHub returned ${response.statusCode}');
        return cached != null ? jsonDecode(cached) as Map<String, dynamic> : null;
      }
      final json = jsonDecode(response.body) as Map<String, dynamic>;
      // Keep only what the check needs; full release payloads are large.
      final slim = <String, dynamic>{
        'tag_name': json['tag_name'],
        'html_url': json['html_url'],
        'body': json['body'],
        'assets': [
          for (final a in (json['assets'] as List? ?? const []).whereType<Map>())
            {'name': a['name'], 'size': a['size'], 'browser_download_url': a['browser_download_url']},
        ],
      };
      await prefs.setString(_cachedReleaseKey, jsonEncode(slim));
      await prefs.setInt(_lastCheckKey, DateTime.now().millisecondsSinceEpoch);
      return slim;
    } catch (e) {
      debugPrint('[AppUpdate] Release check failed: $e');
      return null;
    }
  }

  static Map? _pickAsset(List<Map> assets, AppInstallSource source) {
    Map? find(bool Function(String name) test) {
      for (final a in assets) {
        if (test(a['name']?.toString().toLowerCase() ?? '')) return a;
      }
      return null;
    }

    switch (source) {
      case AppInstallSource.githubApk:
        return find((n) => n == 'app-release.apk') ?? find((n) => n.endsWith('.apk'));
      case AppInstallSource.githubMsix:
        return find((n) => n.endsWith('.msix')) ??
            find((n) => n.endsWith('.zip') && n.contains('windows') && n.contains('msix'));
      case AppInstallSource.githubPortable:
        return find((n) => n.endsWith('.zip') && n.contains('windows') && n.contains('portable'));
      case AppInstallSource.store:
      case AppInstallSource.unsupported:
        return null;
    }
  }

  /// Compares dotted versions part by part (1.2.0.10 > 1.2.0.9; missing parts count as 0; a +build
  /// suffix is ignored).
  static int compareVersions(String a, String b) {
    List<int> parts(String v) => v
        .split('+')
        .first
        .split('.')
        .map((p) => int.tryParse(p.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0)
        .toList();
    final pa = parts(a);
    final pb = parts(b);
    for (var i = 0; i < pa.length || i < pb.length; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x.compareTo(y);
    }
    return 0;
  }
}
