import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../models/api_response.dart';
import '../models/team_match_models.dart';
import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../theme/obsidian_responsive.dart';
import '../widgets/obsidian_glass_card.dart';

class EventsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const EventsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  @override
  State<EventsScreen> createState() => _EventsScreenState();
}

class _EventsScreenState extends State<EventsScreen> {
  List<EventModel> _events = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  String _searchQuery = '';

  bool get _isAdmin {
    final role = widget.apiService.currentUserRole.toUpperCase();
    return role == 'ADMIN' || role == 'SUPERADMIN';
  }

  @override
  void initState() {
    super.initState();
    _loadEvents();
  }

  @override
  void didUpdateWidget(covariant EventsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) {
      _loadEvents();
    }
  }

  Future<void> _loadEvents() async {
    final cached = await widget.apiService.getCachedEvents();
    if (mounted && cached.isNotEmpty) {
      setState(() {
        _events = cached;
        _isLoading = false;
      });
    }

    if (!widget.apiService.isOnline) {
      if (mounted && _isLoading) setState(() => _isLoading = false);
      return;
    }

    try {
      final events = await widget.apiService.fetchEvents();
      if (mounted) {
        setState(() {
          if (events.isNotEmpty) {
            _events = events;
          }
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted && _isLoading) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleSyncEvents() async {
    if (_isSyncing || !_isAdmin) return;
    setState(() => _isSyncing = true);

    final res = await widget.apiService.syncEvents();
    if (!mounted) return;
    setState(() => _isSyncing = false);

    if (res.isSuccess) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.data ?? context.tr('events.synced', 'Events synced')),
          backgroundColor: ObsidianUITheme.successGreen,
        ),
      );
      await _loadEvents();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? context.tr('events.sync_failed', 'Sync failed')),
          backgroundColor: ObsidianUITheme.errorRed,
        ),
      );
    }
  }

  Future<void> _handleDeleteEvent(EventModel event) async {
    if (!_isAdmin) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: ObsidianUITheme.getBorderColor(ctx)),
        ),
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: ObsidianUITheme.errorRed, size: 24),
            const SizedBox(width: 8),
            Text(
              context.tr('common.confirm', 'Confirm Delete'),
              style: TextStyle(color: ObsidianUITheme.getPrimaryTextColor(ctx), fontSize: 18),
            ),
          ],
        ),
        content: Text(
          context.tr(
            'events.confirm_delete',
            'Are you SURE you want to delete this event (${event.name})? This will permanently delete all associated teams, matches, and scouting entries!',
          ),
          style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(context.tr('common.cancel', 'Cancel'), style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: ObsidianUITheme.errorRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(context.tr('common.delete', 'Delete'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final res = await widget.apiService.deleteEvent(event.eventKey);
      if (!mounted) return;
      if (res.isSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.tr('events.deleted_success', 'Event deleted successfully')),
            backgroundColor: ObsidianUITheme.successGreen,
          ),
        );
        await _loadEvents();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.message ?? context.tr('events.delete_failed', 'Failed to delete event')),
            backgroundColor: ObsidianUITheme.errorRed,
          ),
        );
      }
    }
  }

  void _openEventModal([EventModel? existingEvent]) {
    if (!_isAdmin) return;

    final isEditing = existingEvent != null;
    final keyController = TextEditingController(text: existingEvent?.eventKey ?? '');
    final nameController = TextEditingController(text: existingEvent?.name ?? '');
    final yearController = TextEditingController(
      text: (existingEvent?.year ?? widget.apiService.currentSettings?.year ?? DateTime.now().year).toString(),
    );
    final startDateController = TextEditingController(text: existingEvent?.startDate ?? '');
    final endDateController = TextEditingController(text: existingEvent?.endDate ?? '');
    String selectedTimezone = existingEvent?.timezone ?? 'America/Chicago';

    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (modalCtx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: ObsidianUITheme.getSurfaceColor(ctx),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(color: ObsidianUITheme.getBorderColor(ctx)),
              ),
              title: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    isEditing
                        ? context.tr('events.edit_event', 'Edit Event')
                        : context.tr('events.create_custom', 'Create Custom Event'),
                    style: TextStyle(
                      color: ObsidianUITheme.getPrimaryTextColor(ctx),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 20),
                    onPressed: () => Navigator.of(modalCtx).pop(),
                  ),
                ],
              ),
              content: SizedBox(
                width: 500,
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('events.event_key', 'Event Key'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(ctx)),
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: keyController,
                          decoration: InputDecoration(
                            hintText: 'e.g. 2026txcha',
                            filled: true,
                            fillColor: ObsidianUITheme.getSurfaceColor(ctx),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          validator: (v) {
                            if (v == null || v.trim().isEmpty) return 'Event key is required';
                            if (v.contains(' ')) return 'Key cannot contain spaces';
                            return null;
                          },
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('events.event_name', 'Event Name'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(ctx)),
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: nameController,
                          decoration: InputDecoration(
                            hintText: 'e.g. Texas Championship',
                            filled: true,
                            fillColor: ObsidianUITheme.getSurfaceColor(ctx),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('events.year', 'Year'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(ctx)),
                        ),
                        const SizedBox(height: 4),
                        TextFormField(
                          controller: yearController,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            hintText: '2026',
                            filled: true,
                            fillColor: ObsidianUITheme.getSurfaceColor(ctx),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          ),
                          validator: (v) => int.tryParse(v ?? '') == null ? 'Valid year required' : null,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('events.start_date', 'Start Date'),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(ctx)),
                                  ),
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: startDateController,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
                                      filled: true,
                                      fillColor: ObsidianUITheme.getSurfaceColor(ctx),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    onTap: () async {
                                      final now = DateTime.now();
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: DateTime.tryParse(startDateController.text) ?? now,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        startDateController.text =
                                            "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    context.tr('events.end_date', 'End Date'),
                                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(ctx)),
                                  ),
                                  const SizedBox(height: 4),
                                  TextFormField(
                                    controller: endDateController,
                                    readOnly: true,
                                    decoration: InputDecoration(
                                      hintText: 'YYYY-MM-DD',
                                      suffixIcon: const Icon(Icons.calendar_today_rounded, size: 16),
                                      filled: true,
                                      fillColor: ObsidianUITheme.getSurfaceColor(ctx),
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                    ),
                                    onTap: () async {
                                      final now = DateTime.now();
                                      final picked = await showDatePicker(
                                        context: ctx,
                                        initialDate: DateTime.tryParse(endDateController.text) ?? now,
                                        firstDate: DateTime(2000),
                                        lastDate: DateTime(2100),
                                      );
                                      if (picked != null) {
                                        endDateController.text =
                                            "${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}";
                                      }
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          context.tr('events.timezone', 'Timezone'),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: ObsidianUITheme.getSecondaryTextColor(ctx)),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: ObsidianUITheme.getSurfaceColor(ctx),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: ObsidianUITheme.getBorderColor(ctx)),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: selectedTimezone,
                              isExpanded: true,
                              items: const [
                                DropdownMenuItem(value: 'America/New_York', child: Text('America/New_York (Eastern)')),
                                DropdownMenuItem(value: 'America/Chicago', child: Text('America/Chicago (Central)')),
                                DropdownMenuItem(value: 'America/Denver', child: Text('America/Denver (Mountain)')),
                                DropdownMenuItem(value: 'America/Los_Angeles', child: Text('America/Los_Angeles (Pacific)')),
                                DropdownMenuItem(value: 'America/Phoenix', child: Text('America/Phoenix (Arizona)')),
                                DropdownMenuItem(value: 'America/Anchorage', child: Text('America/Anchorage (Alaska)')),
                                DropdownMenuItem(value: 'Pacific/Honolulu', child: Text('Pacific/Honolulu (Hawaii)')),
                                DropdownMenuItem(value: 'UTC', child: Text('UTC')),
                                DropdownMenuItem(value: 'Europe/London', child: Text('Europe/London')),
                                DropdownMenuItem(value: 'Europe/Paris', child: Text('Europe/Paris')),
                                DropdownMenuItem(value: 'Asia/Tokyo', child: Text('Asia/Tokyo')),
                                DropdownMenuItem(value: 'Australia/Sydney', child: Text('Australia/Sydney')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setModalState(() => selectedTimezone = val);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving ? null : () => Navigator.of(modalCtx).pop(),
                  child: Text(context.tr('events.cancel', 'Cancel'), style: TextStyle(color: ObsidianUITheme.getSecondaryTextColor(ctx))),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: ObsidianUITheme.primaryAccent,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setModalState(() => isSaving = true);

                          final eventModel = EventModel(
                            eventKey: keyController.text.trim().toLowerCase(),
                            name: nameController.text.trim(),
                            year: int.tryParse(yearController.text.trim()),
                            startDate: startDateController.text.isNotEmpty ? startDateController.text.trim() : null,
                            endDate: endDateController.text.isNotEmpty ? endDateController.text.trim() : null,
                            timezone: selectedTimezone,
                          );

                          ApiResponse<bool> res;
                          if (isEditing) {
                            res = await widget.apiService.updateEvent(
                              oldKey: existingEvent.eventKey,
                              event: eventModel,
                            );
                          } else {
                            res = await widget.apiService.createEvent(eventModel);
                          }

                          setModalState(() => isSaving = false);
                          if (!mounted) return;

                          if (res.isSuccess) {
                            Navigator.of(modalCtx).pop();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(context.tr('events.saved_success', 'Event saved successfully')),
                                backgroundColor: ObsidianUITheme.successGreen,
                              ),
                            );
                            await _loadEvents();
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(res.message ?? context.tr('events.save_failed', 'Failed to save event')),
                                backgroundColor: ObsidianUITheme.errorRed,
                              ),
                            );
                          }
                        },
                  child: isSaving
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text(context.tr('events.save_event', 'Save Event'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<EventModel> get _filteredEvents {
    final q = _searchQuery.toLowerCase().trim();
    if (q.isEmpty) return _events;
    return _events.where((e) {
      return e.name.toLowerCase().contains(q) || e.eventKey.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final isDesktop = ObsidianResponsive.isDesktop(context, overrideMode: widget.apiService.uiMode);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: _loadEvents,
        color: ObsidianUITheme.primaryAccent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
          padding: EdgeInsets.fromLTRB(16, isDesktop ? 16 : 8, 16, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1400),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Action & Header Card
                  ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.event_rounded, color: ObsidianUITheme.primaryAccent, size: 24),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      context.tr('events.title', 'Events'),
                                      style: TextStyle(
                                        fontSize: 20,
                                        fontWeight: FontWeight.bold,
                                        color: primaryTextColor,
                                        letterSpacing: -0.3,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      context.tr('events.notice', 'Sync events for the selected season and pick an event for scouting.'),
                                      style: TextStyle(fontSize: 13, color: secondaryTextColor),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (_isAdmin) ...[
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: ObsidianUITheme.primaryAccent,
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: _isSyncing ? null : _handleSyncEvents,
                                  icon: _isSyncing
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                                        )
                                      : const Icon(Icons.sync_rounded, color: Colors.white, size: 18),
                                  label: Text(
                                    context.tr('events.sync_events', 'Sync events'),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: BorderSide(color: borderColor),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                  ),
                                  onPressed: () => _openEventModal(),
                                  icon: Icon(Icons.add_rounded, color: primaryTextColor, size: 18),
                                  label: Text(
                                    context.tr('events.add_manual', 'Add Event Manually'),
                                    style: TextStyle(color: primaryTextColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                              SizedBox(
                                width: 280,
                                child: TextField(
                                  decoration: InputDecoration(
                                    hintText: 'Search events or keys...',
                                    prefixIcon: const Icon(Icons.search_rounded, size: 18),
                                    filled: true,
                                    fillColor: ObsidianUITheme.getSurfaceColor(context),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(10),
                                      borderSide: BorderSide(color: borderColor),
                                    ),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                  ),
                                  onChanged: (val) => setState(() => _searchQuery = val),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Events Table / Cards Card
                  ObsidianGlassCard(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'Season Events (${_filteredEvents.length})',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: primaryTextColor,
                                ),
                              ),
                              if (_isLoading)
                                const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: ObsidianUITheme.primaryAccent),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          if (_isLoading && _events.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: CircularProgressIndicator(color: ObsidianUITheme.primaryAccent),
                              ),
                            )
                          else if (_filteredEvents.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 40),
                              child: Center(
                                child: Text(
                                  'No events found',
                                  style: TextStyle(color: secondaryTextColor, fontSize: 14),
                                ),
                              ),
                            )
                          else if (isDesktop)
                            _buildDesktopTable(_filteredEvents)
                          else
                            _buildMobileList(_filteredEvents),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTable(List<EventModel> events) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 900),
        child: DataTable(
          headingTextStyle: TextStyle(fontWeight: FontWeight.bold, color: primaryTextColor, fontSize: 13),
          dataTextStyle: TextStyle(color: primaryTextColor, fontSize: 13),
          dividerThickness: 0.5,
          horizontalMargin: 12,
          columnSpacing: 24,
          columns: [
            DataColumn(label: Text(context.tr('events.event', 'Event'))),
            DataColumn(label: Text(context.tr('events.key', 'Key'))),
            DataColumn(label: Text(context.tr('events.dates', 'Dates'))),
            DataColumn(label: Text(context.tr('events.timezone', 'Timezone'))),
            if (_isAdmin) DataColumn(label: Text(context.tr('events.action', 'Action'))),
          ],
          rows: events.map((e) {
            final datesStr = (e.startDate != null || e.endDate != null)
                ? '${e.startDate ?? ""} - ${e.endDate ?? ""}'
                : '—';

            return DataRow(
              cells: [
                DataCell(
                  Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                DataCell(
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: ObsidianUITheme.getSurfaceColor(context),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: borderColor),
                    ),
                    child: Text(e.eventKey, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
                  ),
                ),
                DataCell(Text(datesStr)),
                DataCell(Text(e.timezone ?? '—', style: TextStyle(color: secondaryTextColor))),
                if (_isAdmin)
                  DataCell(
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit_rounded, size: 18, color: ObsidianUITheme.primaryAccent),
                          tooltip: context.tr('common.edit', 'Edit'),
                          onPressed: () => _openEventModal(e),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded, size: 18, color: ObsidianUITheme.errorRed),
                          tooltip: context.tr('common.delete', 'Delete'),
                          onPressed: () => _handleDeleteEvent(e),
                        ),
                      ],
                    ),
                  ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildMobileList(List<EventModel> events) {
    final primaryTextColor = ObsidianUITheme.getPrimaryTextColor(context);
    final secondaryTextColor = ObsidianUITheme.getSecondaryTextColor(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: events.length,
      separatorBuilder: (_, __) => Divider(color: borderColor, height: 1),
      itemBuilder: (ctx, index) {
        final e = events[index];
        final datesStr = (e.startDate != null || e.endDate != null)
            ? '${e.startDate ?? ""} - ${e.endDate ?? ""}'
            : null;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      e.name,
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: primaryTextColor),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            e.eventKey,
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: ObsidianUITheme.primaryAccent,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        if (e.timezone != null) ...[
                          const SizedBox(width: 8),
                          Text(e.timezone!, style: TextStyle(fontSize: 11, color: secondaryTextColor)),
                        ],
                      ],
                    ),
                    if (datesStr != null) ...[
                      const SizedBox(height: 4),
                      Text(datesStr, style: TextStyle(fontSize: 12, color: secondaryTextColor)),
                    ],
                  ],
                ),
              ),
              if (_isAdmin)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_rounded, size: 20, color: ObsidianUITheme.primaryAccent),
                      onPressed: () => _openEventModal(e),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20, color: ObsidianUITheme.errorRed),
                      onPressed: () => _handleDeleteEvent(e),
                    ),
                  ],
                ),
            ],
          ),
        );
      },
    );
  }
}
