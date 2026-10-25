import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../models/match_pick_models.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import 'obsidian_feedback.dart';
import 'obsidian_glass_card.dart';

const Color _redAlliance = Color(0xFFEF5350);
const Color _blueAlliance = Color(0xFF42A5F5);

/// Team numbers from team keys ("frc254" -> "254").
List<String> _teamNumbers(List<String> keys) => keys
    .map((k) => k.replaceFirst(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim())
    .where((k) => k.isNotEmpty)
    .toList();

/// Saves a tapped pick and returns the status to show. Tapping the current pick again clears it.
/// Mirrors handlePick in the website's js/services/match-prediction-picker.js.
Future<MatchPickStatus> saveMatchPickWithFeedback(
  BuildContext context,
  ApiService api,
  String eventKey,
  MatchPickStatus before,
  String winner,
) async {
  HapticFeedback.selectionClick();
  final result = await api.saveMatchPick(eventKey, before.matchKey, winner);
  if (!context.mounted) return before;
  switch (result) {
    case MatchPickSaveResult.saved:
      return before.withPick(winner);
    case MatchPickSaveResult.queued:
      return before.withPick(winner, pendingSync: true);
    case MatchPickSaveResult.locked:
      ObsidianFeedback.showWarning(
        context,
        message: context.tr('predictions.locked_toast', 'This match already has a result, so picks are locked.'),
      );
      return before.asLocked();
    case MatchPickSaveResult.failed:
      ObsidianFeedback.showError(context, message: context.tr('predictions.save_failed', "Couldn't save your pick"));
      return before;
  }
}

/// Red and blue buttons for one match plus a one-line status, shared by the scouting forms and the
/// Match Predictions screen.
class MatchPickButtons extends StatelessWidget {
  final MatchModel match;
  final MatchPickStatus status;
  final bool busy;
  final ValueChanged<String> onPick;
  final bool compact;

  const MatchPickButtons({
    super.key,
    required this.match,
    required this.status,
    required this.onPick,
    this.busy = false,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: _button(context, 'red')),
        const SizedBox(width: 10),
        Expanded(child: _button(context, 'blue')),
      ],
    );
  }

  Widget _button(BuildContext context, String side) {
    final color = side == 'red' ? _redAlliance : _blueAlliance;
    final selected = status.predictedWinner == side;
    final winner = status.result == side;
    final enabled = !status.locked && !busy;
    final teams = _teamNumbers(side == 'red' ? match.redTeams : match.blueTeams);
    final radius = ObsidianUITheme.getButtonRadius(context, fallback: 12.0).clamp(4.0, 16.0);
    final fg = selected ? Colors.white : color;
    return Opacity(
      opacity: enabled || selected ? 1.0 : 0.55,
      child: Material(
        color: selected ? color : color.withValues(alpha: 0.10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radius),
          side: BorderSide(color: selected || winner ? color : Colors.transparent, width: 2),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: enabled ? () => onPick(selected ? '' : side) : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 6 : 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      side == 'red' ? context.tr('predictions.red', 'Red') : context.tr('predictions.blue', 'Blue'),
                      style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                    if (winner) ...[
                      const SizedBox(width: 6),
                      Icon(Icons.emoji_events_rounded, size: 14, color: fg),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  teams.isEmpty ? context.tr('predictions.teams_tbd', 'Teams TBD') : teams.join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: fg.withValues(alpha: 0.85), fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One line describing a pick and, once it's in, the result.
class MatchPickStatusLine extends StatelessWidget {
  final MatchPickStatus status;

  const MatchPickStatusLine({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    IconData? icon;
    Color color = muted;
    String text;
    final pick = status.predictedWinner;
    final result = status.result;
    String alliance(String side) => side == 'red' ? context.tr('predictions.red', 'Red') : context.tr('predictions.blue', 'Blue');
    if (result != null) {
      if (result == 'tie') {
        icon = Icons.lock_rounded;
        text = context.tr('predictions.result_tie', "Tie - doesn't count");
      } else {
        final won = context.tr('predictions.result_won', '{alliance} won').replaceAll('{alliance}', alliance(result));
        if (pick == null) {
          icon = Icons.lock_rounded;
          text = '$won - ${context.tr('predictions.no_pick', 'no pick')}';
        } else if (pick == result) {
          icon = Icons.check_circle_rounded;
          color = const Color(0xFF10B981);
          text = '$won - ${context.tr('predictions.called_it', 'you called it')}';
        } else {
          icon = Icons.cancel_rounded;
          color = const Color(0xFFEF4444);
          text = '$won - ${context.tr('predictions.missed', 'not this time')}';
        }
      }
    } else if (status.locked) {
      icon = Icons.lock_rounded;
      text = context.tr('predictions.locked', 'Locked');
    } else if (pick == null) {
      text = context.tr('predictions.pick_hint', 'Pick before the result comes in');
    } else if (status.pendingSync) {
      icon = Icons.schedule_rounded;
      text = context.tr('predictions.saved_offline', 'Saved on this device - will sync');
    } else {
      icon = Icons.check_circle_outline_rounded;
      text = context.tr('predictions.saved', 'Saved');
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null) ...[Icon(icon, size: 14, color: color), const SizedBox(width: 4)],
        Flexible(
          child: Text(text, style: TextStyle(fontSize: 12, color: color), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

/// "Who wins this match?" card on the match and qualitative scouting forms. Renders nothing while the
/// team has match predictions turned off. Give it a key per match so it reloads when the match changes.
class MatchPredictionCard extends StatefulWidget {
  final ApiService apiService;
  final String eventKey;
  final MatchModel match;
  final EdgeInsetsGeometry? margin;

  const MatchPredictionCard({
    super.key,
    required this.apiService,
    required this.eventKey,
    required this.match,
    this.margin,
  });

  @override
  State<MatchPredictionCard> createState() => _MatchPredictionCardState();
}

class _MatchPredictionCardState extends State<MatchPredictionCard> {
  late MatchPickStatus _status = MatchPickStatus(matchKey: widget.match.matchKey);
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final picks = await widget.apiService.fetchMatchPicks(widget.eventKey);
    if (!mounted || picks == null) return;
    final found = picks[widget.match.matchKey];
    if (found != null) setState(() => _status = found);
  }

  Future<void> _pick(String winner) async {
    final before = _status;
    setState(() {
      _busy = true;
      _status = before.withPick(winner);
    });
    final next = await saveMatchPickWithFeedback(context, widget.apiService, widget.eventKey, before, winner);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = next;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.apiService.matchPredictionsEnabled) return const SizedBox.shrink();
    return ObsidianGlassCard(
      margin: widget.margin ?? const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                context.tr('predictions.form_title', 'Who wins this match?'),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: ObsidianUITheme.getPrimaryTextColor(context),
                ),
              ),
              MatchPickStatusLine(status: _status),
            ],
          ),
          const SizedBox(height: 10),
          MatchPickButtons(match: widget.match, status: _status, busy: _busy, onPick: _pick),
        ],
      ),
    );
  }
}
