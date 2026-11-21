/// Wire protocol for sending scouting entries from a scout's phone to a receiver over Bluetooth LE.
///
/// The scout's phone is the GATT server. The receiver connects, writes requests to [BleTransferProtocol.rxUuid]
/// and polls [BleTransferProtocol.txUuid] with reads for the replies. Reads are used instead of notifications so
/// every byte from the phone is a request/response the BLE stack acknowledges, the same way on every platform.
///
/// Security comes from the short code on the scout's screen, not from Bluetooth pairing.
///
/// First transfer between two devices (code):
/// 1. HELLO (receiver -> scout): SPAKE2 public value pA, keyed by the code.
/// 2. CHALLENGE (scout -> receiver): pB and the scout's key confirmation cB.
/// 3. CONFIRM (receiver -> scout): the receiver's key confirmation cA, sent only if cB checked out.
/// 4. DATA (scout -> receiver): the entry, AES-256-GCM encrypted under a key derived from the handshake.
/// 5. RESULT (receiver -> scout): encrypted import result. If the receiver asked to trust the scout, both sides
///    keep a pairing key derived from the handshake.
///
/// Later transfers between trusted devices (no code):
/// 1. TRUSTED_HELLO (receiver -> scout): receiver id and an ephemeral P-256 key.
/// 2. TRUSTED_CHALLENGE (scout -> receiver): scout id, its ephemeral key, and a MAC keyed by the pairing key.
/// 3. TRUSTED_CONFIRM (receiver -> scout): the receiver's MAC.
/// Then DATA and RESULT as above, under keys mixing the pairing key with the ephemeral Diffie-Hellman secret.
/// If either side no longer trusts the other it answers NOT_TRUSTED and the receiver falls back to the code on
/// the same connection.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/export.dart' show AEADParameters, AESEngine, GCMBlockCipher, KeyParameter;

import 'spake2.dart';

class BleTransferProtocol {
  static const int version = 1;

  /// Each send session advertises its own service UUID: `a3f1c9e2-6b7d-4e58-TTTT-HHHHHHHHHHHH`. TTTT is a random
  /// tag the phone shows so people can tell phones apart. HHHH is a hint only devices paired with that phone can
  /// recognize (an HMAC of the tag under the phone's beacon key), so strangers cannot track a phone across
  /// sessions but paired receivers can show who it is before connecting.
  static const String servicePrefix = 'a3f1c9e2-6b7d-4e58-';
  static const String rxUuid = 'a3f1c9e3-6b7d-4e58-9f0a-21c4b8d70001';
  static const String txUuid = 'a3f1c9e3-6b7d-4e58-9f0a-21c4b8d70002';

  static final RegExp _serviceRe = RegExp(r'^a3f1c9e2-6b7d-4e58-([0-9a-f]{4})-([0-9a-f]{12})$');

  static const int codeLength = 6;
  static const int idLength = 16;

  /// Wrong codes allowed before the phone stops advertising and waits for the scout.
  static const int maxFailedAttempts = 3;

  /// Largest compressed entry we carry. Matches the QR import limit (64 KiB of base64).
  static const int maxPayloadBytes = 48 * 1024;
  static const int maxMessageBytes = maxPayloadBytes + 4096;

  /// Smallest ATT MTU (23) leaves 20 bytes per write.
  static const int minValueLength = 20;
  static const int maxValueLength = 512;

  static String serviceUuid(String tag, String hint) => '$servicePrefix${tag.toLowerCase()}-${hint.toLowerCase()}';

  /// The tag and hint from an advertised service UUID, or null if it isn't one of ours.
  static ({String tag, String hint})? parseServiceUuid(String uuid) {
    final m = _serviceRe.firstMatch(uuid.toLowerCase());
    if (m == null) return null;
    return (tag: m.group(1)!.toUpperCase(), hint: m.group(2)!);
  }

  static String? tagFromServiceUuid(String uuid) => parseServiceUuid(uuid)?.tag;

  /// 6-byte hint for [tag] under a phone's beacon key.
  static String beaconHint(List<int> beaconKey, String tag) {
    final mac = Hmac(sha256, beaconKey).convert(utf8.encode('obsidianscout-ble-beacon|${tag.toUpperCase()}')).bytes;
    return bytesToHex(mac.sublist(0, 6));
  }

