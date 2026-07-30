import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../l10n/app_localizations.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';

class AllianceSelectionScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const AllianceSelectionScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<AllianceSelectionScreen> createState() => _AllianceSelectionScreenState();
}

class _AllianceSelectionScreenState extends State<AllianceSelectionScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();

  bool _isLoading = false;
  bool _isSaving = false;
  DateTime? _lastSyncedTime;
  Timer? _realtimeSyncTimer;
  StreamSubscription<bool>? _onlineSubscription;

  List<EventModel> _events = [];
  String? _selectedEventKey;
  List<TeamModel> _allTeams = [];
  String _selectedMetric = 'weighted'; // 'weighted', 'scouted', 'epa', 'opr'

  // Board state matching web backend structure: alliance1..alliance8
  // Each contains: 'captain', 'firstPick', 'secondPick', 'backup' (int? team numbers)
  final Map<String, Map<String, int?>> _boardState = {
    'alliance1': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
    'alliance2': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
    'alliance3': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
    'alliance4': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
    'alliance5': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
    'alliance6': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
    'alliance7': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
    'alliance8': {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null},
  };

  // Tracks local write timestamps for each slot: 'alliance1_captain' -> 1753456789000
  // Used for slot-level "Last Write Wins" conflict resolution against server timestamps
  final Map<String, int> _slotTimestamps = {};
  bool _hasPendingOfflineChanges = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    // Listen for online status changes to auto-catchup and upload offline changes
    _onlineSubscription = widget.apiService.onOnlineStatusChanged.listen((online) {
      if (online && mounted && _selectedEventKey != null) {
        _catchUpAndSyncWithServer(isReconnecting: true);
      }
    });

    _initializeData();
    _startRealtimeSyncTimer();
  }

  @override
  void didUpdateWidget(covariant AllianceSelectionScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _catchUpAndSyncWithServer();
    }
  }

  @override
  void dispose() {
    _onlineSubscription?.cancel();
    _realtimeSyncTimer?.cancel();
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _startRealtimeSyncTimer() {
    _realtimeSyncTimer?.cancel();
    // Poll server every 2 seconds for real-time synchronization with server & other scouts
    _realtimeSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted && widget.apiService.isOnline && !_isLoading && !_isSaving && _selectedEventKey != null) {
        _catchUpAndSyncWithServer();
      }
    });
  }

  Future<void> _initializeData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      // 1. Fetch configured current event key from server settings (like web client)
      final currentEventKey = await widget.apiService.fetchCurrentEventKey();

      // 2. Fetch all events for the year
      final events = await widget.apiService.fetchEvents();
      _events = events;

      // 3. Default dropdown value to current configured event key
      if (currentEventKey != null && currentEventKey.isNotEmpty) {
        _selectedEventKey = currentEventKey;
      } else if (_events.isNotEmpty) {
        _selectedEventKey = _events.first.eventKey;
      } else {
        _selectedEventKey = '2026txhou';
      }

      // Ensure _selectedEventKey is present in _events list, or create dummy EventModel
      if (!_events.any((e) => e.eventKey == _selectedEventKey)) {
        _events.insert(0, EventModel(eventKey: _selectedEventKey!, name: 'Configured Event (${_selectedEventKey!.toUpperCase()})'));
      }

      // 4. Load local offline cache metadata & slot timestamps
      await _loadLocalSlotMetadata(_selectedEventKey!);

      // 5. Fetch teams & selection board for selected event
      await _loadEventData(_selectedEventKey!);
    } catch (_) {}

    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _loadLocalSlotMetadata(String eventKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final metaStr = prefs.getString('cache_alliance_meta_$eventKey');
      if (metaStr != null && metaStr.isNotEmpty) {
        final Map<String, dynamic> meta = jsonDecode(metaStr);
        if (meta['slotTimestamps'] is Map) {
          final Map map = meta['slotTimestamps'];
          _slotTimestamps.clear();
          map.forEach((k, v) {
            if (v is num) _slotTimestamps[k.toString()] = v.toInt();
          });
        }
        _hasPendingOfflineChanges = meta['pendingSync'] == true;
      }
    } catch (_) {}
  }

  Future<void> _saveLocalSlotMetadata(String eventKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = {
        'slotTimestamps': _slotTimestamps,
        'pendingSync': _hasPendingOfflineChanges,
      };
      await prefs.setString('cache_alliance_meta_$eventKey', jsonEncode(payload));
    } catch (_) {}
  }

  Future<void> _loadEventData(String eventKey) async {
    try {
      final teams = await widget.apiService.fetchTeams(eventKey);
      _allTeams = teams;

      await _catchUpAndSyncWithServer();
    } catch (_) {}
  }

  /// Catch-Up and Synchronize with Server using "Last Write Wins" Conflict Resolution
  Future<void> _catchUpAndSyncWithServer({bool isReconnecting = false}) async {
    if (_selectedEventKey == null) return;
    final eventKey = _selectedEventKey!;

    final selectionData = await widget.apiService.getAllianceSelection(eventKey);
    if (!mounted || selectionData == null) return;

    final String serverRawJson = selectionData['selectionJson']?.toString() ?? '{}';
    final int serverUpdatedAtMs = (selectionData['updatedAt'] is num) ? (selectionData['updatedAt'] as num).toInt() : 0;
    final DateTime serverTime = DateTime.fromMillisecondsSinceEpoch(serverUpdatedAtMs);

    final Map<String, Map<String, int?>> serverBoard = _parseRawBoardJson(serverRawJson);

    bool mergedDifferentFromServer = false;

    // Slot-by-Slot Conflict Resolution: LAST WRITE WINS
    // For each slot, compare the local slot modification timestamp with the server's update timestamp
    final Map<String, Map<String, int?>> resolvedBoard = {};

    for (int i = 1; i <= 8; i++) {
      final allianceKey = 'alliance$i';
      resolvedBoard[allianceKey] = {};

      final localAlliance = _boardState[allianceKey] ?? {};
      final serverAlliance = serverBoard[allianceKey] ?? {};

      for (final slotName in ['captain', 'firstPick', 'secondPick', 'backup']) {
        final slotKey = '${allianceKey}_$slotName';
        final int localWriteTime = _slotTimestamps[slotKey] ?? 0;

        final int? localVal = localAlliance[slotName];
        final int? serverVal = serverAlliance[slotName];

        if (localWriteTime > serverUpdatedAtMs) {
          // Local write occurred AFTER the server's last update -> LAST WRITE WINS (Keep Local)
          resolvedBoard[allianceKey]![slotName] = localVal;
          if (localVal != serverVal) {
            mergedDifferentFromServer = true;
          }
        } else {
          // Server write is NEWER or equal -> Accept Server value
          resolvedBoard[allianceKey]![slotName] = serverVal;
        }
      }
    }

    // Update in-memory state
    setState(() {
      _boardState.clear();
      _boardState.addAll(resolvedBoard);
      if (serverUpdatedAtMs > 0 && (_lastSyncedTime == null || serverTime.isAfter(_lastSyncedTime!))) {
        _lastSyncedTime = serverTime;
      }
    });

    // If local offline changes win and need to be uploaded to server
    if (_hasPendingOfflineChanges || mergedDifferentFromServer || serverUpdatedAtMs == 0) {
      if (widget.apiService.isOnline) {
        setState(() {
          _isSaving = true;
        });

        final jsonStr = jsonEncode(_boardState);
        final success = await widget.apiService.saveAllianceSelection(eventKey, jsonStr);

        if (mounted) {
          setState(() {
            _isSaving = false;
            if (success) {
              _hasPendingOfflineChanges = false;
              _lastSyncedTime = DateTime.now();
              _saveLocalSlotMetadata(eventKey);
            }
          });

          if (isReconnecting && success) {
            ScaffoldMessenger.of(context).hideCurrentSnackBar();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Reconnected! Synced offline changes (Last Write Wins)'),
                backgroundColor: ObsidianUITheme.successGreen,
                behavior: SnackBarBehavior.floating,
                duration: Duration(seconds: 3),
              ),
            );
          }
        }
      }
    }
  }

  Map<String, Map<String, int?>> _parseRawBoardJson(String rawJson) {
    final Map<String, Map<String, int?>> board = {};
    for (int i = 1; i <= 8; i++) {
      board['alliance$i'] = {'captain': null, 'firstPick': null, 'secondPick': null, 'backup': null};
    }
    if (rawJson.isEmpty || rawJson == '{}') return board;

    try {
      final Map<String, dynamic> parsed = jsonDecode(rawJson);
      for (int i = 1; i <= 8; i++) {
        final key = 'alliance$i';
        if (parsed.containsKey(key) && parsed[key] is Map) {
          final m = parsed[key] as Map;
          board[key] = {
            'captain': (m['captain'] as num?)?.toInt(),
            'firstPick': (m['firstPick'] as num?)?.toInt(),
            'secondPick': (m['secondPick'] as num?)?.toInt(),
            'backup': (m['backup'] as num?)?.toInt(),
          };
        }
      }
    } catch (_) {}
    return board;
  }

  void _resetBoardStateInMemory() {
    for (int i = 1; i <= 8; i++) {
      _boardState['alliance$i'] = {
        'captain': null,
        'firstPick': null,
        'secondPick': null,
        'backup': null,
      };
    }
    _slotTimestamps.clear();
  }

  /// Handles slot mutations with local timestamp tracking & automatic offline catch-up queueing
  Future<void> _updateSlotAndSync(String allianceKey, String slotName, int? teamNumber) async {
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final slotKey = '${allianceKey}_$slotName';

    setState(() {
      _boardState[allianceKey]?[slotName] = teamNumber;
      _slotTimestamps[slotKey] = nowMs;
      _hasPendingOfflineChanges = true;
    });

    if (_selectedEventKey != null) {
      await _saveLocalSlotMetadata(_selectedEventKey!);
    }

    // Attempt instant push or queue offline
    await _catchUpAndSyncWithServer();
  }

  void _assignTeam(String allianceKey, String slotName, int teamNumber) {
    _updateSlotAndSync(allianceKey, slotName, teamNumber);
  }

  void _clearSlot(String allianceKey, String slotName) {
    _updateSlotAndSync(allianceKey, slotName, null);
  }

  void _resetBoard() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(context),
        title: Text('Reset Alliance Board?', style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context), fontWeight: FontWeight.bold)),
        content: Text('This will clear all captain and pick assignments across all 8 alliances on the server.', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: TextStyle(color: ObsidianUITheme.getTertiaryTextColor(context))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _resetBoardStateInMemory();
                _hasPendingOfflineChanges = true;
              });
              if (_selectedEventKey != null) {
                _saveLocalSlotMetadata(_selectedEventKey!);
              }
              _catchUpAndSyncWithServer();
            },
            child: const Text('RESET BOARD', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Set<int> get _pickedTeamNumbers {
    final Set<int> picked = {};
    for (final a in _boardState.values) {
      if (a['captain'] != null) picked.add(a['captain']!);
      if (a['firstPick'] != null) picked.add(a['firstPick']!);
      if (a['secondPick'] != null) picked.add(a['secondPick']!);
      if (a['backup'] != null) picked.add(a['backup']!);
    }
    return picked;
  }

  List<TeamModel> get _availableTeams {
    final picked = _pickedTeamNumbers;
    final query = _searchController.text.trim().toLowerCase();

    List<TeamModel> list = _allTeams.where((t) {
      if (picked.contains(t.teamNumber)) return false;
      if (query.isNotEmpty) {
        final matchNum = t.teamNumber.toString().contains(query);
        final matchNick = (t.nickname ?? '').toLowerCase().contains(query);
        final matchName = (t.name ?? '').toLowerCase().contains(query);
        return matchNum || matchNick || matchName;
      }
      return true;
    }).toList();

    if (_selectedMetric == 'scouted') {
      list.sort((a, b) => (b.averagePoints ?? -999).compareTo(a.averagePoints ?? -999));
    } else if (_selectedMetric == 'epa') {
      list.sort((a, b) => (b.epa ?? -999).compareTo(a.epa ?? -999));
    } else if (_selectedMetric == 'opr') {
      list.sort((a, b) => (b.opr ?? -999).compareTo(a.opr ?? -999));
    } else {
      list.sort((a, b) => b.calculatedWeighted.compareTo(a.calculatedWeighted));
    }

    return list;
  }

  void _openSelectorModal(String allianceKey, String slotName) {
    final available = _availableTeams;
    final int allianceNum = int.tryParse(allianceKey.replaceAll('alliance', '')) ?? 1;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              height: MediaQuery.of(context).size.height * 0.8,
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '${context.tr("alliance-selection.select_team")} — ${context.tr("alliances.alliances")} $allianceNum (${_formatSlotLabel(context, slotName)})',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                      ),
                      IconButton(
                        icon: Icon(Icons.close_rounded, color: ObsidianUITheme.getTertiaryTextColor(context)),
                        onPressed: () => Navigator.pop(ctx),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _searchController,
                    style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(context)),
                    decoration: InputDecoration(
                      hintText: context.tr('alliance-selection.placeholder_search_team_number_or_name'),
                      hintStyle: TextStyle(color: ObsidianUITheme.getFaintTextColor(context)),
                      prefixIcon: Icon(Icons.search_rounded, color: ObsidianUITheme.getFaintTextColor(context)),
                      filled: true,
                      fillColor: ObsidianUITheme.getInputFillColor(context),
                      contentPadding: const EdgeInsets.symmetric(vertical: 8),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                    onChanged: (val) {
                      setModalState(() {
                        _searchController.text = val;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: available.isEmpty
                        ? Center(child: Text('No available teams match query', style: TextStyle(color: ObsidianUITheme.getFaintTextColor(context))))
                        : ListView.builder(
                            itemCount: available.length,
                            itemBuilder: (context, idx) {
                              final team = available[idx];
                              return Card(
                                color: ObsidianUITheme.getBorderColor(context),
                                margin: const EdgeInsets.only(bottom: 8.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                child: ListTile(
                                  onTap: () {
                                    Navigator.pop(ctx);
                                    _assignTeam(allianceKey, slotName, team.teamNumber);
                                  },
                                  leading: CircleAvatar(
                                    backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                                    child: Text(
                                      '#${idx + 1}',
                                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent),
                                    ),
                                  ),
                                  title: Text(
                                    team.displayName,
                                    style: TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context)),
                                  ),
                                  subtitle: Text(
                                    'Avg: ${team.averagePoints?.toStringAsFixed(1) ?? '-'} | EPA: ${team.epa?.toStringAsFixed(1) ?? '-'} | OPR: ${team.opr?.toStringAsFixed(1) ?? '-'}',
                                    style: TextStyle(fontSize: 11, color: ObsidianUITheme.getTertiaryTextColor(context)),
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.cyanAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      'W: ${team.calculatedWeighted.toStringAsFixed(1)}',
                                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.cyanAccent),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showTeamProfile(TeamModel team) {
    showModalBottomSheet(
      context: context,
      backgroundColor: ObsidianUITheme.getSurfaceColor(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (ctx) {
        return Container(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Team #${team.teamNumber} — Profile',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: ObsidianUITheme.getTertiaryTextColor(context)),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              if (team.nickname != null || team.name != null)
                Text(
                  team.nickname ?? team.name ?? '',
                  style: const TextStyle(color: ObsidianUITheme.primaryAccent, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Scouted Avg', team.averagePoints?.toStringAsFixed(1) ?? '-', Colors.amberAccent)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('Statbotics EPA', team.epa?.toStringAsFixed(1) ?? '-', Colors.cyanAccent)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildMetricCard('TBA OPR', team.opr?.toStringAsFixed(1) ?? '-', Colors.lightGreenAccent)),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ObsidianUITheme.getBorderColor(context),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Weighted Performance Score:', style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(context), fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(
                      'Score = (Avg × 1.0 + EPA × 0.8 + OPR × 0.6) / Weights = ${team.calculatedWeighted.toStringAsFixed(1)}',
                      style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetricCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Text(label, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: ObsidianUITheme.getPrimaryTextColor(context))),
        ],
      ),
    );
  }

  String _formatSlotLabel(BuildContext context, String slot) {
    if (slot == 'captain') return context.tr('alliance_selection.captain');
    if (slot == 'firstPick') return context.tr('alliance_selection.first_pick');
    if (slot == 'secondPick') return context.tr('alliance_selection.second_pick');
    if (slot == 'backup') return context.tr('alliance_selection.backup');
    return slot;
  }

  @override
  Widget build(BuildContext context) {
    final mediaWidth = MediaQuery.of(context).size.width;
    final bool isWideScreen = mediaWidth >= 800; // Desktop / Wide layout matching server

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOutCubic,
          height: widget.isBarsVisible ? 95.0 : 16.0,
        ),

        // Web-matching Header Card: Event Selection Dropdown & Reset Board Button
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: ObsidianGlassCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            context.tr('nav.alliance_selection'),
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            context.tr('subtitle.alliance_selection'),
                            style: const TextStyle(fontSize: 11, color: Colors.white54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      onPressed: _resetBoard,
                      icon: const Icon(Icons.refresh_rounded, size: 14),
                      label: Text(context.tr('graphs.clear_all'), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.2),
                        foregroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.event_note_rounded, color: Colors.cyanAccent, size: 20),
                    const SizedBox(width: 8),
                    Text('${context.tr("events.event").toUpperCase()}:', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white70, fontSize: 11)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Container(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        decoration: BoxDecoration(
                          color: Colors.black45,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.white10),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                            value: _selectedEventKey,
                            isExpanded: true,
                            dropdownColor: ObsidianUITheme.surface,
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            items: _events.map((e) {
                              return DropdownMenuItem<String>(
                                value: e.eventKey,
                                child: Text('${e.name} (${e.eventKey})', overflow: TextOverflow.ellipsis),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                setState(() {
                                  _selectedEventKey = val;
                                });
                                _loadEventData(val);
                              }
                            },
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (_isSaving)
                      const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent))
                    else
                      IconButton(
                        icon: const Icon(Icons.sync_rounded, color: Colors.cyanAccent, size: 20),
                        tooltip: context.tr('dashboard.quick_sync'),
                        onPressed: () => _catchUpAndSyncWithServer(),
                      ),
                  ],
                ),
                if (_lastSyncedTime != null || _allTeams.isNotEmpty || _hasPendingOfflineChanges)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 12.0,
                      runSpacing: 4.0,
                      children: [
                        Text(
                          '${context.tr("dashboard.teams")}: ${_allTeams.length} | Picked: ${_pickedTeamNumbers.length}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_hasPendingOfflineChanges) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.warningOrange.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: ObsidianUITheme.warningOrange, width: 0.8),
                                ),
                                child: Text(
                                  context.tr('connection.pending').toUpperCase(),
                                  style: const TextStyle(color: ObsidianUITheme.warningOrange, fontSize: 9, fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                            if (_lastSyncedTime != null) ...[
                              const Icon(Icons.bolt_rounded, color: ObsidianUITheme.successGreen, size: 14),
                              const SizedBox(width: 2),
                              Text(
                                '${context.tr("dashboard.last_sync")} ${_lastSyncedTime!.hour.toString().padLeft(2, '0')}:${_lastSyncedTime!.minute.toString().padLeft(2, '0')}:${_lastSyncedTime!.second.toString().padLeft(2, '0')}',
                                style: const TextStyle(color: ObsidianUITheme.successGreen, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 8),

        // Main Layout: Split Screen on Wide Screen, Tabs on Mobile
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent))
              : isWideScreen
                  ? Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left 2/3: 8 Alliances Grid
                          Expanded(
                            flex: 2,
                            child: _buildAlliancesGrid(),
                          ),
                          const SizedBox(width: 16),
                          // Right 1/3: Recommendations Panel
                          Expanded(
                            flex: 1,
                            child: _buildRecommendationsPanel(),
                          ),
                        ],
                      ),
                    )
                  : Column(
                      children: [
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 16.0),
                          decoration: BoxDecoration(
                            color: ObsidianUITheme.getInputFillColor(context),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: TabBar(
                            controller: _tabController,
                            indicatorColor: ObsidianUITheme.primaryAccent,
                            labelColor: ObsidianUITheme.primaryAccent,
                            unselectedLabelColor: ObsidianUITheme.getSecondaryTextColor(context),
                            tabs: [
                              Tab(icon: const Icon(Icons.groups_rounded, size: 18), text: context.tr('nav.alliances')),
                              Tab(icon: const Icon(Icons.insights_rounded, size: 18), text: context.tr('nav.analytics')),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: TabBarView(
                            controller: _tabController,
                            children: [
                              _buildAlliancesGrid(),
                              _buildRecommendationsPanel(),
                            ],
                          ),
                        ),
                      ],
                    ),
        ),
      ],
    );
  }

  Widget _buildAlliancesGrid() {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(0, 4.0, 0, widget.isBarsVisible ? 100.0 : 20.0),
      itemCount: 8,
      itemBuilder: (context, idx) {
        final allianceNum = idx + 1;
        final key = 'alliance$allianceNum';
        final alliance = _boardState[key]!;

        final bool isFull = alliance['captain'] != null && alliance['firstPick'] != null && alliance['secondPick'] != null;

        return ObsidianGlassCard(
          margin: const EdgeInsets.only(bottom: 12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isFull ? ObsidianUITheme.successGreen.withValues(alpha: 0.2) : ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: isFull ? ObsidianUITheme.successGreen : ObsidianUITheme.primaryAccent),
                    ),
                    child: Text(
                      'ALLIANCE $allianceNum',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isFull ? ObsidianUITheme.successGreen : Colors.cyanAccent,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: ObsidianUITheme.getTertiaryTextColor(context), size: 18),
                    tooltip: 'Clear Alliance $allianceNum',
                    onPressed: () {
                      _clearSlot(key, 'captain');
                      _clearSlot(key, 'firstPick');
                      _clearSlot(key, 'secondPick');
                      _clearSlot(key, 'backup');
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _buildSlotTile(key, 'captain', alliance['captain'], Colors.amberAccent)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildSlotTile(key, 'firstPick', alliance['firstPick'], Colors.cyanAccent)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _buildSlotTile(key, 'secondPick', alliance['secondPick'], Colors.lightGreenAccent)),
                  const SizedBox(width: 8),
                  Expanded(child: _buildSlotTile(key, 'backup', alliance['backup'], Colors.purpleAccent)),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSlotTile(String allianceKey, String slotName, int? teamNumber, Color accentColor) {
    final bool isEmpty = teamNumber == null;
    final teamObj = isEmpty ? null : _allTeams.firstWhere((t) => t.teamNumber == teamNumber, orElse: () => TeamModel(eventKey: '', teamKey: '', teamNumber: teamNumber));
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return GestureDetector(
      onTap: () {
        if (isEmpty) {
          _openSelectorModal(allianceKey, slotName);
        } else if (teamObj != null) {
          _showTeamProfile(teamObj);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isEmpty ? borderColor.withValues(alpha: 0.3) : accentColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: isEmpty ? borderColor : accentColor.withValues(alpha: 0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                SizedBox(
                  width: 75,
                  child: Text(
                    _formatSlotLabel(context, slotName).toUpperCase(),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: accentColor),
                  ),
                ),
                if (!isEmpty)
                  GestureDetector(
                    onTap: () => _clearSlot(allianceKey, slotName),
                    child: Icon(Icons.close_rounded, size: 14, color: ObsidianUITheme.getSecondaryTextColor(context)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              isEmpty ? context.tr('scout.select_team') : (teamObj?.displayName ?? 'Team #$teamNumber'),
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isEmpty ? ObsidianUITheme.getFaintTextColor(context) : ObsidianUITheme.getPrimaryTextColor(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecommendationsPanel() {
    final available = _availableTeams;
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final faintTextColor = ObsidianUITheme.getFaintTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final surfaceColor = ObsidianUITheme.getSurfaceColor(context);
    final inputFillColor = ObsidianUITheme.getInputFillColor(context);

    return ObsidianGlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('alliance-selection.recommendations'),
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: primaryTextColor),
          ),
          const SizedBox(height: 10),

          // Search & Metric Filter Bar
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: TextField(
                    controller: _searchController,
                    style: TextStyle(color: primaryTextColor, fontSize: 12),
                    decoration: InputDecoration(
                      hintText: context.tr('alliance-selection.placeholder_search_team_or_name'),
                      hintStyle: TextStyle(color: faintTextColor, fontSize: 11),
                      prefixIcon: Icon(Icons.search_rounded, color: faintTextColor, size: 16),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      fillColor: inputFillColor,
                      filled: true,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                decoration: BoxDecoration(
                  color: inputFillColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: borderColor),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedMetric,
                    dropdownColor: surfaceColor,
                    style: const TextStyle(color: Colors.cyanAccent, fontSize: 11, fontWeight: FontWeight.bold),
                    items: [
                      DropdownMenuItem(value: 'weighted', child: Text(context.tr('alliance-selection.weighted'))),
                      DropdownMenuItem(value: 'scouted', child: Text(context.tr('alliance-selection.scouted_avg'))),
                      DropdownMenuItem(value: 'epa', child: Text(context.tr('alliance-selection.epa'))),
                      DropdownMenuItem(value: 'opr', child: Text(context.tr('alliance-selection.opr'))),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setState(() {
                          _selectedMetric = val;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Available Teams List
          Expanded(
            child: available.isEmpty
                ? Center(
                    child: Text(
                      'No available teams match filter',
                      style: TextStyle(color: faintTextColor, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: 20.0),
                    itemCount: available.length,
                    itemBuilder: (context, idx) {
                      final team = available[idx];

                      String scoreDisplay = team.calculatedWeighted.toStringAsFixed(1);
                      if (_selectedMetric == 'scouted') {
                        scoreDisplay = team.averagePoints?.toStringAsFixed(1) ?? '-';
                      } else if (_selectedMetric == 'epa') {
                        scoreDisplay = team.epa?.toStringAsFixed(1) ?? '-';
                      } else if (_selectedMetric == 'opr') {
                        scoreDisplay = team.opr?.toStringAsFixed(1) ?? '-';
                      }

                      return Container(
                        margin: const EdgeInsets.only(bottom: 6.0),
                        decoration: BoxDecoration(
                          color: borderColor.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderColor),
                        ),
                        child: ListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                          onTap: () => _showTeamProfile(team),
                          leading: CircleAvatar(
                            radius: 14,
                            backgroundColor: ObsidianUITheme.primaryAccent.withValues(alpha: 0.2),
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: ObsidianUITheme.primaryAccent, fontSize: 10),
                            ),
                          ),
                          title: Text(
                            team.displayName,
                            style: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 12),
                          ),
                          subtitle: Text(
                            'Avg: ${team.averagePoints?.toStringAsFixed(1) ?? '-'} | EPA: ${team.epa?.toStringAsFixed(1) ?? '-'} | OPR: ${team.opr?.toStringAsFixed(1) ?? '-'}',
                            style: TextStyle(fontSize: 10, color: secondaryTextColor),
                          ),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.cyanAccent.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              scoreDisplay,
                              style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.cyanAccent, fontSize: 11),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
