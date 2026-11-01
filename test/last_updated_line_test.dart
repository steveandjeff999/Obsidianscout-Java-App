import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/api_service.dart';
import 'package:obsidianscout_app/services/net/net_client.dart';
import 'package:obsidianscout_app/widgets/last_updated_line.dart';

class _FakeApi extends ApiService {
  bool online = true;
  final StreamController<bool> onlineChanges = StreamController<bool>.broadcast();

  @override
  bool get isOnline => online;

  @override
  Stream<bool> get onOnlineStatusChanged => onlineChanges.stream;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeApi api;

  setUp(() {
    api = _FakeApi();
    NetClient.lastDataAt.value = null;
  });

  Widget line() => MaterialApp(home: Scaffold(body: LastUpdatedLine(apiService: api)));

  testWidgets('shows nothing until data has arrived, then the time', (tester) async {
    await tester.pumpWidget(line());
    expect(find.byType(Text), findsNothing);

    NetClient.lastDataAt.value = DateTime(2026, 11, 1, 15, 42, 5);
    await tester.pump();
    expect(find.textContaining('Last updated'), findsOneWidget);
    expect(find.textContaining('3:42'), findsOneWidget);
  });

  testWidgets('offline says the data is a saved copy', (tester) async {
    NetClient.lastDataAt.value = DateTime(2026, 11, 1, 15, 42, 5);
    await tester.pumpWidget(line());

    api.onlineChanges.add(false);
    await tester.pump();
    expect(find.textContaining('Showing saved data from'), findsOneWidget);
  });

  testWidgets('offline with no time yet still says so', (tester) async {
    api.online = false;
    await tester.pumpWidget(line());
    await tester.pump();
    expect(find.text('Showing saved data'), findsOneWidget);
  });

  testWidgets('another day includes the date', (tester) async {
    final at = DateTime(2026, 10, 30, 9, 5, 7);
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        expect(LastUpdatedLine.formatTime(context, at, now: DateTime(2026, 10, 30, 12)).contains('Oct'), isFalse);
        expect(LastUpdatedLine.formatTime(context, at, now: DateTime(2026, 11, 1, 12)).contains('Oct'), isTrue);
        return const SizedBox();
      }),
    ));
  });
}
