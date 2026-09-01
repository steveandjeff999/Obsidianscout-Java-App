import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// A robust circular user avatar widget that supports:
/// - Base64 Data URIs (e.g. data:image/png;base64,...)
/// - Raw Base64 image strings
/// - Remote HTTP/HTTPS URLs
/// - Relative server image paths (e.g. /api/... or img/...)
/// - Automatic fallback to initials with deterministic hue-based background
class ObsidianUserAvatar extends StatelessWidget {
  final String? profilePicture;
  final String username;
  final double size;
  final String? serverUrl;
  final double? fontSize;
  final Color? borderColor;
  final double borderWidth;
  final List<BoxShadow>? boxShadow;
  final VoidCallback? onTap;

  const ObsidianUserAvatar({
    super.key,
    required this.profilePicture,
    required this.username,
    this.size = 48.0,
    this.serverUrl,
    this.fontSize,
    this.borderColor,
    this.borderWidth = 0.0,
    this.boxShadow,
    this.onTap,
  });

  static int getHue(String text) {
    var hue = 0;
    for (var i = 0; i < text.length; i++) {
      hue = (hue + text.codeUnitAt(i) * 37) % 360;
    }
    return hue;
  }

  static Color getAvatarBgColor(String username) {
    final hue = getHue(username).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.65, 0.45).toColor();
  }

  String get _initials {
    final clean = username.trim();
    if (clean.isEmpty) return 'OS';
    if (clean.length >= 2) return clean.substring(0, 2).toUpperCase();
    return clean.toUpperCase();
  }

  Color get _avatarBgColor => getAvatarBgColor(username);

  Uint8List? _parseBase64Bytes(String data) {
    try {
      String clean = data.trim();
      if (clean.contains(',')) {
        clean = clean.split(',').last;
      }
      return base64Decode(clean);
    } catch (_) {
      return null;
    }
  }

  String? _resolveUrl(String pic) {
    final clean = pic.trim();
    if (clean.startsWith('http://') || clean.startsWith('https://')) {
      return clean;
    }
    if (serverUrl != null && serverUrl!.isNotEmpty) {
      final base = serverUrl!.replaceAll(RegExp(r'/+$'), '');
      final path = clean.startsWith('/') ? clean : '/$clean';
      return '$base$path';
    }
    return null;
  }

  Widget _buildInitialsFallback() {
    final fSize = fontSize ?? (size * 0.38).clamp(10.0, 32.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _avatarBgColor,
      ),
      child: Center(
        child: Text(
          _initials,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: fSize,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget content;

    final pic = profilePicture?.trim();
    if (pic == null || pic.isEmpty) {
      content = _buildInitialsFallback();
    } else if (pic.startsWith('data:image/') ||
        pic.contains(';base64,') ||
        (!pic.startsWith('http') && !pic.startsWith('/') && pic.length > 100)) {
      final bytes = _parseBase64Bytes(pic);
      if (bytes != null && bytes.isNotEmpty) {
        content = Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildInitialsFallback(),
        );
      } else {
        content = _buildInitialsFallback();
      }
    } else {
      final resolvedUrl = _resolveUrl(pic);
      if (resolvedUrl != null) {
        content = Image.network(
          resolvedUrl,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => _buildInitialsFallback(),
        );
      } else {
        content = _buildInitialsFallback();
      }
    }

    Widget avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: _avatarBgColor,
        border: borderColor != null && borderWidth > 0
            ? Border.all(color: borderColor!, width: borderWidth)
            : null,
        boxShadow: boxShadow,
      ),
      child: ClipOval(child: content),
    );

    if (onTap != null) {
      avatar = GestureDetector(
        onTap: onTap,
        child: avatar,
      );
    }

    return avatar;
  }
}
