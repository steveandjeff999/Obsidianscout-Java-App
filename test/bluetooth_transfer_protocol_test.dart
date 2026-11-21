import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/bluetooth/ble_transfer_protocol.dart';
import 'package:obsidianscout_app/widgets/obsidian_barcode_modal.dart';

BleIdentity _identity(int seed, {String user = ''}) {
  final r = Random(seed);
  return BleIdentity(
    id: Uint8List.fromList(List.generate(16, (_) => r.nextInt(256))),
    name: 'Device $seed',
    username: user,
    beaconKey: Uint8List.fromList(List.generate(32, (_) => r.nextInt(256))),
  );
}

final _scoutId = _identity(1, user: 'scout_amy');
final _receiverId = _identity(2, user: 'lead_bo');

/// Passes messages between the two state machines through the same framing the radio uses.
class _Link {
  final int mtu;
  final FrameWriter toScoutWriter = FrameWriter();
  final FrameReader toScoutReader = FrameReader();
  final FrameWriter toReceiverWriter = FrameWriter();
  final FrameReader toReceiverReader = FrameReader();
  int framesToScout = 0;
  int framesToReceiver = 0;
  _Link(this.mtu);

  Uint8List? _carry(Uint8List message, FrameWriter writer, FrameReader reader, void Function() count) {
    Uint8List? out;
    for (final frame in writer.split(message, mtu - 3)) {
      expect(frame.length, lessThanOrEqualTo(mtu - 3));
      count();
      out = reader.add(frame) ?? out;
    }
    return out;
  }

  Uint8List toScout(Uint8List m) => _carry(m, toScoutWriter, toScoutReader, () => framesToScout++)!;
  Uint8List toReceiver(Uint8List m) => _carry(m, toReceiverWriter, toReceiverReader, () => framesToReceiver++)!;
}

BleTransferPayload _payload() {
  final json = jsonEncode({
    'type': 'match-scout',
    'data': {'targetTeamNumber': 5454, 'eventKey': '2026test', 'matchKey': '2026test_qm4', 'notes': 'x' * 300},
  });
  return BleTransferPayload(compressed: Uint8List.fromList(zlib.encode(utf8.encode(json))), summary: 'Team 5454');
}

/// Runs a whole exchange; returns what the receiver got (null if it failed).
({BleTransferPayload? got, ScoutSession scout, ReceiverSession receiver}) _run({
  required String scoutCode,
  required String receiverCode,
  int mtu = 23,
  Uint8List Function(Uint8List)? tamperToReceiver,
}) {
  const tag = 'A1B2';
  final link = _Link(mtu);
  final scout = ScoutSession(tag: tag, code: scoutCode, payload: _payload(), identity: _scoutId);
  final receiver = ReceiverSession.code(tag: tag, code: receiverCode, mtu: mtu, identity: _receiverId);

  var toScout = [receiver.hello()];
  while (toScout.isNotEmpty) {
    final toReceiver = <Uint8List>[];
    for (final m in toScout) {
      toReceiver.addAll(scout.handle(link.toScout(m)));
    }
    toScout = [];
    for (final m in toReceiver) {
      var delivered = link.toReceiver(m);
      if (tamperToReceiver != null) delivered = tamperToReceiver(delivered);
      toScout.addAll(receiver.handle(delivered));
    }
    if (receiver.stage == ReceiverSessionStage.finished && receiver.payload != null && toScout.isEmpty) {
      toScout.add(receiver.buildResult(const BleTransferResult(ok: true, receiverName: 'Pit laptop')));
      final last = toScout.removeLast();
      scout.handle(link.toScout(last));
    }
  }
  return (got: receiver.payload, scout: scout, receiver: receiver);
}

