import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../models/security_models.dart';

/// The server's sign-in security check (in place of a CAPTCHA): find a counter such that
/// SHA-256("nonce:counter") starts with `difficulty` zero bits. About a second on a phone, run off the UI thread.
class SecurityPow {
  static const String header = 'X-Security-Challenge';

  /// True when SHA-256("[nonce]:[counter]") starts with [bits] zero bits.
  static bool meetsDifficulty(String nonce, int counter, int bits) {
    final digest = sha256.convert(utf8.encode('$nonce:$counter')).bytes;
    var remaining = bits;
    for (final b in digest) {
      if (remaining >= 8) {
        if (b != 0) return false;
        remaining -= 8;
        if (remaining == 0) return true;
      } else {
        return remaining == 0 || (b >> (8 - remaining)) == 0;
      }
    }
    return true;
  }

  static int _solve(List<Object> args) {
    final nonce = args[0] as String;
    final bits = args[1] as int;
    var counter = 0;
    while (!meetsDifficulty(nonce, counter, bits)) {
      counter++;
    }
    return counter;
  }

  /// Solves [challenge] and returns the answer the server expects ("token:counter").
  static Future<String> solve(PowChallenge challenge) async {
    final bits = challenge.difficulty.clamp(1, 24);
    final counter = await compute(_solve, <Object>[challenge.nonce, bits]);
    return '${challenge.token}:$counter';
  }
}
