import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/security_models.dart';
import 'package:obsidianscout_app/services/security_pow.dart';

void main() {
  test('an IP block refusal is recognized, other refusals are not', () {
    final info = IpBlockInfo.tryParse({
      'success': false,
      'error': 'Your network is temporarily blocked',
      'errorCode': 'IP_BLOCKED',
      'code': 'ip_blocked',
      'blockId': 'abc',
      'expiresAt': 1700000000000,
      'retryAfterSeconds': 300,
      'unblockRequestsEnabled': true,
    });
    expect(info, isNotNull);
    expect(info!.blockId, 'abc');
    expect(info.retryAfterSeconds, 300);
    expect(IpBlockInfo.tryParse({'error': 'Admin access required'}), isNull);
    expect(IpBlockInfo.tryParse('not json'), isNull);
  });

  test('the security summary reads every field the server sends', () {
    final summary = SecuritySummary.fromJson({
      'enabled': true,
      'mode': 'enforce',
      'autoRevokeSessions': false,
      'maxBlockMinutes': 60,
      'activeBlocks': 2,
      'pendingUnblockRequests': 1,
      'protectedAccounts': 0,
      'credentialStuffingActive': false,
      'eventsLast24h': {'SCANNER_PATH': 4},
      'timeline': [
        {'hourStart': 0, 'low': 1, 'medium': 2, 'high': 3, 'info': 4}
      ],
      'topOffenders': [
        {'ip': '203.0.113.5', 'score': 104.5, 'level': 'BLOCK', 'lastEventAt': 1, 'lastEventType': 'INJECTION_PROBE'}
      ],
      'droppedEvents': 0,
    });
    expect(summary.enforcing, isTrue);
    expect(summary.maxBlockMinutes, 60);
    expect(summary.timeline.single.total, 10);
    expect(summary.topOffenders.single.score, 104.5);
    expect(summary.eventsLast24h['SCANNER_PATH'], 4);
  });

  test('a solved security check has the leading zero bits the server checks for', () async {
    const challenge = PowChallenge(token: 'tok.sig', nonce: '00112233445566778899aabbccddeeff', difficulty: 12, expiresAt: 0);
    final answer = await SecurityPow.solve(challenge);
    expect(answer.startsWith('tok.sig:'), isTrue);
    final counter = answer.substring(answer.lastIndexOf(':') + 1);
    final digest = sha256.convert(utf8.encode('${challenge.nonce}:$counter')).bytes;
    expect(digest[0], 0);
    expect(digest[1] >> 4, 0);
    expect(SecurityPow.meetsDifficulty(challenge.nonce, int.parse(counter), 12), isTrue);
  });

  test('a protected account keeps its team and program, and clears by its account key', () {
    final a = ProtectedAccount.fromJson({
      'account': 'admin|254|FRC',
      'username': 'admin',
      'teamNumber': 254,
      'program': 'FRC',
      'protectedUntil': 1700000000000,
    });
    expect(a.account, 'admin|254|FRC');
    expect(a.label, 'admin (team 254 FRC)');
    expect(ProtectedAccount.fromJson({'username': 'x', 'protectedUntil': 1}).label, 'x');
  });
}
