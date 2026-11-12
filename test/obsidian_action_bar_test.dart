import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/widgets/obsidian_action_bar.dart';

/// Hosts the bar with a fake "form" whose saved value can be changed from the test.
class _Host extends StatefulWidget {
  const _Host({super.key});

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  String value = 'a';
  String saved = 'a';
  bool saving = false;
  bool live = false;

  void edit(String v) => setState(() => value = v);
  void setLive(bool v) => setState(() => live = v);
  void startSave() => setState(() => saving = true);
  void finishSave({required bool ok}) => setState(() {
        if (ok) saved = value;
        saving = false;
      });

  @override
  Widget build(BuildContext context) {
    return ObsidianActionBar(
      isSaving: saving,
      isLive: live,
      isDirty: () => value != saved,
      primary: FilledButton(onPressed: () {}, child: const Text('Save')),
    );
  }
}

void main() {
  Future<_HostState> pump(WidgetTester tester) async {
    final key = GlobalKey<_HostState>();
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: _Host(key: key))));
    return key.currentState!;
  }

  testWidgets('says changes are not auto-saved until something is edited', (tester) async {
    await pump(tester);
    expect(find.text('Changes are not saved automatically'), findsOneWidget);
  });

  testWidgets('edit -> unsaved, save -> saving -> saved -> back to neutral', (tester) async {
    final host = await pump(tester);

    host.edit('b');
    await tester.pump(const Duration(milliseconds: 700)); // dirty poll
    expect(find.text('Unsaved changes'), findsOneWidget);

    host.startSave();
    await tester.pump();
    expect(find.text('Saving...'), findsOneWidget);

    host.finishSave(ok: true);
    await tester.pump();
    expect(find.text('All changes saved'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Changes are not saved automatically'), findsOneWidget);
  });

  testWidgets('a failed save keeps the edits flagged as unsaved', (tester) async {
    final host = await pump(tester);
    host.edit('b');
    await tester.pump(const Duration(milliseconds: 700));
    host.startSave();
    await tester.pump();
    host.finishSave(ok: false);
    await tester.pump();
    expect(find.textContaining('Not saved'), findsOneWidget);

    // Undoing the edit clears the warning.
    host.edit('a');
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Changes are not saved automatically'), findsOneWidget);
  });

  testWidgets('live editors never show unsaved changes', (tester) async {
    final host = await pump(tester);
    host.setLive(true);
    host.edit('b');
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Changes sync automatically'), findsOneWidget);
    expect(find.text('Unsaved changes'), findsNothing);
  });
}
