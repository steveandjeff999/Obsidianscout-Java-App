import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/api_response.dart';
import '../services/file_download_helper.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_feedback.dart';
import 'obsidian_glass_card.dart';

/// Shared building blocks for the screens ported from website pages (Analytics, Compare Teams, Banners,
/// Storage Manager, ...). Those screens read the server's JSON as-is, so this also has small readers for it.

/// [AppLocalizationsX.tr] with an English fallback and {placeholder} values together.
extension PortedTr on BuildContext {
  String trArgs(String key, String fallback, [Map<String, String> args = const {}]) {
    var text = tr(key, fallback);
    args.forEach((name, value) => text = text.replaceAll('{$name}', value));
    return text;
  }
}

// ------------------------------------------------------------------ JSON readers

Map<String, dynamic> jsonMap(dynamic v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

List<dynamic> jsonList(dynamic v) => v is List ? v : const [];

List<Map<String, dynamic>> jsonMaps(dynamic v) => jsonList(v).whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList();

String jsonStr(dynamic v, [String fallback = '']) => v == null ? fallback : v.toString();

int? jsonInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

double? jsonDouble(dynamic v) => v is num ? v.toDouble() : double.tryParse('${v ?? ''}');

bool jsonBool(dynamic v) => v == true || v == 'true' || v == 1;

/// Whole numbers without decimals, anything else with [digits] places (the website's number style).
String fmtNum(dynamic v, {int digits = 2}) {
  final d = jsonDouble(v);
  if (d == null) return '-';
  if (d == d.roundToDouble()) return d.toInt().toString();
  return d.toStringAsFixed(digits);
}

String fmtBytes(dynamic v) {
  final b = jsonDouble(v) ?? 0;
  if (b < 1024) return '${b.toInt()} B';
  const units = ['KB', 'MB', 'GB', 'TB'];
  var size = b / 1024;
  var i = 0;
  while (size >= 1024 && i < units.length - 1) {
    size /= 1024;
    i++;
  }
  return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
}

/// Local date and time for an ISO timestamp or epoch milliseconds, or '' when there isn't one.
String fmtDateTime(BuildContext context, dynamic v) {
  DateTime? d;
  if (v is num) {
    d = DateTime.fromMillisecondsSinceEpoch(v.toInt());
  } else if (v is String && v.isNotEmpty) {
    d = DateTime.tryParse(v);
  }
  if (d == null) return v?.toString() ?? '';
  final local = d.toLocal();
  final loc = MaterialLocalizations.of(context);
  return '${loc.formatMediumDate(local)} ${loc.formatTimeOfDay(TimeOfDay.fromDateTime(local))}';
}

// ------------------------------------------------------------------ layout

/// Pull-to-refresh list with the bottom padding the shell's floating bars need.
class PortedPageList extends StatelessWidget {
  final List<Widget> children;
  final Future<void> Function() onRefresh;
  final bool isBarsVisible;

  const PortedPageList({super.key, required this.children, required this.onRefresh, this.isBarsVisible = true});

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: ObsidianUITheme.primaryAccent,
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.only(top: 4, bottom: isBarsVisible ? 120 : 20),
        children: children,
      ),
    );
  }
}

/// A card with a heading, an optional line under it, and optional buttons on the right.
class PortedSection extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData? icon;
  final List<Widget> actions;
  final Widget? child;
  final EdgeInsetsGeometry padding;

  const PortedSection({
    super.key,
    required this.title,
    this.subtitle,
    this.icon,
    this.actions = const [],
    this.child,
    this.padding = const EdgeInsets.all(16),
  });

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return ObsidianGlassCard(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 20, color: ObsidianUITheme.primaryAccent),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primary)),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(subtitle!, style: TextStyle(fontSize: 12.5, color: muted, height: 1.35)),
                    ],
                  ],
                ),
              ),
            ],
          ),
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
          if (child != null) ...[
            const SizedBox(height: 12),
            child!,
          ],
        ],
      ),
    );
  }
}

class PortedStat {
  final String label;
  final String value;
  final String? sub;
  const PortedStat(this.label, this.value, [this.sub]);
}

/// The website's KPI tiles, wrapped so they fit any width.
class PortedStatGrid extends StatelessWidget {
  final List<PortedStat> stats;
  const PortedStatGrid({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    return LayoutBuilder(builder: (context, c) {
      final perRow = c.maxWidth >= 720 ? 4 : (c.maxWidth >= 420 ? 3 : 2);
      final w = (c.maxWidth - (perRow - 1) * 10) / perRow;
      return Wrap(
        spacing: 10,
        runSpacing: 12,
        children: [
          for (final s in stats)
            SizedBox(
              width: w,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s.label.toUpperCase(),
                      style: TextStyle(fontSize: 10.5, letterSpacing: 0.6, fontWeight: FontWeight.w600, color: muted)),
                  const SizedBox(height: 2),
                  Text(s.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: primary)),
                  if (s.sub != null && s.sub!.isNotEmpty) Text(s.sub!, maxLines: 2, style: TextStyle(fontSize: 11, color: muted)),
                ],
              ),
            ),
        ],
      );
    });
  }
}

