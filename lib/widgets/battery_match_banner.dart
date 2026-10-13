import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../services/battery_rotation.dart';
import '../theme/obsidian_ui_theme.dart';

/// A translated battery string with `{placeholders}` filled in; English [fallback] when the key is missing.
String batteryText(BuildContext context, String key, String fallback, Map<String, String> args) {
  var text = context.tr(key, fallback);
  args.forEach((k, v) => text = text.replaceAll('{$k}', v));
  return text;
}

/// The battery a match needs, with Skip / Undo skips / Mark used. Shown on the Match Checklist and used for
/// each row of the Battery Tracker's rotation (same as the website's checklist banner).
class BatteryMatchBanner extends StatelessWidget {
  final BatterySlot slot;
  final String Function(String id) nameOf;
  final VoidCallback onSkip;
  final VoidCallback onUnskip;
  final VoidCallback onMarkUsed;
  final VoidCallback onUnmarkUsed;

  const BatteryMatchBanner({
    super.key,
    required this.slot,
    required this.nameOf,
    required this.onSkip,
    required this.onUnskip,
    required this.onMarkUsed,
    required this.onUnmarkUsed,
  });

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final id = slot.batteryId;
    final tag = switch (slot.source) {
      'used' => context.tr('battery.source.used', 'Used'),
      'pinned' => context.tr('battery.source.pinned', 'Pinned'),
      _ => '',
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: id == null ? ObsidianUITheme.errorRed : ObsidianUITheme.getBorderColor(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                id == null ? Icons.battery_alert_rounded : Icons.battery_charging_full_rounded,
                color: id == null ? ObsidianUITheme.errorRed : ObsidianUITheme.successGreen,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      id == null
                          ? context.tr('battery.checklist.none', 'No battery available: every battery is skipped for this match')
                          : batteryText(context, 'battery.checklist.needs', 'Battery: {name}', {'name': nameOf(id)}),
                      style: TextStyle(color: primary, fontWeight: FontWeight.bold),
                    ),
                    if (tag.isNotEmpty)
                      Text(tag.toUpperCase(), style: TextStyle(color: secondary, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 0.4)),
                    if (slot.skipped.isNotEmpty)
                      Text(
                        batteryText(context, 'battery.checklist.skipped', 'Skipped: {names}', {'names': slot.skipped.map(nameOf).join(', ')}),
                        style: TextStyle(color: secondary, fontSize: 12),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            alignment: WrapAlignment.end,
            children: [
              if (id != null && slot.source != 'used')
                OutlinedButton(onPressed: onSkip, child: Text(context.tr('battery.action.skip', 'Skip'))),
              if (slot.skipped.isNotEmpty)
                OutlinedButton(onPressed: onUnskip, child: Text(context.tr('battery.action.unskip', 'Undo skips'))),
              if (slot.source == 'used')
                OutlinedButton(onPressed: onUnmarkUsed, child: Text(context.tr('battery.action.unmark_used', 'Not used')))
              else if (id != null)
                FilledButton(onPressed: onMarkUsed, child: Text(context.tr('battery.action.mark_used', 'Mark used'))),
            ],
          ),
        ],
      ),
    );
  }
}
