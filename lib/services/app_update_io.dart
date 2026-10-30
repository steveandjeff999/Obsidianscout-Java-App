import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'app_update_service.dart';

const MethodChannel _channel = MethodChannel('obsidianscout/app_update');

/// Installer package names of app stores. Anything else (a browser, file manager, the system
/// package installer, adb) means the APK was sideloaded.
const Set<String> _androidStores = {
  'com.android.vending', // Google Play
  'com.google.android.feedback', // Google Play (older devices)
  'com.amazon.venezia', // Amazon Appstore
  'com.sec.android.app.samsungapps', // Galaxy Store
  'com.huawei.appmarket', // AppGallery
};

/// Folder names the update packages live under; deletes are limited to these.
const String _windowsFolder = 'ObsidianScout-Update';
const String _androidFolder = 'app_update';

Future<AppInstallSource> detectInstallSource() async {
  if (Platform.isAndroid) {
    final installer = await _channel.invokeMethod<String>('installerPackage');
    debugPrint('[AppUpdate] Installed by: ${installer ?? 'unknown'}');
    return _androidStores.contains(installer) ? AppInstallSource.store : AppInstallSource.githubApk;
  }
  if (Platform.isWindows) return _windowsInstallSource();
  return AppInstallSource.unsupported;
}

/// Whether this is a Windows ARM64 build (an x64 build running under emulation on ARM reports x64).
bool isArm64Build() => Abi.current() == Abi.windowsArm64;

typedef _GetCurrentPackageFullNameNative = Int32 Function(Pointer<Uint32> length, Pointer<Utf16> name);
typedef _GetCurrentPackageFullName = int Function(Pointer<Uint32> length, Pointer<Utf16> name);
typedef _GetStagedPackageOriginNative = Int32 Function(Pointer<Utf16> fullName, Pointer<Int32> origin);
typedef _GetStagedPackageOrigin = int Function(Pointer<Utf16> fullName, Pointer<Int32> origin);

/// An unpackaged exe is the portable zip; a packaged one is an MSIX, from the Microsoft Store or
/// sideloaded from GitHub depending on its PackageOrigin.
AppInstallSource _windowsInstallSource() {
  const errorInsufficientBuffer = 122;
  const appModelErrorNoPackage = 15700;
  const packageOriginInbox = 2;
  const packageOriginStore = 3;

  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final getFullName = kernel32
      .lookupFunction<_GetCurrentPackageFullNameNative, _GetCurrentPackageFullName>('GetCurrentPackageFullName');
  final length = calloc<Uint32>();
  Pointer<Utf16> name = nullptr;
  final origin = calloc<Int32>();
  try {
    final probe = getFullName(length, nullptr);
    if (probe == appModelErrorNoPackage) return AppInstallSource.githubPortable;
    if (probe != errorInsufficientBuffer) return AppInstallSource.unsupported;

    name = calloc<Uint16>(length.value).cast<Utf16>();
    if (getFullName(length, name) != 0) return AppInstallSource.unsupported;
    debugPrint('[AppUpdate] Package: ${name.toDartString()}');

    final getOrigin = kernel32
        .lookupFunction<_GetStagedPackageOriginNative, _GetStagedPackageOrigin>('GetStagedPackageOrigin');
    // If the origin can't be read, don't offer an update: it may be a Store install.
    if (getOrigin(name, origin) != 0) return AppInstallSource.unsupported;
    debugPrint('[AppUpdate] Package origin: ${origin.value}');
    return origin.value == packageOriginStore || origin.value == packageOriginInbox
        ? AppInstallSource.store
        : AppInstallSource.githubMsix;
  } finally {
    calloc.free(length);
    calloc.free(origin);
    if (name != nullptr) calloc.free(name);
  }
}

