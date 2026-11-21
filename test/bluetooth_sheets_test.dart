// Renders the Bluetooth send and receive sheets against the in-memory radio.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_send_server.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_transfer_protocol.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_trust_store.dart';
import 'package:obsidianscout_app/widgets/bluetooth_receive_sheet.dart';
import 'package:obsidianscout_app/widgets/bluetooth_send_sheet.dart';
import 'package:universal_ble/universal_ble.dart';

import 'support/fake_ble.dart';

void main() {
  late FakePeripheral phone;
  late BleSendServer server;

  setUp(() {
    BleTrustStore.storage = MemorySecretStorage();
    phone = FakePeripheral();
    UniversalBlePeripheral.setInstance(phone);
    UniversalBle.setInstance(FakeCentral(phone));
    server = BleSendServer(payload: samplePayload());
  });

  tearDown(() => server.dispose());

  testWidgets('receive sheet lists the sending phone and asks for its code', (tester) async {
    await tester.runAsync(server.start);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BluetoothReceiveSheet(onPayload: (p) async => const BleTransferResult(ok: true))),
    ));
    // The plugin's command queue runs on real timers.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Phone ${server.tag}'), findsOneWidget);
    expect(find.textContaining('not available on the website'), findsOneWidget);
    await tester.tap(find.text('Phone ${server.tag}'));
    // Connecting runs on real timers; the code is asked for once connected.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.byKey(const Key('bluetooth_code_field')), findsOneWidget);
    expect(find.byKey(const Key('bluetooth_trust_checkbox')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('bluetooth_code_field')), '12');
    await tester.tap(find.text('Receive'));
    await tester.pump();
    expect(find.text('Enter the 6-digit code.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byKey(const Key('bluetooth_code_field')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Drain the radio work the unmount queued, so the next test does not wait behind it.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  testWidgets('a trusted phone is listed with its device name and scout username', (tester) async {
    await tester.runAsync(() async {
      final me = await BleTrustStore.identity();
      await BleTrustStore.save(BleTrustedPeer(
        id: me.idHex,
        name: 'Pixel 8',
        username: 'scout_amy',
        key: me.beaconKey,
        role: BleTrustRole.scout,
        beaconKey: me.beaconKey,
        added: DateTime.now(),
        lastUsed: DateTime.now(),
      ));
      await server.start();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: BluetoothReceiveSheet(onPayload: (p) async => const BleTransferResult(ok: true))),
    ));
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('Pixel 8 - scout_amy'), findsOneWidget);
    expect(find.textContaining('Trusted - no code needed'), findsOneWidget);
    expect(find.text('Trusted phones (1)'), findsOneWidget);
    await tester.tap(find.byKey(const Key('bluetooth_manage_trusted')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Forget'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  });

  // Last: work it queues on the widget test's fake clock is not drained for later tests.
  testWidgets('send sheet shows the phone tag and a 6-digit code at phone width', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: BluetoothSendSheet(payload: samplePayload()))));
    // The plugin's command queue runs on real timers.
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    final codeText = tester.widget<Text>(find.byKey(const Key('bluetooth_send_code'))).data!;
    expect(codeText, matches(RegExp(r'^\d{3} \d{3}$')));
    expect(phone.advertised, hasLength(1));
    final tag = BleTransferProtocol.tagFromServiceUuid(phone.advertised.single)!;
    expect(find.text('Phone $tag'), findsOneWidget);
    expect(find.textContaining('not available on the website'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    // Drain the radio work the unmount queued, so the next test does not wait behind it.
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(phone.advertising, isFalse, reason: 'closing the sheet stops advertising');
  });
}