  static String newTag([Random? random]) {
    final r = random ?? Random.secure();
    return r.nextInt(0x10000).toRadixString(16).padLeft(4, '0').toUpperCase();
  }

  static String newCode([Random? random]) {
    final r = random ?? Random.secure();
    return List.generate(codeLength, (_) => r.nextInt(10)).join();
  }

  /// Codes are digits only; spaces or dashes a person types are ignored.
  static String? normalizeCode(String input) {
    final digits = input.replaceAll(RegExp(r'[\s-]'), '');
    return RegExp('^[0-9]{$codeLength}\$').hasMatch(digits) ? digits : null;
  }

  static final List<int> idReceiver = utf8.encode('obsidianscout-ble-receiver');
  static final List<int> idScout = utf8.encode('obsidianscout-ble-scout');

  static List<int> aad(String tag) => utf8.encode('obsidianscout-ble-v$version|${tag.toUpperCase()}');

  static BigInt passwordScalar(String tag, String code) =>
      Spake2.passwordScalar(utf8.encode('obsidianscout-ble-v$version:${tag.toUpperCase()}:$code'));
}

enum BleMessageType {
  hello(0x01),
  challenge(0x02),
  confirm(0x03),
  data(0x04),
  result(0x05),
  trustedHello(0x08),
  trustedChallenge(0x09),
  trustedConfirm(0x0a),
  error(0x7f);

  final int code;
  const BleMessageType(this.code);

  static BleMessageType? fromCode(int code) {
    for (final t in values) {
      if (t.code == code) return t;
    }
    return null;
  }
}

enum BleTransferError {
  wrongCode(1),
  busy(2),
  unsupportedVersion(3),
  locked(4),
  protocol(5),
  tooLarge(6),
  rejected(7),

  /// The other device no longer trusts this one. Not a failed attempt: fall back to the code.
  notTrusted(8);

  final int code;
  const BleTransferError(this.code);

  static BleTransferError fromCode(int code) {
    for (final e in values) {
      if (e.code == code) return e;
    }
    return BleTransferError.protocol;
  }
}

class BleProtocolException implements Exception {
  final BleTransferError error;
  final String message;
  const BleProtocolException(this.error, this.message);
  @override
  String toString() => 'BleProtocolException(${error.name}): $message';
}

/// This install's Bluetooth identity.
class BleIdentity {
  /// 16 random bytes, made once per install.
  final Uint8List id;

  /// Device label, e.g. the computer name.
  final String name;

  /// Signed-in username, shown to paired devices. May be empty.
  final String username;

  /// Shared with paired receivers so they can recognize this phone's advertisements.
  final Uint8List beaconKey;

  const BleIdentity({required this.id, required this.name, required this.beaconKey, this.username = ''});

  String get idHex => bytesToHex(id);

  BleIdentity withUsername(String? username) =>
      BleIdentity(id: id, name: name, beaconKey: beaconKey, username: (username ?? '').trim());

  Map<String, dynamic> toInfoJson({bool includeBeacon = false}) => {
        'id': idHex,
        'name': name,
        'user': username,
        if (includeBeacon) 'beacon': base64.encode(beaconKey),
      };
}

/// What one device tells the other about itself, inside the encrypted channel.
class BlePeerInfo {
  final String idHex;
  final String name;
  final String username;
  final Uint8List? beaconKey;

  const BlePeerInfo({required this.idHex, required this.name, required this.username, this.beaconKey});

  static BlePeerInfo? fromJson(Object? json) {
    if (json is! Map) return null;
    final id = (json['id'] ?? '').toString().toLowerCase();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(id)) return null;
    Uint8List? beacon;
    final b = json['beacon'];
    if (b is String) {
      try {
        final bytes = base64.decode(b);
        if (bytes.length == 32) beacon = Uint8List.fromList(bytes);
      } catch (_) {}
    }
    String clip(Object? v) {
      final s = (v ?? '').toString().trim();
      return s.length > 64 ? s.substring(0, 64) : s;
    }