Future<Directory> _updatesRoot() async {
  if (Platform.isWindows) {
    // An MSIX app's writes to AppData (including Temp) go to a private copy that App Installer
    // can't see, so Windows packages are downloaded to Downloads instead.
    final downloads = await getDownloadsDirectory();
    if (downloads != null) return Directory('${downloads.path}\\$_windowsFolder');
    return Directory('${(await getTemporaryDirectory()).path}\\$_windowsFolder');
  }
  // The app's cache dir; must match the cache-path in android/app/src/main/res/xml/update_file_paths.xml.
  return Directory('${(await getTemporaryDirectory()).path}/$_androidFolder');
}

Future<String> downloadPackage(
  AppUpdateInfo update, {
  void Function(int received, int total)? onProgress,
}) async {
  final root = await _updatesRoot();
  final sep = Platform.pathSeparator;
  final safeTag = update.tag.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final safeAssetName = update.assetName.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
  final dir = Directory('${root.path}$sep$safeTag');
  final file = File('${dir.path}$sep$safeAssetName');

  if (await file.exists() && (update.size == 0 || await file.length() == update.size)) {
    onProgress?.call(update.size, update.size);
    return file.path;
  }

  // Packages from older releases are no longer needed.
  if (await root.exists()) {
    await for (final entry in root.list()) {
      if (entry is Directory && entry.path != dir.path) {
        try {
          await entry.delete(recursive: true);
        } catch (_) {}
      }
    }
  }
  await dir.create(recursive: true);

  final part = File('${file.path}.part');
  final client = http.Client();
  try {
    final response = await client.send(http.Request('GET', Uri.parse(update.downloadUrl)));
    if (response.statusCode != 200) {
      throw HttpException('Download failed (HTTP ${response.statusCode})');
    }
    final total = response.contentLength ?? update.size;
    var received = 0;
    final sink = part.openWrite();
    try {
      await for (final chunk in response.stream) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
    } finally {
      await sink.close();
    }
    if (update.size > 0 && received != update.size) {
      throw const HttpException('Download was interrupted. Please try again.');
    }
    if (await file.exists()) await file.delete();
    await part.rename(file.path);
    return file.path;
  } catch (_) {
    try {
      if (await part.exists()) await part.delete();
    } catch (_) {}
    rethrow;
  } finally {
    client.close();
  }
}

String packageDirOf(String packagePath) => File(packagePath).parent.path;

Future<void> deletePackageDir(String dir) async {
  final target = Directory(dir);
  final root = target.parent;
  final rootName = root.uri.pathSegments.where((s) => s.isNotEmpty).lastOrNull;
  if (rootName != _windowsFolder && rootName != _androidFolder) return;
  if (await target.exists()) await target.delete(recursive: true);
  if (await root.exists() && await root.list().isEmpty) await root.delete();
}

Future<AppUpdateInstallResult> launchInstaller(AppUpdateInfo update, String packagePath) async {
  try {
    switch (update.source) {
      case AppInstallSource.githubApk:
        final status = await _channel.invokeMethod<String>('installApk', {'path': packagePath});
        return status == 'needs_permission'
            ? const AppUpdateInstallResult(AppUpdateInstallStatus.needsPermission)
            : const AppUpdateInstallResult(AppUpdateInstallStatus.started);
      case AppInstallSource.githubMsix:
        return await _installMsix(packagePath);
      case AppInstallSource.githubPortable:
        return await _installPortable(packagePath);
      case AppInstallSource.store:
      case AppInstallSource.unsupported:
        return const AppUpdateInstallResult(AppUpdateInstallStatus.failed, 'This install updates through its store.');
    }
  } catch (e) {
    debugPrint('[AppUpdate] Install failed: $e');
    return AppUpdateInstallResult(AppUpdateInstallStatus.failed, e.toString());
  }
}

