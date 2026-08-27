import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/csv_export_service.dart';
import '../services/file_download_helper.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_feedback.dart';

class CsvExportModal extends StatefulWidget {
  final String title;
  final CsvExportData exportData;

  const CsvExportModal({
    super.key,
    required this.title,
    required this.exportData,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required CsvExportData exportData,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CsvExportModal(
        title: title,
        exportData: exportData,
      ),
    );
  }

  @override
  State<CsvExportModal> createState() => _CsvExportModalState();
}

class _CsvExportModalState extends State<CsvExportModal> {
  bool _isDownloading = false;
  bool _isCopied = false;
  bool _showRawText = false;

  Future<void> _handleDownload() async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final result = await downloadOrSaveFile(
        filename: widget.exportData.suggestedFilename,
        content: widget.exportData.csvContent,
      );

      if (!mounted) return;

      if (result.success) {
        final message = result.isWebDownload
            ? 'Downloaded ${widget.exportData.suggestedFilename} to your browser downloads.'
            : (result.savedPath != null
                ? 'Saved to ${result.savedPath}'
                : 'CSV file saved successfully.');

        ObsidianFeedback.showSuccess(
          context,
          title: 'CSV File Exported',
          message: message,
        );
        Navigator.of(context).pop();
      } else {
        // Fallback: Copy to clipboard if disk write fails
        await Clipboard.setData(ClipboardData(text: widget.exportData.csvContent));
        if (!mounted) return;

        ObsidianFeedback.showWarning(
          context,
          title: 'Direct File Save Unavailable',
          message: '${result.message ?? "Could not save to disk."} CSV copied to clipboard instead.',
        );
      }
    } catch (e) {
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: widget.exportData.csvContent));
      if (!mounted) return;
      ObsidianFeedback.showWarning(
        context,
        title: 'Export Fallback',
        message: 'Could not write file ($e). CSV copied to clipboard.',
      );
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Timer? _copiedTimer;

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopyClipboard() async {
    await Clipboard.setData(ClipboardData(text: widget.exportData.csvContent));
    if (!mounted) return;

    setState(() => _isCopied = true);

    ObsidianFeedback.showSuccess(
      context,
      title: 'Copied to Clipboard',
      message: 'Exported ${widget.exportData.rowCount} rows (${widget.exportData.columnCount} columns) to clipboard as CSV.',
    );

    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _isCopied = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final backgroundColor = isDark ? const Color(0xFF131722) : Colors.white;
    final cardColor = isDark ? const Color(0xFF1C2230) : const Color(0xFFF1F5F9);
    final borderColor = isDark ? Colors.white12 : Colors.black12;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24.0)),
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: secondaryTextColor.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 8.0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8.0),
                  decoration: BoxDecoration(
                    color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                  child: const Icon(
                    Icons.table_chart_rounded,
                    color: ObsidianUITheme.primaryAccent,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: primaryTextColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.exportData.suggestedFilename,
                        style: TextStyle(
                          fontSize: 12,
                          color: secondaryTextColor,
                          fontFamily: 'monospace',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  color: secondaryTextColor,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),

          const Divider(height: 1),

          // Content body
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats row
                  Row(
                    children: [
                      Expanded(
                        child: _buildStatTile(
                          icon: Icons.format_list_numbered_rounded,
                          label: 'Rows',
                          value: '${widget.exportData.rowCount}',
                          color: ObsidianUITheme.primaryAccent,
                          cardColor: cardColor,
                          primaryTextColor: primaryTextColor,
                          secondaryTextColor: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildStatTile(
                          icon: Icons.view_column_rounded,
                          label: 'Columns',
                          value: '${widget.exportData.columnCount}',
                          color: Colors.cyanAccent,
                          cardColor: cardColor,
                          primaryTextColor: primaryTextColor,
                          secondaryTextColor: secondaryTextColor,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _buildStatTile(
                          icon: Icons.data_usage_rounded,
                          label: 'Size',
                          value: widget.exportData.formattedSize,
                          color: Colors.amberAccent,
                          cardColor: cardColor,
                          primaryTextColor: primaryTextColor,
                          secondaryTextColor: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // Preview header & toggle
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.preview_rounded, size: 16, color: ObsidianUITheme.primaryAccent),
                          const SizedBox(width: 6),
                          Text(
                            'Data Structure Preview',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: primaryTextColor,
                            ),
                          ),
                        ],
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => setState(() => _showRawText = !_showRawText),
                        icon: Icon(
                          _showRawText ? Icons.table_rows_rounded : Icons.code_rounded,
                          size: 14,
                          color: ObsidianUITheme.primaryAccent,
                        ),
                        label: Text(
                          _showRawText ? 'Table View' : 'Raw CSV',
                          style: const TextStyle(
                            fontSize: 11,
                            color: ObsidianUITheme.primaryAccent,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Preview content container
                  Container(
                    width: double.infinity,
                    height: 180,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: borderColor),
                    ),
                    child: _showRawText
                        ? SingleChildScrollView(
                            child: SelectableText(
                              widget.exportData.csvContent,
                              style: TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 11,
                                color: primaryTextColor.withValues(alpha: 0.9),
                                height: 1.4,
                              ),
                            ),
                          )
                        : _buildTablePreview(primaryTextColor, secondaryTextColor),
                  ),

                  const SizedBox(height: 12),

                  // Columns list chip preview
                  Text(
                    'Included Columns (${widget.exportData.headers.length}):',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: widget.exportData.headers.take(12).map((h) {
                      return Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Text(
                          h,
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w500,
                            color: ObsidianUITheme.primaryAccent,
                          ),
                        ),
                      );
                    }).toList()
                      ..addAll(widget.exportData.headers.length > 12
                          ? [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '+${widget.exportData.headers.length - 12} more',
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    color: secondaryTextColor,
                                  ),
                                ),
                              )
                            ]
                          : []),
                  ),
                ],
              ),
            ),
          ),

          const Divider(height: 1),

          // Action buttons bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ObsidianUITheme.primaryAccent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 2,
                    ),
                    onPressed: _isDownloading ? null : _handleDownload,
                    icon: _isDownloading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.download_rounded, size: 20),
                    label: Text(
                      _isDownloading ? 'Saving...' : 'Download CSV File',
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 4,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryTextColor,
                      side: BorderSide(color: borderColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    onPressed: _handleCopyClipboard,
                    icon: Icon(
                      _isCopied ? Icons.check_rounded : Icons.copy_rounded,
                      size: 18,
                      color: _isCopied ? ObsidianUITheme.successGreen : secondaryTextColor,
                    ),
                    label: Text(
                      _isCopied ? 'Copied!' : 'Copy Text',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required Color cardColor,
    required Color primaryTextColor,
    required Color secondaryTextColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: secondaryTextColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.bold,
              color: primaryTextColor,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTablePreview(Color primaryTextColor, Color secondaryTextColor) {
    if (widget.exportData.headers.isEmpty) {
      return Center(
        child: Text('No data to preview', style: TextStyle(color: secondaryTextColor)),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SingleChildScrollView(
        scrollDirection: Axis.vertical,
        child: DataTable(
          headingRowHeight: 32,
          dataRowMinHeight: 28,
          dataRowMaxHeight: 32,
          horizontalMargin: 8,
          columnSpacing: 16,
          columns: widget.exportData.headers.map((h) {
            return DataColumn(
              label: Text(
                h,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: primaryTextColor,
                ),
              ),
            );
          }).toList(),
          rows: widget.exportData.sampleRows.map((row) {
            return DataRow(
              cells: row.map((cell) {
                return DataCell(
                  Text(
                    cell.length > 25 ? '${cell.substring(0, 25)}...' : cell,
                    style: TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: secondaryTextColor,
                    ),
                  ),
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }
}
