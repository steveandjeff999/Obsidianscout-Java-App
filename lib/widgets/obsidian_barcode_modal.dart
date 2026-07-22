import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_glass_card.dart';

class BarcodeCompressor {
  /// Compresses a JSON data string into OSC: base64 deflate format matching web common.js
  static String compressData(String dataStr) {
    try {
      final bytes = utf8.encode(dataStr);
      final compressedBytes = zlib.encode(bytes);
      final base64Str = base64.encode(compressedBytes);
      return "OSC:$base64Str";
    } catch (e) {
      return dataStr;
    }
  }

  /// Splits compressed string into multi-part QR payload chunks if data exceeds chunkSize
  static List<String> compressAndChunkData(String dataStr, {int chunkSize = 180}) {
    final compressed = compressData(dataStr);
    if (compressed.length <= chunkSize) {
      return [compressed];
    }

    final String base64Payload = compressed.startsWith("OSC:") ? compressed.substring(4) : compressed;
    final List<String> chunks = [];
    final total = (base64Payload.length / chunkSize).ceil();

    for (int i = 0; i < total; i++) {
      final start = i * chunkSize;
      final end = (start + chunkSize < base64Payload.length) ? start + chunkSize : base64Payload.length;
      final partChunk = base64Payload.substring(start, end);
      chunks.add("OSC:PART:${i + 1}:$total:$partChunk");
    }
    return chunks;
  }

  /// Decompresses OSC: base64 deflate format back to JSON string
  static String decompressData(String compressedStr) {
    if (!compressedStr.startsWith("OSC:")) {
      return compressedStr;
    }
    try {
      final base64Str = compressedStr.substring(4);
      final compressedBytes = base64.decode(base64Str);
      final decompressedBytes = zlib.decode(compressedBytes);
      return utf8.decode(decompressedBytes);
    } catch (e) {
      return compressedStr;
    }
  }
}

class ObsidianBarcodeModal extends StatefulWidget {
  final Map<String, dynamic> payload;
  final String typeLabel;
  final int targetTeamNumber;
  final String? matchKey;

  const ObsidianBarcodeModal({
    super.key,
    required this.payload,
    required this.typeLabel,
    required this.targetTeamNumber,
    this.matchKey,
  });

  static void show(
    BuildContext context, {
    required Map<String, dynamic> payload,
    required String typeLabel,
    required int targetTeamNumber,
    String? matchKey,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ObsidianBarcodeModal(
        payload: payload,
        typeLabel: typeLabel,
        targetTeamNumber: targetTeamNumber,
        matchKey: matchKey,
      ),
    );
  }

  @override
  State<ObsidianBarcodeModal> createState() => _ObsidianBarcodeModalState();
}

class _ObsidianBarcodeModalState extends State<ObsidianBarcodeModal> {
  late List<String> _qrChunks;
  late String _qrPayloadJson;

  @override
  void initState() {
    super.initState();
    final qrPayload = {
      'type': widget.payload['type'] ?? widget.typeLabel.toLowerCase().replaceAll(' ', '-'),
      'data': widget.payload,
    };
    _qrPayloadJson = jsonEncode(qrPayload);
    _qrChunks = BarcodeCompressor.compressAndChunkData(_qrPayloadJson);
  }