/// Label on the left, value on the right; used for detail rows inside cards.
class PortedKeyValue extends StatelessWidget {
  final String label;
  final String value;
  const PortedKeyValue(this.label, this.value, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(label, style: TextStyle(fontSize: 13, color: ObsidianUITheme.getSecondaryTextColor(context)))),
          const SizedBox(width: 12),
          Flexible(
            child: Text(value,
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ObsidianUITheme.getPrimaryTextColor(context))),
          ),
        ],
      ),
    );
  }
}

class PortedNotice extends StatelessWidget {
  final String text;
  final IconData? icon;
  const PortedNotice(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return ObsidianGlassCard(
      child: Row(
        children: [
          if (icon != null) ...[Icon(icon, color: muted), const SizedBox(width: 10)],
          Expanded(child: Text(text, style: TextStyle(color: muted))),
        ],
      ),
    );
  }
}

class PortedLoading extends StatelessWidget {
  const PortedLoading({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent)),
      );
}

class PortedError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const PortedError({super.key, required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.error_outline_rounded, color: ObsidianUITheme.errorRed),
            const SizedBox(width: 8),
            Expanded(child: Text(message, style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)))),
          ]),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(context.tr('common.retry', 'Retry')),
          ),
        ],
      ),
    );
  }
}

/// Shown instead of a page the signed-in role can't use, like the website's "Admin only" card.
class PortedLocked extends StatelessWidget {
  final String title;
  final String message;
  const PortedLocked({super.key, required this.title, required this.message});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 16),
      children: [
        PortedSection(icon: Icons.lock_outline_rounded, title: title, subtitle: message),
      ],
    );
  }
}

/// Small rounded label, e.g. a status or a role.
class PortedBadge extends StatelessWidget {
  final String text;
  final Color? color;
  const PortedBadge(this.text, {super.key, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ?? ObsidianUITheme.primaryAccent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
    );
  }
}

/// Horizontal bars for a label/value series (the website's bar widgets).
class PortedBarSeries extends StatelessWidget {
  final List<MapEntry<String, double>> series;
  const PortedBarSeries({super.key, required this.series});

  @override
  Widget build(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    if (series.isEmpty) {
      return Text(context.tr('analytics.no_data_recorded', 'No data recorded yet'), style: TextStyle(fontSize: 13, color: muted));
    }
    final max = series.map((e) => e.value).fold<double>(1, (a, b) => b > a ? b : a);
    return Column(
      children: [
        for (final e in series)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${e.key} (${fmtNum(e.value)})', style: TextStyle(fontSize: 12.5, color: ObsidianUITheme.getPrimaryTextColor(context))),
                const SizedBox(height: 3),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (e.value / max).clamp(0, 1).toDouble(),
                    minHeight: 8,
                    backgroundColor: ObsidianUITheme.getBorderColor(context),
                    color: ObsidianUITheme.primaryAccent,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ dialogs and feedback

Future<bool> confirmPortedAction(
  BuildContext context, {
  required String title,
  required String message,
  String? confirmLabel,
  bool destructive = false,
}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
      title: Text(title, style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx))),
      content: Text(message, style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(ctx.tr('common.cancel', 'Cancel'))),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: ObsidianUITheme.errorRed) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel ?? ctx.tr('common.confirm', 'Confirm')),
        ),
      ],
    ),
  );
  return ok == true;
}

/// Asks for one line (or several, with [multiline]) of text; null when cancelled.
Future<String?> promptPortedText(
  BuildContext context, {
  required String title,
  String? label,
  String initial = '',
  bool multiline = false,
  TextInputType? keyboardType,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
      title: Text(title, style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx))),
      content: TextField(
        controller: controller,
        autofocus: true,
        keyboardType: keyboardType,
        minLines: multiline ? 3 : 1,
        maxLines: multiline ? 8 : 1,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: Text(ctx.tr('common.cancel', 'Cancel'))),
        FilledButton(onPressed: () => Navigator.pop(ctx, controller.text), child: Text(ctx.tr('common.save', 'Save'))),
      ],
    ),
  );
  controller.dispose();
  return result;
}

/// Feedback banner for a finished request; returns whether it succeeded.
bool reportResult(BuildContext context, ApiResponse res, {required String action, String? success}) {
  if (!context.mounted) return res.success;
  ObsidianFeedback.showApiResponse(context, res, actionName: action, successMessage: success);
  return res.success;
}

/// Saves downloaded bytes to the device (Downloads on desktop) and says where they went.
Future<void> saveDownloadedBytes(BuildContext context, ApiResponse<List<int>> res, String fallbackName, String mimeType) async {
  if (!res.success || res.data == null) {
    reportResult(context, res, action: context.tr('common.download', 'Download'));
    return;
  }
  final name = (res.message != null && res.message!.isNotEmpty) ? res.message! : fallbackName;
  final saved = await downloadOrSaveBytes(filename: name, bytes: res.data!, mimeType: mimeType);
  if (!context.mounted) return;
  if (saved.success) {
    ObsidianFeedback.showSuccess(context, message: saved.savedPath != null ? 'Saved to ${saved.savedPath}' : 'Download started');
  } else {
    ObsidianFeedback.showError(context, message: saved.message ?? 'Could not save $name');
  }
}
