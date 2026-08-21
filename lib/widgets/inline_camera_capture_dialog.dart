import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import '../services/image_utils.dart';
import '../theme/obsidian_ui_theme.dart';

class InlineCameraCaptureDialog extends StatefulWidget {
  final int maxDimension;
  final int quality;

  const InlineCameraCaptureDialog({
    super.key,
    this.maxDimension = 540,
    this.quality = 65,
  });

  static Future<ProcessedImageResult?> show(
    BuildContext context, {
    int maxDimension = 540,
    int quality = 65,
  }) async {
    return showDialog<ProcessedImageResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => InlineCameraCaptureDialog(
        maxDimension: maxDimension,
        quality: quality,
      ),
    );
  }

  @override
  State<InlineCameraCaptureDialog> createState() => _InlineCameraCaptureDialogState();
}

class _InlineCameraCaptureDialogState extends State<InlineCameraCaptureDialog> {
  List<CameraDescription> _cameras = [];
  CameraController? _controller;
  int _selectedCameraIndex = 0;
  bool _isInitializing = true;
  bool _isCapturing = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    setState(() {
      _isInitializing = true;
      _errorMessage = null;
    });

    try {
      _cameras = await availableCameras();
      if (_cameras.isEmpty) {
        if (mounted) {
          setState(() {
            _isInitializing = false;
            _errorMessage = 'No camera devices detected on this system.';
          });
        }
        return;
      }

      bool success = false;
      for (int i = 0; i < _cameras.length; i++) {
        success = await _tryInitIndex(i);
        if (success) break;
      }

      if (!success && mounted) {
        setState(() {
          _isInitializing = false;
          _errorMessage = 'Could not initialize camera preview.';
        });
      }
    } catch (e) {
      if (mounted) {
        String msg = 'Camera error: $e';
        if (e is MissingPluginException || e.toString().contains('MissingPluginException')) {
          msg = 'Camera plugin not linked. Please restart the app.';
        }
        setState(() {
          _isInitializing = false;
          _errorMessage = msg;
        });
      }
    }
  }

  Future<bool> _tryInitIndex(int index) async {
    if (index < 0 || index >= _cameras.length) return false;

    if (_controller != null) {
      final old = _controller!;
      _controller = null;
      try {
        await old.dispose();
      } catch (_) {}
    }

    _selectedCameraIndex = index;
    final camera = _cameras[index];

    final presets = [
      ResolutionPreset.high,
      ResolutionPreset.medium,
      ResolutionPreset.low,
    ];

    for (final preset in presets) {
      try {
        final ctrl = CameraController(
          camera,
          preset,
          enableAudio: false,
          imageFormatGroup: ImageFormatGroup.jpeg,
        );
        await ctrl.initialize();
        if (mounted) {
          setState(() {
            _controller = ctrl;
            _isInitializing = false;
            _errorMessage = null;
          });
          return true;
        }
      } catch (_) {}
    }

    return false;
  }

  Future<void> _capturePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isCapturing) return;

    setState(() {
      _isCapturing = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      final Uint8List rawBytes = await photo.readAsBytes();

      final result = ImageProcessingUtils.processImageBytes(
        rawBytes,
        maxDimension: widget.maxDimension,
        quality: widget.quality,
      );

      if (mounted) {
        Navigator.of(context).pop(result);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Capture failed: $e')),
        );
        setState(() {
          _isCapturing = false;
        });
      }
    }
  }

  Future<void> _fallbackPickFromGallery() async {
    final result = await ImageProcessingUtils.pickAndProcessImage(
      source: ImageSource.gallery,
      maxDimension: widget.maxDimension,
      quality: widget.quality,
    );
    if (result != null && mounted) {
      Navigator.of(context).pop(result);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final surfaceColor = isDark ? const Color(0xFF0F172A) : Colors.white;
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return Dialog(
      backgroundColor: surfaceColor,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: borderColor),
      ),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 680),
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.camera_alt_rounded, color: ObsidianUITheme.primaryAccent, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Inline Camera Capture',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: primaryTextColor,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Camera preview area
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white12),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: _buildCameraBody(),
                ),
              ),
            ),
            const SizedBox(height: 14),

            // Controls
            Row(
              children: [
                if (_cameras.length > 1)
                  IconButton.filledTonal(
                    onPressed: _isCapturing
                        ? null
                        : () {
                            final nextIndex = (_selectedCameraIndex + 1) % _cameras.length;
                            _tryInitIndex(nextIndex);
                          },
                    icon: const Icon(Icons.flip_camera_ios_rounded, size: 20),
                    tooltip: 'Switch Camera',
                  ),
                if (_cameras.length > 1) const SizedBox(width: 10),

                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (_controller != null && _controller!.value.isInitialized && !_isCapturing)
                        ? _capturePhoto
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ObsidianUITheme.primaryAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    icon: _isCapturing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.camera, size: 20),
                    label: Text(
                      _isCapturing ? 'Processing...' : 'Capture Snapshot',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCameraBody() {
    if (_isInitializing) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(strokeWidth: 2.5, color: ObsidianUITheme.primaryAccent),
            SizedBox(height: 12),
            Text('Accessing camera...', style: TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }

    if (_errorMessage != null || _controller == null || !_controller!.value.isInitialized) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.videocam_off_rounded, size: 40, color: Colors.redAccent),
              const SizedBox(height: 10),
              Text(
                _errorMessage ?? 'Camera preview unavailable.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _fallbackPickFromGallery,
                icon: const Icon(Icons.photo_library, size: 16),
                label: const Text('Choose Image File Instead'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white12,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        Center(
          child: CameraPreview(_controller!),
        ),
        Positioned(
          bottom: 10,
          left: 10,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.circle, color: Colors.greenAccent, size: 8),
                const SizedBox(width: 6),
                Text(
                  _formatCameraName(_cameras[_selectedCameraIndex].name),
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  String _formatCameraName(String rawName) {
    if (rawName.isEmpty) return 'Live Camera';
    if (rawName.contains('<')) {
      final idx = rawName.indexOf('<');
      final prefix = rawName.substring(0, idx).trim();
      if (prefix.isNotEmpty) return prefix;
    }
    if (rawName.contains('#')) {
      final parts = rawName.split('#');
      if (parts.isNotEmpty && parts[0].trim().isNotEmpty) {
        return parts[0].trim();
      }
    }
    return rawName;
  }
}