    return BlePeerInfo(idHex: id, name: clip(json['name']), username: clip(json['user']), beaconKey: beacon);
  }
}

/// Which side of a transfer the other device was on when it was trusted.
enum BleTrustRole {
  /// A receiver that may pull entries from this device without a code.
  receiver,

  /// A scout device this receiver may pull entries from without a code.
  scout,
}

class BleTrustedPeer {
  final String id;
  final String name;
  final String username;
  final Uint8List key;
  final BleTrustRole role;

  /// The scout's beacon key, so a receiver can recognize it while scanning. Null for receivers.
  final Uint8List? beaconKey;
  final DateTime added;
  final DateTime lastUsed;

  const BleTrustedPeer({
    required this.id,
    required this.name,
    required this.key,
    required this.role,
    required this.added,
    required this.lastUsed,
    this.username = '',
    this.beaconKey,
  });

  /// "Device name - username", or whichever is known.
  String get label => [if (name.isNotEmpty) name, if (username.isNotEmpty) username].join(' - ');

  BleTrustedPeer refreshedFrom(BlePeerInfo info) => BleTrustedPeer(
        id: id,
        name: info.name.isEmpty ? name : info.name,
        username: info.username.isEmpty ? username : info.username,
        key: key,
        role: role,
        beaconKey: info.beaconKey ?? beaconKey,
        added: added,
        lastUsed: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'user': username,
        'key': base64.encode(key),
        'role': role.name,
        if (beaconKey != null) 'beacon': base64.encode(beaconKey!),
        'added': added.toIso8601String(),
        'lastUsed': lastUsed.toIso8601String(),
      };

  static BleTrustedPeer? fromJson(Object? json) {
    if (json is! Map) return null;
    try {
      final key = base64.decode(json['key'] as String);
      if (key.length != 32) return null;
      Uint8List? beacon;
      if (json['beacon'] is String) {
        final b = base64.decode(json['beacon'] as String);
        if (b.length == 32) beacon = Uint8List.fromList(b);
      }
      return BleTrustedPeer(
        id: (json['id'] as String).toLowerCase(),
        name: (json['name'] ?? '').toString(),
        username: (json['user'] ?? '').toString(),
        key: Uint8List.fromList(key),
        role: BleTrustRole.values.byName(json['role'] as String),
        beaconKey: beacon,
        added: DateTime.tryParse('${json['added']}') ?? DateTime.now(),
        lastUsed: DateTime.tryParse('${json['lastUsed']}') ?? DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }
}

Uint8List encodeMessage(BleMessageType type, [List<int> body = const []]) =>
    Uint8List.fromList([type.code, ...body]);

Uint8List errorMessage(BleTransferError error) => encodeMessage(BleMessageType.error, [error.code]);

/// Splits messages into GATT values: one header byte (bit 7 = last frame, bits 0-6 = sequence number), then data.
/// The sequence runs on across messages so a dropped or repeated value is caught.
class FrameWriter {
  int _seq = 0;

  List<Uint8List> split(Uint8List message, int maxValueLength) {
    final valueLen = maxValueLength.clamp(BleTransferProtocol.minValueLength, BleTransferProtocol.maxValueLength);
    final chunk = valueLen - 1;
    final frames = <Uint8List>[];
    var offset = 0;
    do {
      final end = min(offset + chunk, message.length);
      final last = end >= message.length;
      final frame = Uint8List(1 + end - offset);
      frame[0] = (last ? 0x80 : 0) | (_seq & 0x7f);
      frame.setRange(1, frame.length, message, offset);
      frames.add(frame);
      _seq = (_seq + 1) & 0x7f;
      offset = end;
    } while (offset < message.length);
    return frames;
  }
}

class FrameReader {
  int _expectedSeq = 0;
  final BytesBuilder _buffer = BytesBuilder(copy: true);

  /// Adds one GATT value. Returns the whole message once its last frame arrives.
  Uint8List? add(List<int> frame) {
    if (frame.isEmpty) return null;
    final header = frame[0];
    final seq = header & 0x7f;
    if (seq != _expectedSeq) {
      throw BleProtocolException(BleTransferError.protocol, 'frame $seq arrived, expected $_expectedSeq');
    }
    _expectedSeq = (_expectedSeq + 1) & 0x7f;
    if (_buffer.length + frame.length - 1 > BleTransferProtocol.maxMessageBytes) {
      throw const BleProtocolException(BleTransferError.tooLarge, 'message too large');
    }
    _buffer.add(frame.sublist(1));
    if (header & 0x80 == 0) return null;
    return _buffer.takeBytes();
  }
}

/// AES-256-GCM in one direction, with a message counter as the nonce.
class _Aead {
  final Uint8List _key;
  int _counter = 0;
  _Aead(this._key);

  Uint8List _nonce() {
    final n = Uint8List(12);
    ByteData.sublistView(n).setUint64(4, _counter++);
    return n;
  }

  Uint8List seal(List<int> plaintext, List<int> aad) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(true, AEADParameters(KeyParameter(_key), 128, _nonce(), Uint8List.fromList(aad)));
    return cipher.process(Uint8List.fromList(plaintext));
  }

  Uint8List open(List<int> ciphertext, List<int> aad) {
    final cipher = GCMBlockCipher(AESEngine())
      ..init(false, AEADParameters(KeyParameter(_key), 128, _nonce(), Uint8List.fromList(aad)));
    try {
      return cipher.process(Uint8List.fromList(ciphertext));
    } catch (_) {
      throw const BleProtocolException(BleTransferError.protocol, 'message failed authentication');
    }
  }
}

class _SessionKeys {
  final _Aead scoutToReceiver;
  final _Aead receiverToScout;
  _SessionKeys(List<int> sharedKey, List<int> salt)
      : scoutToReceiver = _Aead(hkdfSha256(
            ikm: sharedKey, salt: salt, info: utf8.encode('obsidianscout ble v1 scout to receiver'), length: 32)),
        receiverToScout = _Aead(hkdfSha256(
            ikm: sharedKey, salt: salt, info: utf8.encode('obsidianscout ble v1 receiver to scout'), length: 32));
}

Uint8List _pairingKey(Spake2Keys keys) => hkdfSha256(
    ikm: keys.sharedKey,
    salt: keys.transcriptHash,
    info: utf8.encode('obsidianscout ble v1 pairing key'),
    length: 32);

/// Keys for a trusted session: MAC keys for each side and the session key, bound to everything both sides sent.
class _TrustedKeys {
  final Uint8List macScout;
  final Uint8List macReceiver;
  final Uint8List sessionKey;
  final Uint8List salt;
  final Uint8List transcript;

