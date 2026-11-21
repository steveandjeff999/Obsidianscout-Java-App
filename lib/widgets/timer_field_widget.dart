import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/config_models.dart';
import '../theme/obsidian_ui_theme.dart';

/// Formats seconds as "12.3s" or "1:05.0".
String formatTimerSeconds(num? seconds) {
  final s = (seconds ?? 0).toDouble().clamp(0, double.infinity);
  final m = s ~/ 60;
  final rest = s - m * 60;
  if (m > 0) return '$m:${rest.toStringAsFixed(1).padLeft(4, '0')}';
  return '${rest.toStringAsFixed(1)}s';
}

/// Timer form element, matching the site's `type: "timer"` field.
///
/// `mode: "stopwatch"` (default) stores total seconds; `mode: "cycle"` stores
/// the average seconds per lap. The value is a plain number (one decimal) so
/// payloads, drafts, QR codes and analytics treat it like any number field.
class TimerFieldWidget extends StatefulWidget {
  final ScoutingFieldModel field;
  final dynamic value;
  final ValueChanged<dynamic> onChanged;
  final bool isDesktop;

  const TimerFieldWidget({
    super.key,
    required this.field,
    required this.value,
    required this.onChanged,
    this.isDesktop = false,
  });

  @override
  State<TimerFieldWidget> createState() => _TimerFieldWidgetState();
}

class _TimerFieldWidgetState extends State<TimerFieldWidget> {
  final Stopwatch _run = Stopwatch();
  Duration _banked = Duration.zero;
  Duration _lapStart = Duration.zero;
  final List<Duration> _laps = [];
  Timer? _tick;
  DateTime _lastEmit = DateTime.fromMillisecondsSinceEpoch(0);

  /// The last value this widget reported, so outside changes can be told apart.
  dynamic _lastEmitted;
  bool _restored = false;

  bool get _isCycle => (widget.field.mode ?? '').toLowerCase() == 'cycle';
  bool get _running => _run.isRunning;
  Duration get _elapsed => _banked + _run.elapsed;

  @override
  void initState() {
    super.initState();
    _loadFrom(widget.value);
  }

