import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// One step of a tutorial. [screenIndex] is the shell screen the step is about; when set,
/// the step gets a button that opens it. [pageId] gates the step on page access.
class _Step {
  final String text;
  final int? screenIndex;
  final String? pageId;
  final bool qrScanner;

  const _Step(this.text, {this.screenIndex, this.pageId, this.qrScanner = false});
}

class _Tutorial {
  final String id;
  final String title;
  final String summary;
  final IconData icon;
  final String category; // scouting, data, strategy, admin
  final List<_Step> steps;

  /// Page the whole tutorial needs (hidden when the user can't open it).
  final String? pageId;

  const _Tutorial({
    required this.id,
    required this.title,
    required this.summary,
    required this.icon,
    required this.category,
    required this.steps,
    this.pageId,
  });
}

// Screen indices come from ShellScreenRegistry.
const List<_Tutorial> _tutorials = [
  _Tutorial(
    id: 'app_dashboard',
    title: 'Find your way around',
    summary: 'The dashboard, the menu and your assignments.',
    icon: Icons.dashboard_rounded,
    category: 'scouting',
    steps: [
      _Step('The Dashboard is your home screen. Quick actions at the top start match scouting, pit scouting or the QR scanner.', screenIndex: 0),
      _Step('Open the menu to reach every page you have access to. Pages your admin turned off for your role are hidden.'),
      _Step('My Assignments lists the matches and pit visits you have been assigned, with the next one first.', screenIndex: 29, pageId: 'my-assignments'),
      _Step('Event Info shows announcements your admins posted for this event.', screenIndex: 51, pageId: 'event-info'),
    ],
  ),
  _Tutorial(
    id: 'app_match_scout',
    title: 'Scout a match',
    summary: 'Pick a team and match, record each phase, then submit.',
    icon: Icons.sports_esports_rounded,
    category: 'scouting',
    pageId: 'scout',
    steps: [
      _Step('Open Match Scout and choose the match, then the team you are watching.', screenIndex: 1, pageId: 'scout'),
      _Step('Fill in Auto, Teleop and Endgame as they happen. The points preview updates as you go.'),
      _Step('Timer fields: tap Start when the action begins and Stop when it ends. In a cycle timer, tap Lap at the end of every cycle; the average cycle time is saved.'),
      _Step('Submit at the end of the match. With no connection the entry is saved on this device and uploads by itself later.'),
      _Step('Scouting History shows everything you submitted and anything still waiting to upload.', screenIndex: 17, pageId: 'scout-history'),
    ],
  ),
  _Tutorial(
    id: 'app_pit_scout',
    title: 'Pit scout a robot',
    summary: 'Robot details and photos, one team at a time.',
    icon: Icons.build_circle_rounded,
    category: 'scouting',
    pageId: 'pit-scout',
    steps: [
      _Step('Open Pit Scout and pick a team at the current event.', screenIndex: 2, pageId: 'pit-scout'),
      _Step('Answer the questions your team set up, such as drivetrain and mechanisms, and add photos with the camera.'),
      _Step('Submit. Pit Data shows which teams still need a visit.', screenIndex: 14, pageId: 'pit-data'),
    ],
  ),
  _Tutorial(
    id: 'app_qual_scout',
    title: 'Qualitative scouting',
    summary: 'Rate driving, defense and strategy.',
    icon: Icons.star_rounded,
    category: 'scouting',
    pageId: 'qual-scout',
    steps: [
      _Step('Open Qual Scout, pick the match and the team or whole alliance you are rating.', screenIndex: 3, pageId: 'qual-scout'),
      _Step('Give ratings and notes for judgment-based traits.'),
    ],
  ),
  _Tutorial(
    id: 'app_offline_sync',
    title: 'Sync without internet',
    summary: 'QR codes and Bluetooth when the venue Wi-Fi is down.',
    icon: Icons.qr_code_2_rounded,
    category: 'scouting',
    steps: [
      _Step('Entries made offline wait on the device and upload when it reconnects. You do not need to do anything.'),
      _Step('To hand entries to a device that is online, open the entry in Scouting History and show its QR code, or send it over Bluetooth to another device running the app.', screenIndex: 17, pageId: 'scout-history'),
      _Step('On the receiving device, scan QR codes with the QR scanner. Scanned entries are queued and uploaded together.', qrScanner: true),
    ],
  ),
  _Tutorial(
    id: 'app_data',
    title: 'Look at the data',
    summary: 'Entries, graphs, comparisons and data checks.',
    icon: Icons.insights_rounded,
    category: 'data',
    steps: [
      _Step('All Data lists every match, pit and qualitative entry. Open one to see its answers and, when TBA has it, the match video.', screenIndex: 12, pageId: 'all-data'),
      _Step('Graphs charts any number from the scouting form, including timer fields, across teams or matches.', screenIndex: 4, pageId: 'graphs'),
      _Step('Compare Teams puts two or three teams side by side.', screenIndex: 38, pageId: 'compare'),
      _Step('Data Validation compares scouted totals with official scores and flags matches that look wrong or are missing scouting.', screenIndex: 16, pageId: 'data-validation'),
    ],
  ),
  _Tutorial(
    id: 'app_strategy',
    title: 'Plan matches and picks',
    summary: 'Match Planning, the pick list and alliance selection.',
    icon: Icons.emoji_events_rounded,
    category: 'strategy',
    steps: [
      _Step("Match Planning shows both alliances on the field. Draw paths for each phase and read each team's stats. Match Videos shows each team's most recent match video.", screenIndex: 31, pageId: 'match-planning'),
      _Step('Pick List: drag teams into your order and keep a Do Not Pick list.', screenIndex: 35, pageId: 'pick-list'),
      _Step('Alliance Selection is a live board for selection day. Recommendations follow your pick list.', screenIndex: 7, pageId: 'alliance-selection'),
    ],
  ),
  _Tutorial(
    id: 'app_admin_setup',
    title: 'Set up your team',
    summary: 'Events, forms, users and assignments (admins).',
    icon: Icons.admin_panel_settings_rounded,
    category: 'admin',
    pageId: 'admin-settings',
    steps: [
      _Step('Events: sync your event from The Blue Alliance or FIRST, or create a custom one.', screenIndex: 25, pageId: 'events'),
      _Step('Admin Settings: build the match, pit and qualitative forms. Add a Timer field for cycle or climb times.', screenIndex: 10, pageId: 'admin-settings'),
      _Step('Users: add scouts and choose their role.', screenIndex: 22, pageId: 'users'),
      _Step('Scout Assignments: plan who scouts which matches.', screenIndex: 30, pageId: 'scout-assignments'),
      _Step("Scout Report: each scout's activity and accuracy, which compares the alliances they scouted with official scores.", screenIndex: 40, pageId: 'scouter-report'),
    ],
  ),
];

