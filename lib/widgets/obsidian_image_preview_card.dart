import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/image_utils.dart';
import '../services/photo_values.dart';
import 'cached_server_image.dart';
import '../theme/obsidian_ui_theme.dart';

class ObsidianImagePreviewCard extends StatelessWidget {
  final String label;
  final String? imageSource;
  final double height;

  const ObsidianImagePreviewCard({
    super.key,
    required this.label,
    required this.imageSource,
    this.height = 180,
  });

  static void showZoomDialog(BuildContext context, String? imageSource, {String title = 'Photo Preview'}) {
    final Widget? image = photoWidget(imageSource, fit: BoxFit.contain);
    if (image == null) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.black.withValues(alpha: 0.94),
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        const Icon(Icons.camera_alt_rounded, color: Colors.cyanAccent, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white70),
                    onPressed: () => Navigator.pop(dialogCtx),
                  ),
                ],
              ),
            ),
            Flexible(
              child: InteractiveViewer(
                panEnabled: true,
                minScale: 0.5,
                maxScale: 4.0,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: image,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final Widget? image = photoWidget(imageSource, fit: BoxFit.contain);

    if (image == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty) ...[
            Row(
              children: [
                const Icon(Icons.photo_camera_rounded, size: 16, color: Colors.cyanAccent),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: primaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
          GestureDetector(
            onTap: () => showZoomDialog(context, imageSource, title: label.isNotEmpty ? label : 'Photo Preview'),
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  height: height,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: Colors.black45,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: image,
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.zoom_in_rounded, size: 14, color: Colors.cyanAccent),
                      SizedBox(width: 4),
                      Text(
                        'Tap to Zoom',
                        style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ObsidianImageThumbnail extends StatelessWidget {
  final String? imageSource;
  final double size;
  final String title;

  const ObsidianImageThumbnail({
    super.key,
    required this.imageSource,
    this.size = 44,
    this.title = 'Photo Preview',
  });

  @override
  Widget build(BuildContext context) {
    final Widget? image = photoWidget(imageSource, width: size, height: size, fit: BoxFit.cover);
    if (image == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => ObsidianImagePreviewCard.showZoomDialog(context, imageSource, title: title),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withValues(alpha: 0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withValues(alpha: 0.2),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(7),
              child: image,
            ),
            Positioned(
              right: 2,
              bottom: 2,
              child: Container(
                padding: const EdgeInsets.all(1.5),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: const Icon(Icons.zoom_in, color: Colors.cyanAccent, size: 10),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A photo value as a widget: a base64 data URL decoded in place, or a blob-store path loaded from the server
/// (cached on the device). Null when [source] is neither.
Widget? photoWidget(String? source, {double? width, double? height, BoxFit? fit}) {
  if (source == null || source.isEmpty) return null;
  if (isBlobPhotoPath(source)) {
    final url = resolveBlobPhotoUrl(source);
    if (url == null) return null;
    return CachedServerImage(
      url: url,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_) => SizedBox(
        width: width,
        height: height,
        child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.white38)),
      ),
    );
  }
  final Uint8List? bytes = ImageProcessingUtils.dataUrlToBytes(source);
  if (bytes == null) return null;
  return Image.memory(bytes, width: width, height: height, fit: fit);
}
