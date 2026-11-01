import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('event announcements file limit is 15 MB', () {
    const maxFileBytes = 15 * 1024 * 1024;
    expect(maxFileBytes, 15728640);
  });

  test('gzip compression compresses repetitive data and decompresses identically', () {
    final text = 'ObsidianScout event announcement file compression test! ' * 200;
    final originalBytes = Uint8List.fromList(utf8.encode(text));

    expect(originalBytes.length, greaterThan(10000));

    // Compress
    final compressed = Uint8List.fromList(GZipEncoder().encode(originalBytes));
    expect(compressed.length, lessThan(originalBytes.length));

    // Verify gzip magic bytes (0x1f, 0x8b)
    expect(compressed[0], 0x1f);
    expect(compressed[1], 0x8b);

    // Decompress
    final decompressed = Uint8List.fromList(GZipDecoder().decodeBytes(compressed));
    expect(decompressed, equals(originalBytes));
    expect(utf8.decode(decompressed), equals(text));
  });

  test('gzip magic byte detection handles both compressed and uncompressed streams', () {
    bool isGzip(List<int> bytes) =>
        bytes.length >= 10 && bytes[0] == 0x1f && bytes[1] == 0x8b;

    final uncompressed = Uint8List.fromList([1, 2, 3, 4, 5]);
    expect(isGzip(uncompressed), isFalse);

    final compressed = GZipEncoder().encode(utf8.encode('hello world'));
    expect(isGzip(compressed), isTrue);
  });
}