/// Step-by-step guides for the app's own screens. Progress is kept on this device.
class TutorialsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;
  final void Function(int index) onNavigateScreen;
  final VoidCallback onOpenQrScanner;

  const TutorialsScreen({
    super.key,
    required this.apiService,
    required this.onNavigateScreen,
    required this.onOpenQrScanner,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<TutorialsScreen> createState() => _TutorialsScreenState();
}

class _TutorialsScreenState extends State<TutorialsScreen> {
  static const _prefsKey = 'app_tutorials_completed';
  Set<String> _done = {};
  String? _open;
  String _filter = 'all';

  @override
  void initState() {
    super.initState();
    _loadProgress();
  }

  Future<void> _loadProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() => _done = (prefs.getStringList(_prefsKey) ?? const []).toSet());
    } catch (_) {}
  }

  Future<void> _saveProgress() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_prefsKey, _done.toList());
    } catch (_) {}
  }

  bool _canOpen(String? pageId) => pageId == null || widget.apiService.hasPageAccess(pageId);

  List<_Tutorial> get _available => _tutorials.where((t) => _canOpen(t.pageId)).toList();

  void _toggleDone(_Tutorial t) {
    setState(() => _done.contains(t.id) ? _done.remove(t.id) : _done.add(t.id));
    _saveProgress();
  }

  void _resetAll() {
    setState(() => _done.clear());
    _saveProgress();
  }

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final available = _available;
    final completed = available.where((t) => _done.contains(t.id)).length;
    final shown = _filter == 'all' ? available : available.where((t) => t.category == _filter).toList();
    final next = available.where((t) => !_done.contains(t.id)).firstOrNull;

    return PortedPageList(
      onRefresh: _loadProgress,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: 'Tutorials',
          subtitle: 'Short guides to each part of the app. Tap a step to jump to that screen.',
          actions: [
            if (_done.isNotEmpty)
              TextButton.icon(onPressed: _resetAll, icon: const Icon(Icons.restart_alt_rounded, size: 18), label: const Text('Reset')),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$completed of ${available.length} done', style: TextStyle(fontWeight: FontWeight.w700, color: primary)),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: available.isEmpty ? 0 : completed / available.length,
                  minHeight: 6,
                  backgroundColor: ObsidianUITheme.getBorderColor(context),
                  color: ObsidianUITheme.primaryAccent,
                ),
              ),
              if (next != null) ...[
                const SizedBox(height: 10),
                FilledButton.icon(
                  onPressed: () => setState(() => _open = next.id),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Continue: ${next.title}'),
                ),
              ],
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
          child: Wrap(
            spacing: 6,
            children: [
              for (final (id, label) in const [('all', 'All'), ('scouting', 'Scouting'), ('data', 'Data'), ('strategy', 'Strategy'), ('admin', 'Admin')])
                if (id == 'all' || available.any((t) => t.category == id))
                  ChoiceChip(label: Text(label), selected: _filter == id, onSelected: (_) => setState(() => _filter = id)),
            ],
          ),
        ),
        for (final t in shown) _buildTutorial(context, t, primary, muted),
      ],
    );
  }

  Widget _buildTutorial(BuildContext context, _Tutorial t, Color primary, Color muted) {
    final isOpen = _open == t.id;
    final isDone = _done.contains(t.id);
    final steps = t.steps.where((s) => _canOpen(s.pageId)).toList();
    return ObsidianGlassCard(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      padding: const EdgeInsets.all(12),
      onTap: () => setState(() => _open = isOpen ? null : t.id),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isDone ? Icons.check_circle_rounded : t.icon, color: isDone ? ObsidianUITheme.successGreen : ObsidianUITheme.primaryAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.title, style: TextStyle(fontWeight: FontWeight.w700, color: primary)),
                    Text('${t.summary} · ${steps.length} steps', style: TextStyle(fontSize: 12, color: muted)),
                  ],
                ),
              ),
              Icon(isOpen ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: muted),
            ],
          ),
          if (isOpen) ...[
            const Divider(height: 20),
            for (var i = 0; i < steps.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      radius: 11,
                      backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                      child: Text('${i + 1}', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: ObsidianUITheme.primaryAccent)),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(steps[i].text, style: TextStyle(fontSize: 13.5, height: 1.4, color: primary)),
                          if (steps[i].screenIndex != null || steps[i].qrScanner)
                            TextButton.icon(
                              style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                              onPressed: () => steps[i].qrScanner
                                  ? widget.onOpenQrScanner()
                                  : widget.onNavigateScreen(steps[i].screenIndex!),
                              icon: const Icon(Icons.open_in_new_rounded, size: 16),
                              label: const Text('Go there'),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerRight,
              child: isDone
                  ? TextButton(onPressed: () => _toggleDone(t), child: const Text('Mark as not done'))
                  : FilledButton(
                      onPressed: () {
                        _toggleDone(t);
                        setState(() => _open = null);
                      },
                      child: const Text('Mark as done'),
                    ),
            ),
          ],
        ],
      ),
    );
  }
}