Future<AppUpdateInstallResult> _installMsix(String packagePath) async {
  var msixPath = packagePath;
  if (packagePath.toLowerCase().endsWith('.zip')) {
    // Releases ship the MSIX inside a zip with its certificate.
    final outDir = Directory('${packageDirOf(packagePath)}\\msix');
    if (await outDir.exists()) await outDir.delete(recursive: true);
    await extractFileToDisk(packagePath, outDir.path);
    final msix = outDir
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.toLowerCase().endsWith('.msix'))
        .firstOrNull;
    if (msix == null) {
      return const AppUpdateInstallResult(AppUpdateInstallStatus.failed, 'The download has no .msix installer.');
    }
    msixPath = msix.path;
  }
  // Opens App Installer, which shows the update. The app closes so its files aren't in use.
  await Process.start('explorer.exe', [msixPath]);
  _exitSoon();
  return const AppUpdateInstallResult(AppUpdateInstallStatus.started);
}

Future<AppUpdateInstallResult> _installPortable(String packagePath) async {
  final packageDir = packageDirOf(packagePath);
  final extracted = Directory('$packageDir\\portable');
  if (await extracted.exists()) await extracted.delete(recursive: true);
  await extractFileToDisk(packagePath, extracted.path);

  final exe = File(Platform.resolvedExecutable);
  final exeName = exe.uri.pathSegments.last.toLowerCase();
  // Use the folder holding the exe, in case the zip wraps the app in a folder.
  final newExe = extracted
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.uri.pathSegments.last.toLowerCase() == exeName)
      .firstOrNull;
  if (newExe == null) {
    return const AppUpdateInstallResult(AppUpdateInstallStatus.failed, 'The download has no app executable.');
  }

  final script = File('$packageDir\\apply-update.ps1');
  await script.writeAsString(_portableUpdateScript);
  await Process.start(
    'powershell.exe',
    [
      '-NoProfile',
      '-ExecutionPolicy',
      'Bypass',
      '-WindowStyle',
      'Hidden',
      '-File',
      script.path,
      '-ProcessId',
      '$pid',
      '-Source',
      newExe.parent.path,
      '-Target',
      exe.parent.path,
      '-Exe',
      exe.path,
      '-Cleanup',
      packageDir,
    ],
    mode: ProcessStartMode.detached,
  );
  _exitSoon();
  return const AppUpdateInstallResult(AppUpdateInstallStatus.started);
}

void _exitSoon() {
  Timer(const Duration(milliseconds: 1500), () => exit(0));
}

/// Waits for the app to close, copies the new files over the install folder (elevating once if
/// the folder needs admin rights), restarts the app and deletes the downloaded package.
const String _portableUpdateScript = r'''
param(
  [int]$ProcessId,
  [string]$Source,
  [string]$Target,
  [string]$Exe,
  [string]$Cleanup,
  [switch]$Elevated
)

try { Wait-Process -Id $ProcessId -Timeout 60 -ErrorAction Stop } catch {}

robocopy "$Source" "$Target" /E /R:10 /W:1 /NP /NFL /NDL /NJH /NJS | Out-Null
$copied = $LASTEXITCODE -lt 8

if (-not $copied -and -not $Elevated) {
  $argList = @(
    "-NoProfile",
    "-ExecutionPolicy", "Bypass",
    "-WindowStyle", "Hidden",
    "-File", $PSCommandPath,
    "-ProcessId", "$ProcessId",
    "-Source", $Source,
    "-Target", $Target,
    "-Exe", $Exe,
    "-Cleanup", $Cleanup,
    "-Elevated"
  )
  try {
    Start-Process powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList $argList -ErrorAction Stop
    exit
  } catch {}
}

if ($Elevated) {
  # Start the app through Explorer so it doesn't run as administrator.
  Start-Process explorer.exe -ArgumentList "`"$Exe`""
} else {
  Start-Process -FilePath $Exe
}

if ($copied) {
  Remove-Item -LiteralPath $Cleanup -Recurse -Force -ErrorAction SilentlyContinue
  $root = Split-Path -Parent $Cleanup
  if ((Test-Path -LiteralPath $root) -and -not (Get-ChildItem -LiteralPath $root -Force)) {
    Remove-Item -LiteralPath $root -Force -ErrorAction SilentlyContinue
  }
}
''';
