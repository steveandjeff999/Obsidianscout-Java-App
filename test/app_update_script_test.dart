import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/app_update_io.dart';

void main() {
  test('the elevated update keeps paths that contain spaces whole', () async {
    final argList = RegExp(r'^\s*\$argList = .*$', multiLine: true).firstMatch(portableUpdateScript)?.group(0);
    expect(argList, isNotNull, reason: 'The script should build the elevated arguments on one line');

    final dir = await Directory.systemTemp.createTemp('obsidian update test ');
    addTearDown(() => dir.delete(recursive: true));
    final sep = Platform.pathSeparator;
    final out = '${dir.path}${sep}result.txt';

    // Runs the script's real argument line, starting itself the way the update does (without the admin prompt).
    final harness = File('${dir.path}${sep}harness.ps1');
    await harness.writeAsString('''
param([int]\$ProcessId, [string]\$Source, [string]\$Target, [string]\$Exe, [string]\$Cleanup, [switch]\$Elevated)
if (\$Elevated) {
  Set-Content -LiteralPath \$Source -Value "\$ProcessId|\$Target|\$Exe|\$Cleanup"
  exit
}
$argList
Start-Process powershell.exe -Wait -WindowStyle Hidden -ArgumentList \$argList
''');

    const target = r'C:\Program Files\ObsidianScout';
    const exe = r'C:\Program Files\ObsidianScout\app.exe';
    const cleanup = r'C:\Users\Some One\AppData\updates';
    final result = await Process.run('powershell.exe', [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', harness.path,
      '-ProcessId', '42', '-Source', out, '-Target', target, '-Exe', exe, '-Cleanup', cleanup,
    ]);
    expect(result.exitCode, 0, reason: '${result.stderr}');

    expect((await File(out).readAsString()).trim(), '42|$target|$exe|$cleanup');
  }, skip: Platform.isWindows ? false : 'The update script only runs on Windows');
}
