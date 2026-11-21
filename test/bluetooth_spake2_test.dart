import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/services/bluetooth/spake2.dart';

BigInt _hex(String s) => BigInt.parse(s.replaceAll(RegExp(r'\s'), ''), radix: 16);

void main() {
  group('SPAKE2 P-256 matches RFC 9382 Appendix B', () {
    // Vector 1: A='server', B='client'.
    final w = _hex('2ee57912099d31560b3a44b1184b9b4866e904c49d12ac5042c97dca461b1a5f');
    final x = _hex('43dd0fd7215bdcb482879fca3220c6a968e66d70b1356cac18bb26c84a78d729');
    final y = _hex('dcb60106f276b02606d8ef0a328c02e4b629f84f89786af5befb0bc75b6e66be');
    const pA = '04a56fa807caaa53a4d28dbb9853b9815c61a411118a6fe516a8798434751470'
        'f9010153ac33d0d5f2047ffdb1a3e42c9b4e6be662766e1eeb4116988ede5f912c';
    const pB = '0406557e482bd03097ad0cbaa5df82115460d951e3451962f1eaf4367a420676'
        'd09857ccbc522686c83d1852abfa8ed6e4a1155cf8f1543ceca528afb591a1e0b7';

    Spake2 side(Spake2Role role, BigInt secret) => Spake2.withSecret(
          role: role,
          w: w,
          secret: secret,
          idA: utf8.encode('server'),
          idB: utf8.encode('client'),
        );

    test('public values', () {
      expect(bytesToHex(side(Spake2Role.a, x).message), pA);
      expect(bytesToHex(side(Spake2Role.b, y).message), pB);
    });

    test('keys and confirmations', () {
      final a = side(Spake2Role.a, x).finish(hexToBytes(pB));
      final b = side(Spake2Role.b, y).finish(hexToBytes(pA));
      expect(bytesToHex(a.sharedKey), '0e0672dc86f8e45565d338b0540abe69');
      expect(bytesToHex(b.sharedKey), '0e0672dc86f8e45565d338b0540abe69');
      expect(bytesToHex(a.ownConfirmation), '58ad4aa88e0b60d5061eb6b5dd93e80d9c4f00d127c65b3b35b1b5281fee38f0');
      expect(bytesToHex(b.ownConfirmation), 'd3e2e547f1ae04f2dbdbf0fc4b79f8ecff2dff314b5d32fe9fcef2fb26dc459b');
      expect(a.verifyPeer(b.ownConfirmation), isTrue);
      expect(b.verifyPeer(a.ownConfirmation), isTrue);
    });
  });

  test('random handshake agrees with the same password and fails with a different one', () {
    final good = Spake2.passwordScalar(utf8.encode('123456'));
    final bad = Spake2.passwordScalar(utf8.encode('123457'));
    final a = Spake2(role: Spake2Role.a, w: good, idA: [1], idB: [2]);
    final b = Spake2(role: Spake2Role.b, w: good, idA: [1], idB: [2]);
    final ka = a.finish(b.message);
    final kb = b.finish(a.message);
    expect(ka.sharedKey, kb.sharedKey);
    expect(kb.verifyPeer(ka.ownConfirmation), isTrue);

    final wrong = Spake2(role: Spake2Role.a, w: bad, idA: [1], idB: [2]);
    final b2 = Spake2(role: Spake2Role.b, w: good, idA: [1], idB: [2]);
    final kWrong = wrong.finish(b2.message);
    final kB2 = b2.finish(wrong.message);
    expect(kB2.verifyPeer(kWrong.ownConfirmation), isFalse);
    expect(kWrong.verifyPeer(kB2.ownConfirmation), isFalse);
  });

  test('rejects points that are not on the curve', () {
    final b = Spake2(role: Spake2Role.b, w: BigInt.from(7), idA: const [], idB: const []);
    final bogus = List<int>.filled(65, 1)..[0] = 4;
    expect(() => b.finish(bogus), throwsA(isA<Spake2Exception>()));
    expect(() => b.finish(List<int>.filled(33, 2)), throwsA(isA<Spake2Exception>()));
  });

  test('HKDF-SHA256 matches RFC 5869 test case 1', () {
    final okm = hkdfSha256(
      ikm: List<int>.filled(22, 0x0b),
      salt: hexToBytes('000102030405060708090a0b0c'),
      info: hexToBytes('f0f1f2f3f4f5f6f7f8f9'),
      length: 42,
    );
    expect(bytesToHex(okm),
        '3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865');
  });
}