  _TrustedKeys._(this.macScout, this.macReceiver, this.sessionKey, this.salt, this.transcript);

  factory _TrustedKeys({
    required List<int> pairingKey,
    required List<int> dhSecret,
    required String tag,
    required List<int> receiverId,
    required List<int> receiverEphemeral,
    required List<int> scoutId,
    required List<int> scoutEphemeral,
  }) {
    final t = Spake2.transcript(
      idA: utf8.encode('obsidianscout-ble-v1-trusted|${tag.toUpperCase()}'),
      idB: receiverId,
      pA: receiverEphemeral,
      pB: scoutId,
      k: scoutEphemeral,
      w: const [],
    );
    final salt = Uint8List.fromList(sha256.convert(t).bytes);
    final okm = hkdfSha256(
        ikm: [...pairingKey, ...dhSecret], salt: salt, info: utf8.encode('obsidianscout ble v1 trusted'), length: 96);
    return _TrustedKeys._(
      Uint8List.sublistView(okm, 0, 32),
      Uint8List.sublistView(okm, 32, 64),
      Uint8List.sublistView(okm, 64, 96),
      salt,
      t,
    );
  }

  Uint8List macFor(List<int> key) => Uint8List.fromList(Hmac(sha256, key).convert(transcript).bytes);
}

/// What a scout sends: the compressed QR envelope plus a short description for the receiver's screen.
class BleTransferPayload {
  /// zlib-compressed JSON, the same bytes a QR code carries after its `OSC:` prefix.
  final Uint8List compressed;
  final String summary;

  /// Who sent it. Set when decoding; the sender's session fills it in when encoding.
  final BlePeerInfo? sender;

