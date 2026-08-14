import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
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
  static List<String> compressAndChunkData(String dataStr, {int chunkSize = 450}) {
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
  int _maxChunkSize = 450;

  @override
  void initState() {
    super.initState();
    final qrPayload = {
      'type': widget.payload['type'] ?? widget.typeLabel.toLowerCase().replaceAll(' ', '-'),
      'data': widget.payload,
    };
    _qrPayloadJson = jsonEncode(qrPayload);
    _qrChunks = BarcodeCompressor.compressAndChunkData(_qrPayloadJson, chunkSize: _maxChunkSize);
    _loadSavedChunkSize();
  }

  Future<void> _loadSavedChunkSize() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedStr = prefs.getString('obsidianscout:qr_max_chunk_size');
      final savedInt = prefs.getInt('obsidianscout:qr_max_chunk_size');
      int parsedSize = 450;
      if (savedInt != null) {
        parsedSize = savedInt;
      } else if (savedStr != null) {
        parsedSize = int.tryParse(savedStr) ?? 450;
      }
      if (parsedSize < 50) parsedSize = 450;

      if (mounted && parsedSize != _maxChunkSize) {
        setState(() {
          _maxChunkSize = parsedSize;
          _qrChunks = BarcodeCompressor.compressAndChunkData(_qrPayloadJson, chunkSize: _maxChunkSize);
        });
      }
    } catch (_) {}
  }

  Future<void> _updateChunkSize(int newSize) async {
    setState(() {
      _maxChunkSize = newSize;
      _qrChunks = BarcodeCompressor.compressAndChunkData(_qrPayloadJson, chunkSize: _maxChunkSize);
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('obsidianscout:qr_max_chunk_size', newSize.toString());
      await prefs.setInt('obsidianscout:qr_max_chunk_size', newSize);
    } catch (_) {}
  }

  Widget _buildSizeDropdown(BuildContext context, {required ValueChanged<int> onChanged, bool isDark = false}) {
    final primaryTextColor = isDark ? Colors.white : ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = isDark ? Colors.white70 : ObsidianUITheme.getSecondaryTextColor(context);
    final surfaceColor = isDark ? const Color(0xFF1E1E2C) : ObsidianUITheme.getSurfaceColor(context);

    final Map<int, String> options = {
      150: context.tr('qr.size_150'),
      250: context.tr('qr.size_250'),
      350: context.tr('qr.size_350'),
      450: context.tr('qr.size_450'),
      600: context.tr('qr.size_600'),
      800: context.tr('qr.size_800'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 6.0),
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.1)
            : ObsidianUITheme.primaryAccent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16.0),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.2)
              : ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
        ),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8.0,
        runSpacing: 4.0,
        children: [
          Text(
            context.tr('qr.max_size_label'),
            style: TextStyle(
              fontSize: 13.0,
              fontWeight: FontWeight.bold,
              color: secondaryTextColor,
            ),
          ),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: options.containsKey(_maxChunkSize) ? _maxChunkSize : 450,
              dropdownColor: surfaceColor,
              isDense: true,
              icon: const Icon(
                Icons.arrow_drop_down_rounded,
                color: ObsidianUITheme.primaryAccent,
              ),
              style: TextStyle(
                color: primaryTextColor,
                fontSize: 13.0,
                fontWeight: FontWeight.w600,
              ),
              onChanged: (val) {
                if (val != null) {
                  onChanged(val);
                }
              },
              items: options.entries.map((entry) {
                return DropdownMenuItem<int>(
                  value: entry.key,
                  child: Text(
                    entry.value,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: primaryTextColor,
                      fontSize: 13.0,
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showFullScreenBarcode(BuildContext context) {
    showDialog(
      context: context,
      useSafeArea: false,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            return Scaffold(
              backgroundColor: Colors.black,
              body: GestureDetector(
                onTap: () => Navigator.of(ctx).pop(),
                behavior: HitTestBehavior.opaque,
                child: Stack(
                  children: [
                    Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48.0, horizontal: 20.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildSizeDropdown(
                                dialogCtx,
                                isDark: true,
                                onChanged: (val) {
                                  _updateChunkSize(val);
                                  setDialogState(() {});
                                },
                              ),
                              const SizedBox(height: 16.0),
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
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final tertiaryTextColor = ObsidianUITheme.getTertiaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);

    final double maxHeight = MediaQuery.of(context).size.height * 0.85;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      padding: EdgeInsets.only(
        left: 20.0,
        right: 20.0,
        top: 16.0,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20.0,
      ),
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28.0)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40.0,
            height: 4.0,
            decoration: BoxDecoration(
              color: faintTextColor,
              borderRadius: BorderRadius.circular(2.0),
            ),
          ),
          const SizedBox(height: 12.0),

          // Title & Close Button
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('qr.title'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18.0,
                        color: primaryTextColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (_qrChunks.length > 1)
                      Text(
                        'Multi-QR Grid (${_qrChunks.length} Parts)',
                        style: const TextStyle(fontSize: 12.0, color: ObsidianUITheme.primaryAccent, fontWeight: FontWeight.bold),
                      ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close_rounded, color: secondaryTextColor),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 12.0),

          // Scrollable Content Body
          Flexible(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Size selector dropdown
                  _buildSizeDropdown(
                    context,
                    onChanged: (val) => _updateChunkSize(val),
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
                                  style: TextStyle(color: secondaryTextColor, fontSize: 11.0, fontWeight: FontWeight.bold),
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
                  Text(
                    'Tap QR code grid for full screen',
                    style: TextStyle(fontSize: 12.0, color: tertiaryTextColor),
                  ),
                  const SizedBox(height: 16.0),

                  // Details summary
                  ObsidianGlassCard(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _detailCol(context, 'TYPE', widget.typeLabel),
                        _detailCol(context, 'TEAM', '${widget.targetTeamNumber}'),
                        if (widget.matchKey != null && widget.matchKey!.isNotEmpty)
                          _detailCol(context, 'MATCH', widget.matchKey!),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12.0),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailCol(BuildContext context, String label, String value) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 10.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, letterSpacing: 1.0),
        ),
        const SizedBox(height: 4.0),
        Text(
          value,
          style: TextStyle(fontSize: 14.0, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context)),
        ),
      ],
    );
  }
}
