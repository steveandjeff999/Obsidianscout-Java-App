import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../models/assignment_models.dart';
import '../services/assignment_advance_service.dart';
import '../theme/obsidian_ui_theme.dart';

/// Strip above a scouting form's selectors describing the current selection:
/// "Current assignment" when the form is on one of the scout's assignments, plus what's
/// "Up next" after it. When the selection isn't an assignment it offers to jump to the next one.
/// The selectors stay fully editable; Change clears them so the scout can pick manually.
class NextAssignmentChip extends StatelessWidget {
  /// False when the scout has no assignments of this type; the chip is hidden.
  final bool hasAssignments;

  /// The open assignment matching the form's current selection, if any.
  final ScoutingAssignment? current;

  /// The assignment after [current] (or after the selection when it isn't an assignment).
  final ScoutingAssignment? upNext;

  /// Unfinished assignments earlier in the event than [current] (shown when nothing comes after it).
  final int earlierOpen;

  /// Already-played assignments passed over by the last auto-advance.
  final int skippedPast;
  final bool autoAdvance;
  final VoidCallback? onChange;
  final ValueChanged<ScoutingAssignment>? onGoTo;
  final ValueChanged<bool> onToggleAutoAdvance;
  final EdgeInsetsGeometry margin;

  const NextAssignmentChip({
    super.key,
    required this.hasAssignments,
    required this.current,
    required this.upNext,
    required this.autoAdvance,
    required this.onToggleAutoAdvance,
    this.skippedPast = 0,
    this.earlierOpen = 0,
    this.onChange,
    this.onGoTo,
    this.margin = const EdgeInsets.fromLTRB(16, 4, 16, 4),
  });

  @override
  Widget build(BuildContext context) {
    if (!hasAssignments) return const SizedBox.shrink();

    final accent = ObsidianUITheme.primaryAccent;
    final textColor = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    const bold = TextStyle(fontWeight: FontWeight.w700);

    Widget line(FaIconData? icon, Color? iconColor, List<InlineSpan> spans, {Color? color}) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[FaIcon(icon, size: 13, color: iconColor), const SizedBox(width: 8)],
            Flexible(
              child: Text.rich(TextSpan(children: spans), style: TextStyle(fontSize: 13, color: color ?? textColor)),
            ),
          ],
        );

    final lines = <Widget>[];
    Widget? action;
    if (current != null) {
      lines.add(line(FontAwesomeIcons.forwardStep, accent, [
        const TextSpan(text: 'Current assignment: '),
        TextSpan(text: AssignmentAdvanceService.describe(current!), style: bold),
        if (skippedPast > 0) TextSpan(text: '  (skipped $skippedPast already played)', style: TextStyle(color: muted)),
      ]));
      lines.add(Padding(
        padding: const EdgeInsets.only(left: 21, top: 2),
        child: line(null, null, upNext != null
            ? [const TextSpan(text: 'Up next: '), TextSpan(text: AssignmentAdvanceService.describe(upNext!), style: bold)]
            : [
                TextSpan(
                  text: earlierOpen > 0
                      ? 'Up next: nothing after this one. You still have $earlierOpen earlier ${earlierOpen == 1 ? 'assignment' : 'assignments'} open.'
                      : 'Up next: nothing after this one, this is your last assignment.',
                ),
              ], color: muted),
      ));
      if (onChange != null) {
        action = TextButton(
          onPressed: onChange,
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('Change'),
        );
      }
    } else if (upNext != null) {
      lines.add(line(FontAwesomeIcons.forwardStep, accent, [
        const TextSpan(text: 'Your next assignment: '),
        TextSpan(text: AssignmentAdvanceService.describe(upNext!), style: bold),
      ]));
      if (onGoTo != null) {
        action = TextButton(
          onPressed: () => onGoTo!(upNext!),
          style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
          child: const Text('Go to it'),
        );
      }
    } else {
      lines.add(line(FontAwesomeIcons.circleCheck, ObsidianUITheme.successGreen,
          [const TextSpan(text: 'No more assignments. Pick a team and match manually.')]));
    }

    return Container(
      margin: margin,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 4,
        children: [
          Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: lines),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (action != null) action,
              Text('Auto-advance', style: TextStyle(fontSize: 12, color: muted)),
              Switch(
                value: autoAdvance,
                onChanged: onToggleAutoAdvance,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
