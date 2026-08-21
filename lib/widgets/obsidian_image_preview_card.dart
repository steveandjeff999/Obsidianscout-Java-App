import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../services/image_utils.dart';
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
    final Uint8List? bytes = ImageProcessingUtils.dataUrlToBytes(imageSource);
    if (bytes == null) return;

    showDialog(
      context: context,
      builder: (dialogCtx) => Dialog(
        backgroundColor: Colors.black.withOpacity(0.94),
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
                  child: Image.memory(bytes, fit: BoxFit.contain),
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
    final Uint8List? imgBytes = ImageProcessingUtils.dataUrlToBytes(imageSource);

    if (imgBytes == null) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withOpacity(0.03) : Colors.black.withOpacity(0.02),
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
                    child: Image.memory(imgBytes, fit: BoxFit.contain),
                  ),
                ),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.75),
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
    final Uint8List? bytes = ImageProcessingUtils.dataUrlToBytes(imageSource);
    if (bytes == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => ObsidianImagePreviewCard.showZoomDialog(context, imageSource, title: title),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.cyanAccent.withOpacity(0.2),
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
              child: Image.memory(
                bytes,
                width: size,
                height: size,
                fit: BoxFit.cover,
              ),
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