  const BleTransferPayload({required this.compressed, required this.summary, this.sender});

  Uint8List encode({Map<String, dynamic>? senderInfo}) {
    final meta = utf8.encode(jsonEncode({'summary': summary, if (senderInfo != null) 'sender': senderInfo}));
    final out = BytesBuilder(copy: false)
      ..add((ByteData(2)..setUint16(0, meta.length)).buffer.asUint8List())
      ..add(meta)
      ..add(compressed);
    return out.takeBytes();
  }

  static BleTransferPayload decode(Uint8List bytes) {
    if (bytes.length < 2) throw const BleProtocolException(BleTransferError.protocol, 'short payload');
    final metaLen = ByteData.sublistView(bytes).getUint16(0);
    if (bytes.length < 2 + metaLen) throw const BleProtocolException(BleTransferError.protocol, 'short payload');
    String summary = '';
    BlePeerInfo? sender;
    try {
      final meta = jsonDecode(utf8.decode(bytes.sublist(2, 2 + metaLen)));
      if (meta is Map) {
        if (meta['summary'] is String) summary = meta['summary'] as String;
        sender = BlePeerInfo.fromJson(meta['sender']);
      }
    } catch (_) {}
    final compressed = Uint8List.sublistView(bytes, 2 + metaLen);
    if (compressed.length > BleTransferProtocol.maxPayloadBytes) {
      throw const BleProtocolException(BleTransferError.tooLarge, 'payload too large');
    }
    return BleTransferPayload(compressed: Uint8List.fromList(compressed), summary: summary, sender: sender);
  }

  /// The string the QR import path understands.
  String toQrText() => 'OSC:${base64.encode(compressed)}';
}

/// What the receiver reports back after importing.
class BleTransferResult {
  final bool ok;
  final String message;
  final String receiverName;

  /// Set when decoding on the scout's side.
  final BlePeerInfo? receiver;
  final bool trust;

  const BleTransferResult({
    required this.ok,
    this.message = '',
    this.receiverName = '',
    this.receiver,
    this.trust = false,
  });

  List<int> encode({Map<String, dynamic>? receiverInfo, bool trust = false}) => utf8.encode(jsonEncode({
        'ok': ok,
        'message': message,
        'receiverName': receiverName,
        if (receiverInfo != null) 'receiver': receiverInfo,
        'trust': trust,
      }));

  static BleTransferResult decode(List<int> bytes) {
    try {
      final m = jsonDecode(utf8.decode(bytes));
      if (m is Map) {
        final info = BlePeerInfo.fromJson(m['receiver']);
        return BleTransferResult(
          ok: m['ok'] == true,
          message: (m['message'] ?? '').toString(),
          receiverName: (m['receiverName'] ?? info?.name ?? '').toString(),
          receiver: info,
          trust: m['trust'] == true,
        );
      }
    } catch (_) {}
    throw const BleProtocolException(BleTransferError.protocol, 'bad result');
  }
}

enum ScoutSessionStage { waitingHello, waitingConfirm, waitingResult, finished, failed }

/// The scout's side of one connection. Feed it whole messages; it returns whole messages to send back.
/// Holds no Bluetooth state, so it can be tested without a radio.
class ScoutSession {
  final String tag;
  final String code;
  final BleTransferPayload payload;
  final BleIdentity identity;

  /// Receivers allowed in without a code, by id (hex).
  final Map<String, BleTrustedPeer> trustedReceivers;

  ScoutSessionStage stage = ScoutSessionStage.waitingHello;
  BleTransferError? failure;
  BleTransferResult? result;

  /// Receiver's ATT MTU from its hello, so replies fit in single reads.
  int peerMtu = 23;

  /// Set when a receiver came in through trust rather than the code.
  BleTrustedPeer? trustedPeer;

  /// After a finished transfer: the trust record to store (new pairing or refreshed names).
  BleTrustedPeer? trustToSave;

  Spake2Keys? _keys;
  bool _codeTried = false;
  _TrustedKeys? _trusted;
  _SessionKeys? _session;

  ScoutSession({
    required this.tag,
    required this.code,
    required this.payload,
    required this.identity,
    this.trustedReceivers = const {},
  });

