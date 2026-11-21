/// SPAKE2 over P-256 with SHA-256, HKDF and HMAC (RFC 9382, ciphersuite SPAKE2-P256-SHA256-HKDF-HMAC).
///
/// Used to turn the short code a scout's phone shows into a strong session key. An eavesdropper who records the
/// whole exchange learns nothing that lets them test codes offline, and an active attacker gets exactly one guess
/// per handshake. The scout's phone retires its code after every handshake, so a wrong guess cannot be retried.
library;

import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';

/// RFC 9382 section 6 generator seeds for P-256, as compressed SEC1 points.
const String _mHex = '02886e2f97ace46e55ba9dd7242579f2993b64e16ef3dcab95afd497333d8fa12f';
const String _nHex = '03d8bbd6c639c62937b04d997f38c3770719c629d7014d49a24b4f98baa1292b49';

final ECDomainParameters _p256 = ECCurve_secp256r1();
final ECPoint _m = _p256.curve.decodePoint(hexToBytes(_mHex))!;
final ECPoint _n = _p256.curve.decodePoint(hexToBytes(_nHex))!;

/// Field prime of P-256, used for the curve equation check and the fixed width of w in the transcript.
final BigInt _fieldPrime = BigInt.parse('ffffffff00000001000000000000000000000000ffffffffffffffffffffffff', radix: 16);

const int _scalarBytes = 32;
const int _pointBytes = 65;

class Spake2Exception implements Exception {
  final String message;
  const Spake2Exception(this.message);
  @override
  String toString() => 'Spake2Exception: $message';
}

/// Keys that come out of one finished handshake.
class Spake2Keys {
  /// Shared secret (Ke). 16 bytes; expand it with HKDF before use.
  final Uint8List sharedKey;

  /// Confirmation MAC this side sends.
  final Uint8List ownConfirmation;

  /// Confirmation MAC the peer must send.
  final Uint8List expectedPeerConfirmation;

  /// SHA-256 of the transcript, handy as a session id or HKDF salt.
  final Uint8List transcriptHash;

  const Spake2Keys({
    required this.sharedKey,
    required this.ownConfirmation,
    required this.expectedPeerConfirmation,
    required this.transcriptHash,
  });

  /// Constant-time check of the peer's confirmation MAC.
  bool verifyPeer(List<int> confirmation) => constantTimeEquals(confirmation, expectedPeerConfirmation);
}

enum Spake2Role { a, b }

/// One side of a SPAKE2 run. A sends pA first; B answers with pB. Use a fresh instance per handshake.
class Spake2 {
  final Spake2Role role;
  final Uint8List idA;
  final Uint8List idB;
  final Uint8List aad;
  final BigInt _w;
  final BigInt _secret;
  late final Uint8List message;

  Spake2._(this.role, this.idA, this.idB, this.aad, this._w, this._secret) {
    final own = role == Spake2Role.a ? _m : _n;
    final point = (_p256.G * _secret)! + (own * _w)!;
    if (point == null || point.isInfinity) throw const Spake2Exception('degenerate public value');
    message = point.getEncoded(false);
  }

  /// Starts a handshake. [w] must already be reduced mod the group order (see [Spake2.passwordScalar]).
  factory Spake2({
    required Spake2Role role,
    required BigInt w,
    required List<int> idA,
    required List<int> idB,
    List<int> aad = const [],
    Random? random,
  }) {
    return Spake2._(role, Uint8List.fromList(idA), Uint8List.fromList(idB), Uint8List.fromList(aad), w,
        _randomScalar(random ?? Random.secure()));
  }

  /// Test hook: runs with a fixed secret scalar so the RFC vectors can be checked.
  factory Spake2.withSecret({
    required Spake2Role role,
    required BigInt w,
    required BigInt secret,
    required List<int> idA,
    required List<int> idB,
    List<int> aad = const [],
  }) {
    return Spake2._(role, Uint8List.fromList(idA), Uint8List.fromList(idB), Uint8List.fromList(aad), w, secret);
  }

  /// Maps a password to w: SHA-512 of the input (64 bits wider than the order, as RFC 9382 suggests), mod n.
  /// The short code is guessable offline only after the session is over, and the code is single use by then,
  /// so a memory-hard function would add delay without adding protection here.
  static BigInt passwordScalar(List<int> password) {
    final digest = sha512.convert(password).bytes;
    final w = _bytesToBigInt(digest) % _p256.n;
    return w == BigInt.zero ? BigInt.one : w;
  }

