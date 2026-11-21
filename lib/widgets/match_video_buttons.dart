import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';

/// "Watch match" buttons for TBA match videos. Opens the YouTube app when it is
/// installed (or the browser), which plays better on tablets than an embedded
/// player. Renders nothing when there are no videos.
class MatchVideoButtons extends StatelessWidget {
  final List<String> videoUrls;
  final bool compact;

  const MatchVideoButtons({super.key, required this.videoUrls, this.compact = false});

  Future<void> _open(BuildContext context, String url) async {
    HapticFeedback.selectionClick();
    final uri = Uri.parse(url);
    var ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) ok = await launchUrl(uri, mode: LaunchMode.platformDefault);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open the match video.")));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (videoUrls.isEmpty) return const SizedBox.shrink();
    final accent = ObsidianUITheme.primaryAccent;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < videoUrls.length; i++)
          compact
              ? ActionChip(
                  avatar: Icon(Icons.play_circle_outline_rounded, size: 16, color: accent),
                  label: Text(videoUrls.length > 1 ? 'Video ${i + 1}' : 'Video'),
                  visualDensity: VisualDensity.compact,
                  onPressed: () => _open(context, videoUrls[i]),
                )
              : OutlinedButton.icon(
                  icon: const Icon(Icons.play_circle_outline_rounded, size: 18),
                  label: Text(videoUrls.length > 1 ? 'Watch video ${i + 1}' : 'Watch match'),
                  onPressed: () => _open(context, videoUrls[i]),
                ),
      ],
    );
  }
}

/// Looks up the match's videos (one schedule request per event, cached for the
/// app session) and shows [MatchVideoButtons] once they're known.
class EntryMatchVideoButtons extends StatefulWidget {
  final ApiService apiService;
  final String? eventKey;
  final String? matchKey;

  const EntryMatchVideoButtons({super.key, required this.apiService, required this.eventKey, required this.matchKey});

  @override
  State<EntryMatchVideoButtons> createState() => _EntryMatchVideoButtonsState();
}

class _EntryMatchVideoButtonsState extends State<EntryMatchVideoButtons> {
  // eventKey -> (when fetched, match videos). Refetched after a few minutes so videos
  // TBA publishes during the event show up.
  static final Map<String, (DateTime, Future<Map<String, List<String>>>)> _cache = {};
  static const _ttl = Duration(minutes: 5);
  List<String> _urls = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EntryMatchVideoButtons oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.matchKey != widget.matchKey || oldWidget.eventKey != widget.eventKey) {
      _urls = const [];
      _load();
    }
  }

  Future<void> _load() async {
    final mk = (widget.matchKey ?? '').trim().toLowerCase();
    if (mk.isEmpty) return;
    var ev = (widget.eventKey ?? '').trim().toLowerCase();
    if (ev.isEmpty && mk.contains('_')) ev = mk.split('_').first;
    if (ev.isEmpty) return;
    final cached = _cache[ev];
    if (cached != null && DateTime.now().difference(cached.$1) > _ttl) _cache.remove(ev);
    final future = _cache.putIfAbsent(ev, () => (DateTime.now(), () async {
      try {
        final matches = await widget.apiService.fetchMatches(ev);
        return {
          for (final m in matches)
            if (m.videoUrls.isNotEmpty) m.matchKey.toLowerCase(): m.videoUrls,
        };
      } catch (_) {
        _cache.remove(ev);
        return <String, List<String>>{};
      }
    }())).$2;
    final map = await future;
    if (!mounted) return;
    final urls = map[mk] ?? const [];
    if (urls.isNotEmpty) setState(() => _urls = urls);
  }

  @override
  Widget build(BuildContext context) {
    if (_urls.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: MatchVideoButtons(videoUrls: _urls),
    );
  }
}