  /// True when the code was tried (a code HELLO arrived) and must not be used again.
  bool get codeConsumed => _codeTried;

  /// True if the receiver proved it knew the code or the pairing key.
  bool get authenticated => _session != null;

  List<Uint8List> handle(Uint8List message) {
    if (message.isEmpty) return _fail(BleTransferError.protocol);
    final type = BleMessageType.fromCode(message[0]);
    final body = Uint8List.sublistView(message, 1);
    if (type == BleMessageType.error) {
      failure = body.isNotEmpty ? BleTransferError.fromCode(body[0]) : BleTransferError.protocol;
      stage = ScoutSessionStage.failed;
      return const [];
    }
    switch (stage) {
      case ScoutSessionStage.waitingHello:
        if (type == BleMessageType.hello) return _onHello(body);
        if (type == BleMessageType.trustedHello) return _onTrustedHello(body);
        return _fail(BleTransferError.protocol);

      case ScoutSessionStage.waitingConfirm:
        if (_trusted != null) {
          if (type != BleMessageType.trustedConfirm) return _fail(BleTransferError.protocol);
          if (!constantTimeEquals(body, _trusted!.macFor(_trusted!.macReceiver))) {
            return _fail(BleTransferError.notTrusted);
          }
          _session = _SessionKeys(_trusted!.sessionKey, _trusted!.salt);
        } else {
          if (type != BleMessageType.confirm) return _fail(BleTransferError.protocol);
          if (!_keys!.verifyPeer(body)) return _fail(BleTransferError.wrongCode);
          _session = _SessionKeys(_keys!.sharedKey, _keys!.transcriptHash);
        }
        stage = ScoutSessionStage.waitingResult;
        final plain = payload.encode(senderInfo: identity.toInfoJson(includeBeacon: true));
        return [encodeMessage(BleMessageType.data, _session!.scoutToReceiver.seal(plain, [BleMessageType.data.code]))];

      case ScoutSessionStage.waitingResult:
        if (type != BleMessageType.result) return _fail(BleTransferError.protocol);
        try {
          final plain = _session!.receiverToScout.open(body, [BleMessageType.result.code]);
          result = BleTransferResult.decode(plain);
        } on BleProtocolException catch (e) {
          return _fail(e.error);
        }
        stage = ScoutSessionStage.finished;
        final info = result!.receiver;
        if (result!.ok && info != null) {
          if (trustedPeer != null) {
            if (info.idHex == trustedPeer!.id) trustToSave = trustedPeer!.refreshedFrom(info);
          } else if (result!.trust) {
            final now = DateTime.now();
            trustToSave = BleTrustedPeer(
              id: info.idHex,
              name: info.name,
              username: info.username,
              key: _pairingKey(_keys!),
              role: BleTrustRole.receiver,
              added: now,
              lastUsed: now,
            );
          }
        }
        return const [];

      case ScoutSessionStage.finished:
      case ScoutSessionStage.failed:
        return const [];
    }
  }

  List<Uint8List> _onHello(Uint8List body) {
    if (body.isEmpty || body[0] != BleTransferProtocol.version) return _fail(BleTransferError.unsupportedVersion);
    if (body.length != 1 + 2 + 65) return _fail(BleTransferError.protocol);
    peerMtu = ByteData.sublistView(body).getUint16(1);
    final spake = Spake2(
      role: Spake2Role.b,
      w: BleTransferProtocol.passwordScalar(tag, code),
      idA: BleTransferProtocol.idReceiver,
      idB: BleTransferProtocol.idScout,
      aad: BleTransferProtocol.aad(tag),
    );
    stage = ScoutSessionStage.waitingConfirm;
    _codeTried = true;
    try {
      _keys = spake.finish(body.sublist(3));
    } on Spake2Exception {
      return _fail(BleTransferError.protocol);
    }
    return [encodeMessage(BleMessageType.challenge, [...spake.message, ..._keys!.ownConfirmation])];
  }