  /// Finishes the handshake with the peer's message and returns the session keys.
  Spake2Keys finish(List<int> peerMessage) {
    final peerPoint = decodePublicPoint(peerMessage);
    final peerBlind = role == Spake2Role.a ? _n : _m;
    final unblinded = peerPoint + (-(peerBlind * _w)!);
    if (unblinded == null || unblinded.isInfinity) throw const Spake2Exception('invalid peer value');
    // P-256 has cofactor 1, so h*x*(...) is x*(...).
    final k = (unblinded * _secret)!;
    if (k.isInfinity) throw const Spake2Exception('invalid shared point');

    final pA = role == Spake2Role.a ? message : Uint8List.fromList(peerMessage);
    final pB = role == Spake2Role.a ? Uint8List.fromList(peerMessage) : message;
    final tt = transcript(
      idA: idA,
      idB: idB,
      pA: pA,
      pB: pB,
      k: k.getEncoded(false),
      w: _bigIntToBytes(_w, _scalarBytes),
    );
    final hashTt = Uint8List.fromList(sha256.convert(tt).bytes);
    final ke = Uint8List.sublistView(hashTt, 0, 16);
    final ka = Uint8List.sublistView(hashTt, 16, 32);
    final kc = hkdfSha256(ikm: ka, salt: const [], info: [...'ConfirmationKeys'.codeUnits, ...aad], length: 32);
    final kcA = Uint8List.sublistView(kc, 0, 16);
    final kcB = Uint8List.sublistView(kc, 16, 32);
    final cA = Uint8List.fromList(Hmac(sha256, kcA).convert(tt).bytes);
    final cB = Uint8List.fromList(Hmac(sha256, kcB).convert(tt).bytes);
    return Spake2Keys(
      sharedKey: Uint8List.fromList(ke),
      ownConfirmation: role == Spake2Role.a ? cA : cB,
      expectedPeerConfirmation: role == Spake2Role.a ? cB : cA,
      transcriptHash: hashTt,
    );
  }

  /// RFC 9382 transcript: each field prefixed with its length as an 8-byte little-endian number.
  static Uint8List transcript({
    required List<int> idA,
    required List<int> idB,
    required List<int> pA,
    required List<int> pB,
    required List<int> k,
    required List<int> w,
  }) {
    final out = BytesBuilder(copy: false);
    for (final field in [idA, idB, pA, pB, k, w]) {
      final len = ByteData(8)..setUint64(0, field.length, Endian.little);
      out.add(len.buffer.asUint8List());
      out.add(field);
    }
    return out.takeBytes();
  }

  /// Decodes an uncompressed SEC1 point and rejects anything off the curve or at infinity.
  static ECPoint decodePublicPoint(List<int> encoded) {
    if (encoded.length != _pointBytes || encoded[0] != 0x04) {
      throw const Spake2Exception('expected an uncompressed P-256 point');
    }
    final x = _bytesToBigInt(encoded.sublist(1, 33));
    final y = _bytesToBigInt(encoded.sublist(33, 65));
    if (x >= _fieldPrime || y >= _fieldPrime) throw const Spake2Exception('coordinate out of range');
    final a = _p256.curve.a!.toBigInteger()!;
    final b = _p256.curve.b!.toBigInteger()!;
    final lhs = (y * y) % _fieldPrime;
    final rhs = (x * x * x + a * x + b) % _fieldPrime;
    if (lhs != rhs) throw const Spake2Exception('point is not on P-256');
    final point = _p256.curve.createPoint(x, y);
    if (point.isInfinity) throw const Spake2Exception('point at infinity');
    return point;
  }

  static BigInt _randomScalar(Random random) {
    // 64 bytes reduced mod n keeps the bias negligible.
    final bytes = Uint8List(64);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = random.nextInt(256);
    }
    final s = _bytesToBigInt(bytes) % _p256.n;
    return s == BigInt.zero ? BigInt.one : s;
  }
}

/// Ephemeral P-256 Diffie-Hellman, used by trusted-device sessions so a recording of one stays private even if
/// the long-term pairing key later leaks.
class EcdhP256 {
  final BigInt _secret;
  late final Uint8List publicKey;

  EcdhP256._(this._secret) {
    publicKey = (_p256.G * _secret)!.getEncoded(false);
  }

  factory EcdhP256({Random? random}) => EcdhP256._(Spake2._randomScalar(random ?? Random.secure()));

  /// The x-coordinate of the shared point. Rejects invalid peer keys.
  Uint8List sharedSecret(List<int> peerPublic) {
    final shared = Spake2.decodePublicPoint(peerPublic) * _secret;
    if (shared == null || shared.isInfinity) throw const Spake2Exception('invalid shared point');
    return _bigIntToBytes(shared.x!.toBigInteger()!, _scalarBytes);
  }
}

/// HKDF-SHA256 (RFC 5869).
Uint8List hkdfSha256({required List<int> ikm, required List<int> salt, required List<int> info, required int length}) {
  if (length > 255 * 32) throw ArgumentError.value(length, 'length');
  final prk = Hmac(sha256, salt.isEmpty ? List<int>.filled(32, 0) : salt).convert(ikm).bytes;
  final okm = BytesBuilder(copy: false);
  var previous = <int>[];
  var counter = 1;
  while (okm.length < length) {
    previous = Hmac(sha256, prk).convert([...previous, ...info, counter]).bytes;
    okm.add(previous);
    counter++;
  }
  return Uint8List.sublistView(okm.takeBytes(), 0, length);
}

bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Uint8List hexToBytes(String hex) {
  final clean = hex.replaceAll(RegExp(r'\s'), '');
  if (clean.length.isOdd) throw FormatException('odd-length hex', hex);
  final out = Uint8List(clean.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(clean.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(List<int> bytes) => bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

BigInt _bytesToBigInt(List<int> bytes) {
  var result = BigInt.zero;
  for (final b in bytes) {
    result = (result << 8) | BigInt.from(b);
  }
  return result;
}

Uint8List _bigIntToBytes(BigInt value, int length) {
  final out = Uint8List(length);
  var v = value;
  for (var i = length - 1; i >= 0; i--) {
    out[i] = (v & BigInt.from(0xff)).toInt();
    v = v >> 8;
  }
  return out;
}