  void _showFullScreenBarcode(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (ctx) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: GestureDetector(
            onTap: () => Navigator.of(ctx).pop(),
            behavior: HitTestBehavior.opaque,
            child: Stack(
              children: [
                Center(
                  child: SingleChildScrollView(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 20.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (_qrChunks.length > 1) ...[
                            Text(
                              'GRID OF ${_qrChunks.length} QR CODES',
                              style: const TextStyle(
                                color: ObsidianUITheme.primaryAccent,
                                fontSize: 14.0,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.2,
                              ),
                            ),
                            const SizedBox(height: 16.0),
                          ],
                          Wrap(
                            spacing: 16.0,
                            runSpacing: 16.0,
                            alignment: WrapAlignment.center,
                            children: List.generate(_qrChunks.length, (idx) {
                              return Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (_qrChunks.length > 1)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 10.0, vertical: 4.0),
                                      margin: const EdgeInsets.only(bottom: 8.0),
                                      decoration: BoxDecoration(
                                        color: ObsidianUITheme.primaryAccent,
                                        borderRadius: BorderRadius.circular(8.0),
                                      ),
                                      child: Text(
                                        'PART ${idx + 1} OF ${_qrChunks.length}',
                                        style: const TextStyle(color: Colors.white, fontSize: 11.0, fontWeight: FontWeight.bold),
                                      ),
                                    ),
                                  Container(
                                    width: _qrChunks.length > 1 ? 220.0 : 320.0,
                                    height: _qrChunks.length > 1 ? 220.0 : 320.0,
                                    padding: const EdgeInsets.all(16.0),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(20.0),
                                      boxShadow: [
                                        BoxShadow(
                                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.4),
                                          blurRadius: 20.0,
                                          spreadRadius: 2.0,
                                        ),
                                      ],
                                    ),
                                    child: QrImageView(
                                      data: _qrChunks[idx],
                                      version: QrVersions.auto,
                                      size: _qrChunks.length > 1 ? 188.0 : 288.0,
                                      backgroundColor: Colors.white,
                                      errorCorrectionLevel: QrErrorCorrectLevel.M,
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                          const SizedBox(height: 24.0),
                          Text(
                            '${widget.typeLabel} • Team ${widget.targetTeamNumber}${widget.matchKey != null && widget.matchKey!.isNotEmpty ? " • ${widget.matchKey}" : ""}',
                            style: const TextStyle(color: Colors.white, fontSize: 16.0, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8.0),
                          const Text(
                            'Tap anywhere to exit full screen',
                            style: TextStyle(color: Colors.white54, fontSize: 13.0),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 48.0,
                  right: 20.0,
                  child: IconButton(
                    icon: const Icon(Icons.close_rounded, color: Colors.white, size: 32.0),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 20.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24.0,
      ),
      decoration: const BoxDecoration(
        color: ObsidianUITheme.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40.0,
            height: 4.0,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
          const SizedBox(height: 16.0),

          // Title & Close Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Scouting Entry QR Code',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18.0,
                      color: Colors.white,
                    ),
                  ),
                  if (_qrChunks.length > 1)
                    Text(
                      'Multi-QR Grid (${_qrChunks.length} Parts)',
                      style: const TextStyle(fontSize: 12.0, color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16.0),

          // QR Grid Container (Tappable to make Full Screen)
          GestureDetector(
            onTap: () => _showFullScreenBarcode(context),
            child: Wrap(
              spacing: 12.0,
              runSpacing: 12.0,
              alignment: WrapAlignment.center,
              children: List.generate(_qrChunks.length, (idx) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_qrChunks.length > 1)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4.0),
                        child: Text(
                          'Part ${idx + 1} of ${_qrChunks.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11.0, fontWeight: FontWeight.bold),
                        ),
                      ),
                    Container(
                      width: _qrChunks.length > 1 ? 135.0 : 260.0,
                      height: _qrChunks.length > 1 ? 135.0 : 260.0,
                      padding: const EdgeInsets.all(10.0),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16.0),
                        boxShadow: [
                          BoxShadow(
                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.3),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: QrImageView(
                        data: _qrChunks[idx],
                        version: QrVersions.auto,
                        size: _qrChunks.length > 1 ? 115.0 : 240.0,
                        backgroundColor: Colors.white,
                        errorCorrectionLevel: QrErrorCorrectLevel.M,
                      ),
                    ),
                  ],
                );
              }),
            ),
          ),
          const SizedBox(height: 8.0),
          const Text(
            'Tap QR code grid for full screen',
            style: TextStyle(fontSize: 12.0, color: Colors.white54),
          ),
          const SizedBox(height: 16.0),

          // Details summary
          ObsidianGlassCard(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _detailCol('TYPE', widget.typeLabel),
                _detailCol('TEAM', '${widget.targetTeamNumber}'),
                if (widget.matchKey != null && widget.matchKey!.isNotEmpty)
                  _detailCol('MATCH', widget.matchKey!),
              ],
            ),
          ),
          const SizedBox(height: 12.0),
        ],
      ),
    );
  }

  Widget _detailCol(String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0),
        ),
        const SizedBox(height: 4.0),
        Text(
          value,
          style: const TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: Colors.white),
        ),
      ],
    );
  }
}