  List<Uint8List> _onTrustedHello(Uint8List body) {
    if (body.isEmpty || body[0] != BleTransferProtocol.version) return _fail(BleTransferError.unsupportedVersion);
    const idLen = BleTransferProtocol.idLength;
    if (body.length != 1 + 2 + idLen + 65) return _fail(BleTransferError.protocol);
    peerMtu = ByteData.sublistView(body).getUint16(1);
    final receiverId = body.sublist(3, 3 + idLen);
    final receiverEphemeral = body.sublist(3 + idLen);
    final peer = trustedReceivers[bytesToHex(receiverId)];
    if (peer == null) return _fail(BleTransferError.notTrusted);
    final ecdh = EcdhP256();
    final Uint8List dh;
    try {
      dh = ecdh.sharedSecret(receiverEphemeral);
    } on Spake2Exception {
      return _fail(BleTransferError.protocol);
    }
    _trusted = _TrustedKeys(
      pairingKey: peer.key,
      dhSecret: dh,
      tag: tag,
      receiverId: receiverId,
      receiverEphemeral: receiverEphemeral,
      scoutId: identity.id,
      scoutEphemeral: ecdh.publicKey,
    );
    trustedPeer = peer;
    stage = ScoutSessionStage.waitingConfirm;
    return [
      encodeMessage(BleMessageType.trustedChallenge,
          [...identity.id, ...ecdh.publicKey, ..._trusted!.macFor(_trusted!.macScout)])
    ];
  }

  List<Uint8List> _fail(BleTransferError error) {
    failure = error;
    stage = ScoutSessionStage.failed;
    return [errorMessage(error)];
  }
}

enum ReceiverSessionStage { idle, waitingChallenge, waitingData, finished, failed }

/// The receiver's side of one connection.
class ReceiverSession {
  final String tag;
  final int mtu;
  final BleIdentity identity;

  /// Code sessions only: the code typed in and whether to trust the scout afterwards.
  final String? code;
  final bool requestTrust;

  /// Trusted sessions only: the scout this receiver expects.
  final BleTrustedPeer? expectedPeer;

  ReceiverSessionStage stage = ReceiverSessionStage.idle;
  BleTransferError? failure;
  BleTransferPayload? payload;

  /// After the entry arrived: the trust record to store (new pairing or refreshed names).
  BleTrustedPeer? trustToSave;

  Spake2? _spake;
  EcdhP256? _ecdh;
  Spake2Keys? _keys;
  _SessionKeys? _session;

  ReceiverSession.code({
    required this.tag,
    required String this.code,
    required this.mtu,
    required this.identity,
    this.requestTrust = false,
  }) : expectedPeer = null {
    _spake = Spake2(
      role: Spake2Role.a,
      w: BleTransferProtocol.passwordScalar(tag, code!),
      idA: BleTransferProtocol.idReceiver,
      idB: BleTransferProtocol.idScout,
      aad: BleTransferProtocol.aad(tag),
    );
  }

  ReceiverSession.trusted({
    required this.tag,
    required this.mtu,
    required this.identity,
    required BleTrustedPeer this.expectedPeer,
  })  : code = null,
        requestTrust = false {
    _ecdh = EcdhP256();
  }

  bool get isTrusted => expectedPeer != null;

  Uint8List hello() {
    stage = ReceiverSessionStage.waitingChallenge;
    final mtuBytes = (ByteData(2)..setUint16(0, mtu.clamp(23, 517))).buffer.asUint8List();
    if (isTrusted) {
      return encodeMessage(BleMessageType.trustedHello,
          [BleTransferProtocol.version, ...mtuBytes, ...identity.id, ..._ecdh!.publicKey]);
    }
    return encodeMessage(BleMessageType.hello, [BleTransferProtocol.version, ...mtuBytes, ..._spake!.message]);
  }

