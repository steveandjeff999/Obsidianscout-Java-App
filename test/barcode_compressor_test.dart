import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/widgets/obsidian_barcode_modal.dart';

void main() {
  group('BarcodeCompressor', () {
    test('round-trips compressed OSC: payloads with Zlib framing', () {
      const payload = '{"team":9999,"match":"qm12","notes":"Defense & passing accuracy test 12345"}';
      final compressed = BarcodeCompressor.compressData(payload);

      expect(compressed, startsWith('OSC:'));
      expect(BarcodeCompressor.decompressData(compressed), equals(payload));
    });

    test('decompresses raw zlib.encode output prefixed with OSC:', () {
      const payload = 'Hello ObsidianScout QR zlib compatibility!';
      final encoded = 'OSC:${base64.encode(zlib.encode(utf8.encode(payload)))}';

      expect(BarcodeCompressor.decompressData(encoded), equals(payload));
    });

    test('returns uncompressed strings verbatim when OSC: prefix is absent', () {
      const payload = '{"plain":true}';
      expect(BarcodeCompressor.decompressData(payload), equals(payload));
    });

    test('rejects decompressed payloads exceeding 512 KB bomb limit', () {
      final oversized = 'A' * (512 * 1024 + 1024);
      final bombPayload = 'OSC:${base64.encode(zlib.encode(utf8.encode(oversized)))}';

      expect(BarcodeCompressor.decompressData(bombPayload), isEmpty);
    });

    test('returns empty string for corrupted OSC: zlib payload', () {
      expect(BarcodeCompressor.decompressData('OSC:not-valid-zlib!!!'), isEmpty);
    });
  });
}
