import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:obsidianscout_app/services/image_utils.dart';

void main() {
  group('ImageProcessingUtils Tests', () {
    test('processImageBytes encodes image to WebP with correct metadata and headers', () {
      // Create a 2400x1600 test image (simulating high-res camera capture)
      final testImage = img.Image(width: 2400, height: 1600);
      img.fill(testImage, color: img.ColorRgb8(0, 150, 255));
      final rawJpegBytes = Uint8List.fromList(img.encodeJpg(testImage));

      final result = ImageProcessingUtils.processImageBytes(
        rawJpegBytes,
        maxDimension: 1920,
        quality: 76,
      );

      expect(result, isNotNull);
      expect(result!.format, equals('WebP'));
      expect(result.dataUrl.startsWith('data:image/webp;base64,'), isTrue);
      expect(result.width, equals(1920));
      expect(result.height, equals(1280));
      expect(result.sizeBytes, greaterThan(0));

      // Decoded bytes should start with RIFF...WEBP header
      final decodedBytes = ImageProcessingUtils.dataUrlToBytes(result.dataUrl);
      expect(decodedBytes, isNotNull);
      expect(decodedBytes!.length, equals(result.sizeBytes));
      // RIFF header
      expect(decodedBytes[0], equals(0x52)); // 'R'
      expect(decodedBytes[1], equals(0x49)); // 'I'
      expect(decodedBytes[2], equals(0x46)); // 'F'
      expect(decodedBytes[3], equals(0x46)); // 'F'
      // WEBP signature at bytes 8-11
      expect(decodedBytes[8], equals(0x57));  // 'W'
      expect(decodedBytes[9], equals(0x45));  // 'E'
      expect(decodedBytes[10], equals(0x42)); // 'B'
      expect(decodedBytes[11], equals(0x50)); // 'P'
    });

    test('processImageBytesAsync runs in background isolate and produces valid WebP', () async {
      final testImage = img.Image(width: 800, height: 600);
      img.fill(testImage, color: img.ColorRgb8(255, 100, 50));
      final rawPngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = await ImageProcessingUtils.processImageBytesAsync(
        rawPngBytes,
        maxDimension: 1920,
        quality: 76,
      );

      expect(result, isNotNull);
      expect(result!.dataUrl.startsWith('data:image/webp;base64,'), isTrue);
      expect(result.width, equals(800)); // Doesn't upscale if below maxDimension
      expect(result.height, equals(600));
      expect(result.formattedSize, contains('KB (WebP)'));
    });

    test('dataUrlToBytes gracefully handles null and malformed strings', () {
      expect(ImageProcessingUtils.dataUrlToBytes(null), isNull);
      expect(ImageProcessingUtils.dataUrlToBytes(''), isNull);
      expect(ImageProcessingUtils.dataUrlToBytes('not-a-valid-base-64'), isNull);
    });

    test('compressDataUrlForTransportation generates compact thumbnail', () {
      final testImage = img.Image(width: 600, height: 400);
      img.fill(testImage, color: img.ColorRgb8(10, 200, 100));
      final rawJpeg = Uint8List.fromList(img.encodeJpg(testImage));
      final processed = ImageProcessingUtils.processImageBytes(rawJpeg);
      expect(processed, isNotNull);

      final thumbUrl = ImageProcessingUtils.compressDataUrlForTransportation(
        processed!.dataUrl,
        maxDimension: 160,
        quality: 35,
      );

      expect(thumbUrl, isNotNull);
      expect(thumbUrl!.startsWith('data:image/webp;base64,'), isTrue);
      final thumbBytes = ImageProcessingUtils.dataUrlToBytes(thumbUrl);
      expect(thumbBytes, isNotNull);
      expect(thumbBytes!.length, lessThan(processed.sizeBytes));
    });
  });
}