void main() {
  trustedTests();

  test('right code delivers the entry and the receipt, at the minimum MTU', () {
    final r = _run(scoutCode: '482913', receiverCode: '482913');
    expect(r.got, isNotNull);
    expect(r.got!.summary, 'Team 5454');
    final decoded = jsonDecode(BarcodeCompressor.decompressData(r.got!.toQrText()));
    expect(decoded['data']['targetTeamNumber'], 5454);
    expect(r.scout.stage, ScoutSessionStage.finished);
    expect(r.scout.result!.ok, isTrue);
    expect(r.scout.result!.receiverName, 'Pit laptop');
    expect(r.scout.result!.receiver!.username, 'lead_bo');
  });

  test('works at a large MTU too', () {
    final r = _run(scoutCode: '000001', receiverCode: '000001', mtu: 517);
    expect(r.got, isNotNull);
  });

  test('wrong code: receiver rejects the challenge, nothing is sent, scout sees wrongCode', () {
    final r = _run(scoutCode: '482913', receiverCode: '482914');
    expect(r.got, isNull);
    expect(r.receiver.stage, ReceiverSessionStage.failed);
    expect(r.receiver.failure, BleTransferError.wrongCode);
    expect(r.scout.stage, ScoutSessionStage.failed);
    expect(r.scout.failure, BleTransferError.wrongCode);
    expect(r.scout.authenticated, isFalse);
    expect(r.scout.codeConsumed, isTrue);
  });

  test('a forged confirmation is refused by the scout before any data goes out', () {
    final scout = ScoutSession(tag: 'A1B2', code: '111111', payload: _payload(), identity: _scoutId);
    final attacker = ReceiverSession.code(tag: 'A1B2', code: '222222', mtu: 185, identity: _receiverId);
    final challenge = scout.handle(attacker.hello());
    expect(challenge.single[0], BleMessageType.challenge.code);
    final reply = scout.handle(encodeMessage(BleMessageType.confirm, List.filled(32, 7)));
    expect(reply.single, errorMessage(BleTransferError.wrongCode));
    expect(scout.stage, ScoutSessionStage.failed);
    expect(scout.authenticated, isFalse);
  });

  test('tampered ciphertext is rejected', () {
    final r = _run(
      scoutCode: '123123',
      receiverCode: '123123',
      tamperToReceiver: (m) {
        if (m[0] != BleMessageType.data.code) return m;
        final copy = Uint8List.fromList(m);
        copy[copy.length - 1] ^= 1;
        return copy;
      },
    );
    expect(r.got, isNull);
    expect(r.receiver.failure, BleTransferError.protocol);
  });

  test('the recorded exchange does not contain the plaintext entry', () {
    final scout = ScoutSession(tag: 'A1B2', code: '654321', payload: _payload(), identity: _scoutId);
    final receiver = ReceiverSession.code(tag: 'A1B2', code: '654321', mtu: 185, identity: _receiverId);
    final wire = <int>[];
    final hello = receiver.hello();
    wire.addAll(hello);
    final challenge = scout.handle(hello).single;
    wire.addAll(challenge);
    final confirm = receiver.handle(challenge).single;
    wire.addAll(confirm);
    final data = scout.handle(confirm).single;
    wire.addAll(data);
    receiver.handle(data);
    expect(receiver.payload, isNotNull);
    final compressed = receiver.payload!.compressed;
    final asText = latin1.decode(wire, allowInvalid: true);
    expect(asText.contains('Team 5454'), isFalse);
    // No 16-byte window of the compressed entry shows up on the wire.
    final needle = latin1.decode(compressed.sublist(0, 16));
    expect(asText.contains(needle), isFalse);
  });

  test('frame reader catches a dropped frame', () {
    final writer = FrameWriter();
    final frames = writer.split(Uint8List(100), 23);
    final reader = FrameReader();
    reader.add(frames[0]);
    expect(() => reader.add(frames[2]), throwsA(isA<BleProtocolException>()));
  });

  test('codes, tags and service UUIDs', () {
    final rnd = Random(1);
    final code = BleTransferProtocol.newCode(rnd);
    expect(code, matches(RegExp(r'^\d{6}$')));
    expect(BleTransferProtocol.normalizeCode('482 913'), '482913');
    expect(BleTransferProtocol.normalizeCode('48291'), isNull);
    final tag = BleTransferProtocol.newTag(rnd);
    final uuid = BleTransferProtocol.serviceUuid(tag, BleTransferProtocol.beaconHint(_scoutId.beaconKey, tag));
    expect(uuid.length, 36);
    expect(BleTransferProtocol.tagFromServiceUuid(uuid.toUpperCase()), tag);
    expect(BleTransferProtocol.tagFromServiceUuid('0000180f-0000-1000-8000-00805f9b34fb'), isNull);
  });

  test('oversized payloads are refused', () {
    final big = BleTransferPayload(
      compressed: Uint8List(BleTransferProtocol.maxPayloadBytes + 1),
      summary: '',
    );
    expect(() => BleTransferPayload.decode(big.encode()), throwsA(isA<BleProtocolException>()));
  });
}

/// Runs a code session with trust requested and returns both sides' stored trust records.
({BleTrustedPeer onScout, BleTrustedPeer onReceiver}) _pair(String tag) {
  final scout = ScoutSession(tag: tag, code: '246810', payload: _payload(), identity: _scoutId);
  final receiver =
      ReceiverSession.code(tag: tag, code: '246810', mtu: 185, identity: _receiverId, requestTrust: true);
  final challenge = scout.handle(receiver.hello()).single;
  final confirm = receiver.handle(challenge).single;
  final data = scout.handle(confirm).single;
  receiver.handle(data);
  scout.handle(receiver.buildResult(const BleTransferResult(ok: true)));
  return (onScout: scout.trustToSave!, onReceiver: receiver.trustToSave!);
}

