import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

class ProcessedImageResult {
  final String dataUrl;
  final int width;
  final int height;
  final int sizeBytes;

  ProcessedImageResult({
    required this.dataUrl,
    required this.width,
    required this.height,
    required this.sizeBytes,
  });

  String get formattedSize => '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
}

class ImageProcessingUtils {
  static final ImagePicker _picker = ImagePicker();

  /// Captures an image using the device camera or picks from gallery,
  /// then strips EXIF/GPS metadata, downscales if UHD (max 540px), and compresses to JPEG.
  static Future<ProcessedImageResult?> pickAndProcessImage({
    required ImageSource source,
    int maxDimension = 540,
    int quality = 65,
  }) async {
    try {
      final XFile? pickedFile = await _picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (pickedFile == null) return null;

      final Uint8List rawBytes = await pickedFile.readAsBytes();
      return processImageBytes(
        rawBytes,
        maxDimension: maxDimension,
        quality: quality,
      );
    } catch (e) {
      return null;
    }
  }

  /// Strips EXIF/GPS/device metadata and polyglots by decoding and re-encoding pixel buffer,
  /// downscales if exceeding maxDimension (e.g., 540px), and encodes to optimized JPEG.
  static ProcessedImageResult? processImageBytes(
    Uint8List rawBytes, {
    int maxDimension = 540,
    int quality = 65,
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
          height = ((height * maxDimension) / width).round();
          width = maxDimension;
        } else {
          width = ((width * maxDimension) / height).round();
          height = maxDimension;
        }

        decoded = img.copyResize(
          decoded,
          width: width,
          height: height,
          interpolation: img.Interpolation.linear,
        );
      }

      // Re-encoding via encodeJpg eliminates all raw EXIF/GPS/camera chunks
      final Uint8List jpgBytes = Uint8List.fromList(
        img.encodeJpg(decoded, quality: quality),
      );

      final String base64Str = base64Encode(jpgBytes);
      final String dataUrl = 'data:image/jpeg;base64,$base64Str';

      return ProcessedImageResult(
        dataUrl: dataUrl,
        width: width,
        height: height,
        sizeBytes: jpgBytes.length,
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
}
