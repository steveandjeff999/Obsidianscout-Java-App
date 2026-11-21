// Runs the real BleSendServer and BleReceiveClient against an in-memory radio, so the GATT handlers, framing,
// code rotation, lockout and trusted-device pairing are exercised exactly as the plugin would drive them.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_receive_client.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_send_server.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_transfer_protocol.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_trust_store.dart';
import 'package:universal_ble/universal_ble.dart';

import 'support/fake_ble.dart';

void main() {
  late FakePeripheral phone;
  late FakeCentral central;
  late BleSendServer server;
  late BleReceiveClient client;

  setUp(() async {
    airCapture.clear();
    BleTrustStore.storage = MemorySecretStorage();
    phone = FakePeripheral();
    UniversalBlePeripheral.setInstance(phone);
    central = FakeCentral(phone);
    UniversalBle.setInstance(central);
    server = BleSendServer(payload: samplePayload(), username: 'scout_amy');
    client = BleReceiveClient(username: 'lead_bo');
  });

  tearDown(() async {
    // Not awaited, like a sheet closing: the next test's server must survive this teardown finishing late.
    server.dispose();
    await client.dispose();
  });

  Future<BleNearbyScout> findPhone([String? tag]) async {
    await client.stopScan();
    await client.startScan();
    await Future<void>.delayed(Duration.zero);
    expect(client.scouts.value, hasLength(1));
    final scout = client.scouts.value.single;
    expect(scout.tag, tag ?? server.tag);
    return scout;
  }

  var codeAsks = 0;

  /// Receives from [scout], typing [code] (evaluated when the code is asked for) if one is needed.
  Future<BleReceiveOutcome> recv(
    BleNearbyScout scout,
    String Function() code, {
    bool trust = false,
    Future<BleTransferResult> Function(BleTransferPayload p)? importer,
  }) {
    return client.receive(
      scout,
      askCode: () async {
        codeAsks++;
        return (code: code(), trust: trust);
      },
      importer: importer ?? (p) async => const BleTransferResult(ok: true),
    );
  }

  setUp(() => codeAsks = 0);

  test('right code delivers the entry; the receipt reaches the phone', () async {
    await server.start();
    expect(server.state, BleSendState.waiting);
    expect(BleTransferProtocol.tagFromServiceUuid(phone.advertised.single), server.tag);
    final scout = await findPhone();

    BleTransferPayload? imported;
    final outcome = await recv(scout, () => server.code, importer: (p) async {
      imported = p;
      return const BleTransferResult(ok: true);
    });

    expect(outcome.result.ok, isTrue);
    expect(outcome.viaTrust, isFalse);
    expect(outcome.senderLabel, contains('scout_amy'));
    expect(imported!.summary, 'Pit - Team 9001');
    expect(imported!.compressed, samplePayload().compressed);
    // Let the phone process the final write.
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.state, BleSendState.delivered);
    expect(server.receiverName, contains('lead_bo'));
    expect(server.trustedReceivers, isEmpty, reason: 'trust was not ticked');

    final captured = latin1.decode(airCapture);
    expect(captured.contains('Team 9001'), isFalse);
    expect(captured.contains('swerve'), isFalse);
    expect(captured.contains('scout_amy'), isFalse);
    expect(captured.contains(latin1.decode(samplePayload().compressed.sublist(0, 12))), isFalse);
  });

  test('a wrong code is refused, the code changes, and the new code works', () async {
    await server.start();
    final scout = await findPhone();
    final firstCode = server.code;
    var importerCalled = false;

    await expectLater(
      recv(scout, () => wrongCodeFor(firstCode), importer: (p) async {
        importerCalled = true;
        return const BleTransferResult(ok: true);
      }),
      throwsA(isA<BleReceiveException>().having((e) => e.failure, 'failure', BleReceiveFailure.wrongCode)),
    );
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(importerCalled, isFalse);
    expect(server.failedAttempts, 1);
    expect(server.state, BleSendState.waiting);
    expect(server.code, isNot(firstCode));

    // The old code is dead even though it was the right one before.
    await expectLater(recv(scout, () => firstCode), throwsA(isA<BleReceiveException>()));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(server.failedAttempts, 2);

    final outcome = await recv(scout, () => server.code);
    expect(outcome.result.ok, isTrue);
  });

  test('three wrong codes lock the phone and stop advertising', () async {
    await server.start();
    final scout = await findPhone();
    for (var i = 0; i < BleTransferProtocol.maxFailedAttempts; i++) {
      await expectLater(
        recv(scout, () => wrongCodeFor(server.code)),
        throwsA(isA<BleReceiveException>().having((e) => e.failure, 'failure', BleReceiveFailure.wrongCode)),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(server.state, BleSendState.locked);
    expect(phone.advertising, isFalse);
    expect(phone.read, isNull);

    await expectLater(recv(scout, () => server.code), throwsA(isA<BleReceiveException>()));

    await server.restart();
    expect(server.state, BleSendState.waiting);
    expect(server.failedAttempts, 0);
    expect(phone.advertising, isTrue);
  });

  test('cancelling the code prompt disconnects without spending the code', () async {
    await server.start();
    final scout = await findPhone();
    final code = server.code;
    await expectLater(
      client.receive(scout, askCode: () async => null, importer: (p) async => const BleTransferResult(ok: true)),
      throwsA(isA<BleReceiveException>().having((e) => e.failure, 'failure', BleReceiveFailure.cancelled)),
    );
    expect(server.code, code);
    expect(server.failedAttempts, 0);
  });

  test('closing one send sheet does not tear down the next one', () async {
    await server.start();
    final scout = await findPhone();
    await recv(scout, () => server.code);
    // Delivered: this server schedules its own teardown. Close it and open the next entry right away.
    server.dispose();
    final next = BleSendServer(payload: samplePayload());
    addTearDown(next.dispose);
    await next.start();
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(next.state, BleSendState.waiting);
    expect(BleTransferProtocol.tagFromServiceUuid(phone.advertised.single), next.tag);
    expect(phone.read, isNotNull);
    server = BleSendServer(payload: samplePayload()); // keep tearDown happy

    final again = await findPhone(next.tag);
    final outcome = await recv(again, () => next.code);
    expect(outcome.result.ok, isTrue);
  });

  test('a phone seen under two addresses is listed once and the working address is used', () async {
    central.staleAddresses.add('aa:bb:cc:dd:ee:02');
    await server.start();
    final scout = await findPhone();
    expect(scout.deviceIds, hasLength(2));
    // Make the stale address the "newest" so it is tried first.
    final staleFirst = BleNearbyScout(
      tag: scout.tag,
      hint: scout.hint,
      deviceIds: ['aa:bb:cc:dd:ee:02', fakePhoneId],
      lastSeen: scout.lastSeen,
    );
    final outcome = await recv(staleFirst, () => server.code);
    expect(outcome.result.ok, isTrue);
    expect(central.connectAttempts, ['aa:bb:cc:dd:ee:02', fakePhoneId]);
    expect(central.clearGattCacheRequested, isTrue);
  });

  test('a phone that stopped sending is reported as such', () async {
    await server.start();
    final scout = await findPhone();
    await phone.clearServices();
    await expectLater(
      recv(scout, () => server.code),
      throwsA(isA<BleReceiveException>().having((e) => e.message, 'message', contains('no longer sending'))),
    );
  });

  group('trusted devices', () {
    test('after one code transfer with trust ticked, the next needs no code and shows the scout', () async {
      await server.start();
      final first = await findPhone();
      expect(first.trustedPeer, isNull);
      final paired = await recv(first, () => server.code, trust: true);
      expect(paired.newlyTrusted, isTrue);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.newlyTrusted, isTrue);
      expect(server.trustedReceivers.single.label, contains('lead_bo'));
      expect(client.trustedScouts.value.single.label, contains('scout_amy'));
      expect(codeAsks, 1);

      // A new entry from the same phone: new session, new tag and code.
      server.dispose();
      server = BleSendServer(payload: samplePayload(), username: 'scout_amy');
      await server.start();
      final second = await findPhone();
      expect(second.trustedPeer, isNotNull, reason: 'recognized from the advertisement before connecting');
      expect(second.trustedPeer!.label, contains('scout_amy'));

      final codeBefore = server.code;
      final outcome = await recv(second, () => fail('no code should be asked'));
      expect(outcome.viaTrust, isTrue);
      expect(outcome.result.ok, isTrue);
      expect(codeAsks, 1);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.state, BleSendState.delivered);
      expect(server.deliveredViaTrust, isTrue);
      expect(server.code, codeBefore, reason: 'the code was never used');
    });

    test('a phone that forgot the receiver falls back to the code on the same connection', () async {
      await server.start();
      await recv(await findPhone(), () => server.code, trust: true);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      server.dispose();
      server = BleSendServer(payload: samplePayload(), username: 'scout_amy');
      await server.start();
      await server.forgetReceiver(server.trustedReceivers.single.id);
      final scout = await findPhone();
      expect(scout.trustedPeer, isNotNull, reason: 'the receiver still trusts the phone');

      final outcome = await recv(scout, () => server.code, trust: true);
      expect(outcome.result.ok, isTrue);
      expect(outcome.viaTrust, isFalse);
      expect(codeAsks, 2);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(server.failedAttempts, 0, reason: 'the trust mismatch is not a wrong guess');
      expect(server.trustedReceivers, hasLength(1), reason: 're-paired');
    });

    test('forgetting a phone on the receiver means it asks for the code again', () async {
      await server.start();
      await recv(await findPhone(), () => server.code, trust: true);
      await client.forgetScout(client.trustedScouts.value.single.id);
      server.dispose();
      server = BleSendServer(payload: samplePayload(), username: 'scout_amy');
      await server.start();
      final scout = await findPhone();
      expect(scout.trustedPeer, isNull);
      await recv(scout, () => server.code);
      expect(codeAsks, 2);
    });
  });
}