void trustedTests() {
  test('a code transfer with trust ticked pairs both devices with the same key and names', () {
    final pair = _pair('C0DE');
    expect(pair.onScout.key, pair.onReceiver.key);
    expect(pair.onScout.id, _receiverId.idHex);
    expect(pair.onScout.username, 'lead_bo');
    expect(pair.onScout.role, BleTrustRole.receiver);
    expect(pair.onReceiver.id, _scoutId.idHex);
    expect(pair.onReceiver.username, 'scout_amy');
    expect(pair.onReceiver.label, 'Device 1 - scout_amy');
    expect(pair.onReceiver.beaconKey, _scoutId.beaconKey);
  });

  test('without trust ticked nothing is stored', () {
    final scout = ScoutSession(tag: 'AAAA', code: '111222', payload: _payload(), identity: _scoutId);
    final receiver = ReceiverSession.code(tag: 'AAAA', code: '111222', mtu: 185, identity: _receiverId);
    final confirm = receiver.handle(scout.handle(receiver.hello()).single).single;
    receiver.handle(scout.handle(confirm).single);
    scout.handle(receiver.buildResult(const BleTransferResult(ok: true)));
    expect(receiver.trustToSave, isNull);
    expect(scout.trustToSave, isNull);
  });

  test('paired devices transfer later with no code, and the code is not spent', () {
    final pair = _pair('C0DE');
    final scout = ScoutSession(
      tag: 'BEEF',
      code: '999999',
      payload: _payload(),
      identity: _scoutId,
      trustedReceivers: {pair.onScout.id: pair.onScout},
    );
    final receiver =
        ReceiverSession.trusted(tag: 'BEEF', mtu: 64, identity: _receiverId, expectedPeer: pair.onReceiver);
    final link = _Link(64);
    var toScout = [receiver.hello()];
    while (toScout.isNotEmpty) {
      final replies = <Uint8List>[];
      for (final m in toScout) {
        replies.addAll(scout.handle(link.toScout(m)));
      }
      toScout = [];
      for (final m in replies) {
        toScout.addAll(receiver.handle(link.toReceiver(m)));
      }
    }
    expect(receiver.stage, ReceiverSessionStage.finished);
    expect(receiver.payload!.summary, 'Team 5454');
    scout.handle(link.toScout(receiver.buildResult(const BleTransferResult(ok: true))));
    expect(scout.stage, ScoutSessionStage.finished);
    expect(scout.trustedPeer!.id, _receiverId.idHex);
    expect(scout.codeConsumed, isFalse);
  });

  test('a phone that forgot the receiver answers notTrusted, without spending its code', () {
    final pair = _pair('C0DE');
    final scout = ScoutSession(tag: 'BEEF', code: '999999', payload: _payload(), identity: _scoutId);
    final receiver =
        ReceiverSession.trusted(tag: 'BEEF', mtu: 185, identity: _receiverId, expectedPeer: pair.onReceiver);
    final reply = scout.handle(receiver.hello());
    expect(reply.single, errorMessage(BleTransferError.notTrusted));
    expect(scout.failure, BleTransferError.notTrusted);
    expect(scout.codeConsumed, isFalse);
    receiver.handle(reply.single);
    expect(receiver.failure, BleTransferError.notTrusted);
  });

  test('a stranger claiming a trusted receiver id cannot get the entry', () {
    final pair = _pair('C0DE');
    final scout = ScoutSession(
      tag: 'BEEF',
      code: '999999',
      payload: _payload(),
      identity: _scoutId,
      trustedReceivers: {pair.onScout.id: pair.onScout},
    );
    // Same receiver id the phone trusts, but a made-up pairing key.
    final forged = BleTrustedPeer(
      id: _scoutId.idHex,
      name: '',
      key: Uint8List(32),
      role: BleTrustRole.scout,
      added: DateTime.now(),
      lastUsed: DateTime.now(),
    );
    final attacker = ReceiverSession.trusted(tag: 'BEEF', mtu: 185, identity: _receiverId, expectedPeer: forged);
    final challenge = scout.handle(attacker.hello()).single;
    expect(attacker.handle(challenge).single, errorMessage(BleTransferError.notTrusted));
    final reply = scout.handle(encodeMessage(BleMessageType.trustedConfirm, List.filled(32, 1)));
    expect(reply.single, errorMessage(BleTransferError.notTrusted));
    expect(scout.authenticated, isFalse);
  });

  test('a paired receiver recognizes the phone from its advertisement; others cannot', () {
    const tag = '4F2A';
    final hint = BleTransferProtocol.beaconHint(_scoutId.beaconKey, tag);
    final parsed = BleTransferProtocol.parseServiceUuid(BleTransferProtocol.serviceUuid(tag, hint))!;
    expect(parsed.tag, tag);
    expect(BleTransferProtocol.beaconHint(_scoutId.beaconKey, parsed.tag), parsed.hint);
    expect(BleTransferProtocol.beaconHint(_receiverId.beaconKey, parsed.tag), isNot(parsed.hint));
    // A new session tag gives an unrelated hint, so strangers can't link sessions.
    expect(BleTransferProtocol.beaconHint(_scoutId.beaconKey, '4F2B'), isNot(hint));
  });
}
