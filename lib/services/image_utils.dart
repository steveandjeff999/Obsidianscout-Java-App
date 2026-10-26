import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'net/link_quality.dart';

class ProcessedImageResult {
  final String dataUrl;
  final int width;
  final int height;
  final int sizeBytes;
  final String format;

  ProcessedImageResult({
    required this.dataUrl,
    required this.width,
    required this.height,
    required this.sizeBytes,
    this.format = 'WebP',
  });

  String get formattedSize => '${(sizeBytes / 1024).toStringAsFixed(1)} KB ($format)';
}

class ImageProcessingUtils {
  static final ImagePicker _picker = ImagePicker();

  /// Size budget for an uploaded photo; the encoder steps down once to stay near it.
  static const int defaultBudgetBytes = 300 * 1024;

  /// On a slow link a photo is uploaded smaller: still readable for a robot photo, about a third of the bytes.
  static const int slowLinkMaxDimension = 960;
  static const int slowLinkQuality = 64;
  static const int slowLinkBudgetBytes = 120 * 1024;

  /// Captures an image using the device camera or picks from gallery,
  /// then strips EXIF/GPS metadata, downscales to at most 1280px (the server's limit),
  /// and compresses to WebP (usually ~150–300 KB) in a background isolate.
  static Future<ProcessedImageResult?> pickAndProcessImage({
    required ImageSource source,
    int maxDimension = 1280,
    int quality = 76,
  }) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 95,
      );

      if (pickedFile == null) return null;

      final Uint8List rawBytes = await pickedFile.readAsBytes();
      return await processImageBytesAsync(
        rawBytes,
        maxDimension: maxDimension,
        quality: quality,
      );
    } catch (e) {
      return null;
    }
  }

  /// Offloads CPU-intensive image decoding, resizing, and WebP compression
  /// to a background Dart isolate to keep the UI thread completely fluid.
  /// On a slow link ([slowLink], by default the measured link) the photo is made smaller.
  static Future<ProcessedImageResult?> processImageBytesAsync(
    Uint8List rawBytes, {
    int maxDimension = 1280,
    int quality = 76,
    bool? slowLink,
  }) async {
    var budgetBytes = defaultBudgetBytes;
    if (slowLink ?? LinkQuality.instance.isLowBandwidth) {
      if (maxDimension > slowLinkMaxDimension) maxDimension = slowLinkMaxDimension;
      if (quality > slowLinkQuality) quality = slowLinkQuality;
      budgetBytes = slowLinkBudgetBytes;
    }
    try {
      return await Isolate.run(() => processImageBytes(
        rawBytes,
        maxDimension: maxDimension,
        quality: quality,
        budgetBytes: budgetBytes,
      ));
    } catch (_) {
      // Fallback to synchronous processing if isolate spawn fails
      return processImageBytes(
        rawBytes,
        maxDimension: maxDimension,
        quality: quality,
        budgetBytes: budgetBytes,
      );
    }
  }

  /// Strips EXIF/GPS/device metadata by decoding and re-encoding pixel buffer,
  /// downscales if exceeding maxDimension (e.g. 1280px), and encodes to lossy WebP
  /// (usually ~150–300 KB).
  static ProcessedImageResult? processImageBytes(
    Uint8List rawBytes, {
    int maxDimension = 1280,
    int quality = 76,
    int budgetBytes = defaultBudgetBytes,
  }) {
    try {
      img.Image? decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      // Bake EXIF orientation so pixel coordinates match visual display
      decoded = img.bakeOrientation(decoded);

      int width = decoded.width;
      int height = decoded.height;

      if (width > maxDimension || height > maxDimension) {
        if (width > height) {
          height = ((height * maxDimension) / width).round().clamp(1, maxDimension);
          width = maxDimension;
        } else {
          width = ((width * maxDimension) / height).round().clamp(1, maxDimension);
          height = maxDimension;
        }

        decoded = img.copyResize(
          decoded,
          width: width,
          height: height,
          interpolation: img.Interpolation.linear,
        );
      }

      // Encode lossy WebP (lossless: false enables quality-based compression)
      Uint8List webpBytes = Uint8List.fromList(
        img.encodeWebP(decoded, lossless: false, quality: quality, method: 4),
      );

      // Adaptive size pass: if high-frequency noise pushes the image over the budget,
      // downscale slightly and lower quality to stay near it.
      if (webpBytes.length > budgetBytes) {
        final int targetMaxDim = (maxDimension * 0.8).round().clamp(640, 1280);
        final int targetQ = (quality - 8).clamp(55, 75);

        int adaptiveW = decoded.width;
        int adaptiveH = decoded.height;
        if (adaptiveW > targetMaxDim || adaptiveH > targetMaxDim) {
          if (adaptiveW > adaptiveH) {
            adaptiveH = ((adaptiveH * targetMaxDim) / adaptiveW).round().clamp(1, targetMaxDim);
            adaptiveW = targetMaxDim;
          } else {
            adaptiveW = ((adaptiveW * targetMaxDim) / adaptiveH).round().clamp(1, targetMaxDim);
            adaptiveH = targetMaxDim;
          }

          decoded = img.copyResize(
            decoded,
            width: adaptiveW,
            height: adaptiveH,
            interpolation: img.Interpolation.linear,
          );
          width = adaptiveW;
          height = adaptiveH;
        }

        webpBytes = Uint8List.fromList(
          img.encodeWebP(decoded, lossless: false, quality: targetQ, method: 4),
        );
      }

      final String base64Str = base64Encode(webpBytes);
      final String dataUrl = 'data:image/webp;base64,$base64Str';

      return ProcessedImageResult(
        dataUrl: dataUrl,
        width: width,
        height: height,
        sizeBytes: webpBytes.length,
        format: 'WebP',
      );
    } catch (e) {
      return null;
    }
  }

  /// Converts a data URI (or raw base64 string) to Uint8List for display
  static Uint8List? dataUrlToBytes(String? dataUrl) {
    if (dataUrl == null || dataUrl.isEmpty) return null;
    try {
      String clean = dataUrl.trim();
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  /// Compresses an image data URI down to an ultra-compact ~2-3KB thumbnail suitable for QR transportation
  static String? compressDataUrlForTransportation(
    String dataUrl, {
    int maxDimension = 320,
    int quality = 45,
  }) {
    try {
      final bytes = dataUrlToBytes(dataUrl);
      if (bytes == null) return null;
      final result = processImageBytes(
        bytes,
        maxDimension: maxDimension,
        quality: quality,
      );
      return result?.dataUrl;
    } catch (_) {
      return null;
    }
  }

  /// Picks and processes an avatar image: centre-crops to a square, resizes to size px, and encodes to data URL.
  static Future<ProcessedImageResult?> pickAndProcessAvatar({
    required ImageSource source,
    int size = 384,
    int quality = 80,
  }) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 90,
      );

      if (pickedFile == null) return null;

      final Uint8List rawBytes = await pickedFile.readAsBytes();
      img.Image? decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;

      decoded = img.bakeOrientation(decoded);

      // Centre crop to square
      final int minDim = decoded.width < decoded.height ? decoded.width : decoded.height;
      final int x = (decoded.width - minDim) ~/ 2;
      final int y = (decoded.height - minDim) ~/ 2;

      img.Image cropped = img.copyCrop(decoded, x: x, y: y, width: minDim, height: minDim);
      img.Image resized = img.copyResize(cropped, width: size, height: size, interpolation: img.Interpolation.linear);

      final Uint8List pngBytes = Uint8List.fromList(img.encodePng(resized));
      final String base64Str = base64Encode(pngBytes);
      final String dataUrl = 'data:image/png;base64,$base64Str';

      return ProcessedImageResult(
        dataUrl: dataUrl,
        width: size,
        height: size,
        sizeBytes: pngBytes.length,
      );
    } catch (e) {
      return null;
    }
  }
}