  /// Handles a message from the scout. Once [stage] is finished, import [payload] and send [buildResult].
  List<Uint8List> handle(Uint8List message) {
    if (message.isEmpty) return _fail(BleTransferError.protocol);
    final type = BleMessageType.fromCode(message[0]);
    final body = Uint8List.sublistView(message, 1);
    if (type == BleMessageType.error) {
      failure = body.isNotEmpty ? BleTransferError.fromCode(body[0]) : BleTransferError.protocol;
      stage = ReceiverSessionStage.failed;
      return const [];
    }
    switch (stage) {
      case ReceiverSessionStage.waitingChallenge:
        return isTrusted ? _onTrustedChallenge(type, body) : _onChallenge(type, body);

      case ReceiverSessionStage.waitingData:
        if (type != BleMessageType.data) return _fail(BleTransferError.protocol);
        try {
          final plain = _session!.scoutToReceiver.open(body, [BleMessageType.data.code]);
          payload = BleTransferPayload.decode(plain);
        } on BleProtocolException catch (e) {
          return _fail(e.error);
        }
        final sender = payload!.sender;
        if (isTrusted) {
          if (sender == null || sender.idHex != expectedPeer!.id) return _fail(BleTransferError.protocol);
          trustToSave = expectedPeer!.refreshedFrom(sender);
        } else if (requestTrust && sender != null) {
          final now = DateTime.now();
          trustToSave = BleTrustedPeer(
            id: sender.idHex,
            name: sender.name,
            username: sender.username,
            key: _pairingKey(_keys!),
            role: BleTrustRole.scout,
            beaconKey: sender.beaconKey,
            added: now,
            lastUsed: now,
          );
        }
        stage = ReceiverSessionStage.finished;
        return const [];

      case ReceiverSessionStage.idle:
      case ReceiverSessionStage.finished:
      case ReceiverSessionStage.failed:
        return _fail(BleTransferError.protocol);
    }
  }

  List<Uint8List> _onChallenge(BleMessageType? type, Uint8List body) {
    if (type != BleMessageType.challenge || body.length != 65 + 32) return _fail(BleTransferError.protocol);
    try {
      _keys = _spake!.finish(body.sublist(0, 65));
    } on Spake2Exception {
      return _fail(BleTransferError.protocol);
    }
    if (!_keys!.verifyPeer(body.sublist(65))) return _fail(BleTransferError.wrongCode);
    _session = _SessionKeys(_keys!.sharedKey, _keys!.transcriptHash);
    stage = ReceiverSessionStage.waitingData;
    return [encodeMessage(BleMessageType.confirm, _keys!.ownConfirmation)];
  }

  List<Uint8List> _onTrustedChallenge(BleMessageType? type, Uint8List body) {
    const idLen = BleTransferProtocol.idLength;
    if (type != BleMessageType.trustedChallenge || body.length != idLen + 65 + 32) {
      return _fail(BleTransferError.protocol);
    }
    final scoutId = body.sublist(0, idLen);
    final scoutEphemeral = body.sublist(idLen, idLen + 65);
    final mac = body.sublist(idLen + 65);
    if (bytesToHex(scoutId) != expectedPeer!.id) return _fail(BleTransferError.notTrusted);
    final Uint8List dh;
    try {
      dh = _ecdh!.sharedSecret(scoutEphemeral);
    } on Spake2Exception {
      return _fail(BleTransferError.protocol);
    }
    final keys = _TrustedKeys(
      pairingKey: expectedPeer!.key,
      dhSecret: dh,
      tag: tag,
      receiverId: identity.id,
      receiverEphemeral: _ecdh!.publicKey,
      scoutId: scoutId,
      scoutEphemeral: scoutEphemeral,
    );
    // A different key means one side re-paired; fall back to the code rather than calling it an attack.
    if (!constantTimeEquals(mac, keys.macFor(keys.macScout))) return _fail(BleTransferError.notTrusted);
    _session = _SessionKeys(keys.sessionKey, keys.salt);
    stage = ReceiverSessionStage.waitingData;
    return [encodeMessage(BleMessageType.trustedConfirm, keys.macFor(keys.macReceiver))];
  }

  /// Encrypted import result for the scout. Only valid after [payload] arrived.
  Uint8List buildResult(BleTransferResult result) {
    final plain = result.encode(receiverInfo: identity.toInfoJson(), trust: isTrusted || requestTrust);
    return encodeMessage(BleMessageType.result, _session!.receiverToScout.seal(plain, [BleMessageType.result.code]));
  }

  List<Uint8List> _fail(BleTransferError error) {
    failure = error;
    stage = ReceiverSessionStage.failed;
    return [errorMessage(error)];
  }
}
