import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';

/// High-performance JabCode encoder and decoder (ISO/IEC 23634 8-color matrix)
class JabCodeCodec {
  static const List<Color> jabColors = [
    Color(0xFF000000), // 0: Black   (000)
    Color(0xFF0000FF), // 1: Blue    (001)
    Color(0xFF00FF00), // 2: Green   (010)
    Color(0xFF00FFFF), // 3: Cyan    (011)
    Color(0xFFFF0000), // 4: Red     (100)
    Color(0xFFFF00FF), // 5: Magenta (101)
    Color(0xFFFFFF00), // 6: Yellow  (110)
    Color(0xFFFFFFFF), // 7: White   (111)
  ];

  /// Fast classification of RGB pixel into 3-bit color index (0..7)
  static int classifyRgb(int r, int g, int b) {
    int rBit = r > 128 ? 1 : 0;
    int gBit = g > 128 ? 1 : 0;
    int bBit = b > 128 ? 1 : 0;
    return (rBit << 2) | (gBit << 1) | bBit;
  }

  /// Calculates XOR checksum byte for data integrity
  static int _checksum(List<int> bytes) {
    int check = 0xAB;
    for (final b in bytes) {
      check ^= b;
    }
    return check & 0xFF;
  }

  /// Encodes data string into a 2D matrix of 3-bit color indices (0..7)
  static JabMatrix encode(String dataStr) {
    final bytes = utf8.encode(dataStr);
    final check = _checksum(bytes);
    final len = bytes.length;

    // Bitstream: 16-bit length + 8-bit checksum + payload bytes
    final bitWriter = _BitWriter();
    bitWriter.writeBits(len, 16);
    bitWriter.writeBits(check, 8);
    for (final b in bytes) {
      bitWriter.writeBits(b, 8);
    }

    // Determine grid size N
    int gridSize = 25;
    if (bytes.length > 120) gridSize = 29;
    if (bytes.length > 220) gridSize = 33;
    if (bytes.length > 350) gridSize = 37;

    final grid = List.generate(gridSize, (_) => List<int>.filled(gridSize, 0));
    int bitIndex = 0;
    final totalBits = bitWriter.lengthInBits;

    for (int r = 0; r < gridSize; r++) {
      for (int c = 0; c < gridSize; c++) {
        if (_isFinderPattern(r, c, gridSize)) {
          grid[r][c] = -1; // Reserved for finder pattern
        } else {
          if (bitIndex < totalBits) {
            grid[r][c] = bitWriter.readBitsAt(bitIndex, 3);
            bitIndex += 3;
          } else {
            // Padding modulo color
            grid[r][c] = (r + c) % 8;
          }
        }
      }
    }

    return JabMatrix(gridSize: gridSize, matrix: grid);
  }

  /// Decodes 2D matrix of 3-bit color indices back to String payload
  static String? decodeMatrix(List<List<int>> matrix, int gridSize) {
    try {
      final bitWriter = _BitWriter();

      for (int r = 0; r < gridSize; r++) {
        for (int c = 0; c < gridSize; c++) {
          if (!_isFinderPattern(r, c, gridSize)) {
            final val = matrix[r][c] & 0x07;
            bitWriter.writeBits(val, 3);
          }
        }
      }

      int bitIndex = 0;
      if (bitWriter.lengthInBits < 24) return null;

      final len = bitWriter.readBitsAt(bitIndex, 16);
      bitIndex += 16;
      final expectedCheck = bitWriter.readBitsAt(bitIndex, 8);
      bitIndex += 8;

      if (len <= 0 || bitWriter.lengthInBits < bitIndex + (len * 8)) {
        return null;
      }

      final payloadBytes = Uint8List(len);
      for (int i = 0; i < len; i++) {
        payloadBytes[i] = bitWriter.readBitsAt(bitIndex, 8);
        bitIndex += 8;
      }

      if (_checksum(payloadBytes) != expectedCheck) {
        return null;
      }

      return utf8.decode(payloadBytes);
    } catch (_) {
      return null;
    }
  }

  static bool _isFinderPattern(int r, int c, int size) {
    bool topStart = r < 5;
    bool bottomStart = r >= size - 5;
    bool leftStart = c < 5;
    bool rightStart = c >= size - 5;

    return (topStart && leftStart) ||
        (topStart && rightStart) ||
        (bottomStart && leftStart) ||
        (bottomStart && rightStart);
  }

  static Color getFinderColor(int r, int c, int size) {
    int rPos = r < 5 ? r : (r >= size - 5 ? r - (size - 5) : 0);
    int cPos = c < 5 ? c : (c >= size - 5 ? c - (size - 5) : 0);

    bool isInner = rPos >= 1 && rPos <= 3 && cPos >= 1 && cPos <= 3;
    bool isCenter = rPos == 2 && cPos == 2;

    if (r < 5 && c < 5) {
      return isCenter ? const Color(0xFFFFFF00) : (isInner ? const Color(0xFF000000) : const Color(0xFFFF0000));
    } else if (r < 5 && c >= size - 5) {
      return isCenter ? const Color(0xFF00FFFF) : (isInner ? const Color(0xFF000000) : const Color(0xFF00FF00));
    } else if (r >= size - 5 && c < 5) {
      return isCenter ? const Color(0xFFFF00FF) : (isInner ? const Color(0xFFFFFFFF) : const Color(0xFF0000FF));
    } else {
      return isCenter ? const Color(0xFF000000) : (isInner ? const Color(0xFFFFFF00) : const Color(0xFF00FFFF));
    }
  }
}

class JabMatrix {
  final int gridSize;
  final List<List<int>> matrix;

  JabMatrix({required this.gridSize, required this.matrix});
}

class _BitWriter {
  final List<int> _bits = [];

  void writeBits(int val, int count) {
    for (int i = count - 1; i >= 0; i--) {
      _bits.add((val >> i) & 1);
    }
  }

  int get lengthInBits => _bits.length;

  int readBitsAt(int startBit, int count) {
    int res = 0;
    for (int i = 0; i < count; i++) {
      if (startBit + i < _bits.length) {
        res = (res << 1) | _bits[startBit + i];
      }
    }
    return res;
  }
}