  @override
  void didUpdateWidget(covariant TimerFieldWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameValue(widget.value, _lastEmitted)) {
      // Cleared after submit, draft restored, or a different entry loaded.
      _stopClock();
      _loadFrom(widget.value);
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  bool _sameValue(dynamic a, dynamic b) {
    final na = _asSeconds(a);
    final nb = _asSeconds(b);
    return na == nb;
  }

  double? _asSeconds(dynamic v) {
    if (v == null) return null;
    if (v is num) return v > 0 ? v.toDouble() : null;
    final parsed = double.tryParse(v.toString());
    return (parsed == null || parsed <= 0) ? null : parsed;
  }

  void _loadFrom(dynamic v) {
    final seconds = _asSeconds(v);
    _run
      ..stop()
      ..reset();
    _laps.clear();
    _lapStart = Duration.zero;
    _banked = Duration.zero;
    _restored = false;
    if (seconds != null) {
      final d = Duration(milliseconds: (seconds * 1000).round());
      if (_isCycle) {
        _laps.add(d);
        _restored = true;
      } else {
        _banked = d;
      }
    }
    _lastEmitted = v;
  }

  double? _storedValue() {
    if (_isCycle) {
      if (_laps.isEmpty) return null;
      final totalMs = _laps.fold<int>(0, (a, d) => a + d.inMilliseconds);
      return ((totalMs / _laps.length) / 100).round() / 10;
    }
    final ms = _elapsed.inMilliseconds;
    return ms > 0 ? (ms / 100).round() / 10 : null;
  }

  void _emit() {
    final v = _storedValue();
    _lastEmitted = v;
    _lastEmit = DateTime.now();
    widget.onChanged(v);
  }

  void _startClock() {
    _run.start();
    _tick ??= Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (!mounted) return;
      setState(() {});
      // Keep the saved value current while a stopwatch runs.
      if (!_isCycle && DateTime.now().difference(_lastEmit).inMilliseconds >= 1000) {
        _emit();
      }
    });
  }

  void _stopClock() {
    if (_run.isRunning) {
      _banked += _run.elapsed;
      _run
        ..stop()
        ..reset();
    }
    _tick?.cancel();
    _tick = null;
  }

  void _toggle() {
    HapticFeedback.lightImpact();
    setState(() {
      if (_running) {
        _stopClock();
        _emit();
      } else {
        _restored = false;
        _startClock();
      }
    });
  }

  void _lap() {
    if (!_running || !_isCycle) return;
    final at = _elapsed;
    final dur = at - _lapStart;
    if (dur.inMilliseconds < 200) return; // ignore accidental double taps
    HapticFeedback.selectionClick();
    setState(() {
      if (_restored) {
        _laps.clear();
        _restored = false;
      }
      _laps.add(dur);
      _lapStart = at;
    });
    _emit();
  }

  void _reset() {
    HapticFeedback.mediumImpact();
    setState(() {
      _stopClock();
      _banked = Duration.zero;
      _lapStart = Duration.zero;
      _laps.clear();
      _restored = false;
    });
    _emit();
  }

  @override
  Widget build(BuildContext context) {
    final isDesktop = widget.isDesktop;
    final primaryText = ObsidianUITheme.getPrimaryTextColor(context);
    final tertiaryText = ObsidianUITheme.getTertiaryTextColor(context);
    final border = ObsidianUITheme.getBorderColor(context);
    final accent = ObsidianUITheme.primaryAccent;

    String display;
    String sub = '';
    if (_isCycle) {
      if (_running) {
        display = formatTimerSeconds((_elapsed - _lapStart).inMilliseconds / 1000);
      } else {
        display = formatTimerSeconds(_storedValue() ?? 0);
      }
      if (_restored) {
        sub = 'Restored value';
      } else if (_laps.isNotEmpty) {
        sub = '${_laps.length} ${_laps.length == 1 ? 'cycle' : 'cycles'} · avg ${formatTimerSeconds(_storedValue())}';
      } else if (_running) {
        sub = 'Tap Lap at the end of each cycle';
      }
    } else {
      display = formatTimerSeconds(_elapsed.inMilliseconds / 1000);
    }

    final startLabel = _running ? 'Stop' : (_elapsed > Duration.zero ? 'Resume' : 'Start');

    Widget button({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool primary = false,
    }) {
      final enabled = onPressed != null;
      return Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Material(
          color: primary ? accent : ObsidianUITheme.getGlassSurfaceColor(context),
          borderRadius: BorderRadius.circular(isDesktop ? 6 : 8),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(isDesktop ? 6 : 8),
            child: Container(
              constraints: BoxConstraints(minHeight: isDesktop ? 34 : 48, minWidth: isDesktop ? 64 : 76),
              padding: EdgeInsets.symmetric(horizontal: isDesktop ? 10 : 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(isDesktop ? 6 : 8),
                border: Border.all(color: primary ? accent : border),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: isDesktop ? 18 : 20, color: primary ? Colors.white : primaryText),
                  const SizedBox(width: 4),
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: isDesktop ? 12.5 : 14,
                      color: primary ? Colors.white : primaryText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.field.label,
          style: TextStyle(fontSize: isDesktop ? 13.0 : 14.5, color: primaryText, fontWeight: FontWeight.w500),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 110),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    display,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: isDesktop ? 22 : 26,
                      fontWeight: FontWeight.w500,
                      color: _running ? accent : primaryText,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (sub.isNotEmpty)
                    Text(sub, style: TextStyle(fontSize: isDesktop ? 11 : 12.5, color: tertiaryText)),
                ],
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                button(
                  icon: _running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  label: startLabel,
                  onPressed: _toggle,
                  primary: true,
                ),
                if (_isCycle)
                  button(icon: Icons.flag_rounded, label: 'Lap', onPressed: _running ? _lap : null),
                button(icon: Icons.restart_alt_rounded, label: 'Reset', onPressed: _reset),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
