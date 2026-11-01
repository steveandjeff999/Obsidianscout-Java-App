import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart' show GZipEncoder;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import '../services/live_refresh.dart';
import '../services/image_utils.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_feedback.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';

/// Announcements, images and files the team's admins post for the current event.
/// Same data as the website's event-info.html; admins can post, edit and delete here too.
class EventInfoScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const EventInfoScreen({super.key, required this.apiService, this.isVisible = true, this.isBarsVisible = true});

  @override
  State<EventInfoScreen> createState() => _EventInfoScreenState();
}

class _PendingFile {
  final String name;
  final Uint8List bytes;
  final int? originalSize;
  const _PendingFile(this.name, this.bytes, {this.originalSize});
}

final _urlPattern = RegExp(r'https?://[^\s<>"]+');

class _EventInfoScreenState extends State<EventInfoScreen> with LiveRefresh<EventInfoScreen> {
  @override
  ApiService get liveApi => widget.apiService;

  @override
  bool get liveVisible => widget.isVisible;

  @override
  Set<String> get liveTopics => const {'event-info'};

  @override
  Future<void> liveReload() => _load();

  bool _loading = true;
  String? _error;
  String _eventKey = '';
  bool _canEdit = false;
  int _maxFileBytes = 15 * 1024 * 1024;
  List<Map<String, dynamic>> _posts = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant EventInfoScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isVisible && !oldWidget.isVisible) _load();
  }

  Future<void> _load() async {
    if (!isLiveRefreshing) setState(() => _loading = _posts.isEmpty);
    final res = await widget.apiService.requestJson('GET', '/api/event-info', cacheKey: 'cache_event_info');
    if (!mounted) return;
    if (isLiveRefreshing && !res.success) return;
    setState(() {
      _loading = false;
      if (res.success) {
        final data = jsonMap(res.data);
        _error = null;
        _eventKey = jsonStr(data['eventKey']);
        _canEdit = jsonBool(data['canEdit']);
        _maxFileBytes = jsonInt(data['maxFileBytes']) ?? _maxFileBytes;
        _posts = jsonMaps(data['posts']);
      } else {
        _error = res.message ?? context.tr('event_info.err_load', 'Failed to load event info: ');
      }
    });
  }

  String _fileUrl(Map<String, dynamic> file) => '${widget.apiService.currentServerUrl}${jsonStr(file['url'])}';

  /// Uploads [files] one at a time; returns how many failed.
  Future<int> _upload(String postId, List<_PendingFile> files) async {
    var failed = 0;
    for (final f in files) {
      final res = await widget.apiService.uploadFile('/api/event-info/${Uri.encodeComponent(postId)}/files', bytes: f.bytes, filename: f.name);
      if (!res.success) {
        failed++;
        if (mounted) ObsidianFeedback.showError(context, message: '${f.name}: ${res.message ?? ''}');
      }
    }
    return failed;
  }

  Future<void> _editPost(Map<String, dynamic>? post) async {
    final result = await showDialog<_PostDialogResult>(
      context: context,
      builder: (_) => _PostDialog(post: post, maxFileBytes: _maxFileBytes, apiService: widget.apiService),
    );
    if (result == null || !mounted) return;
    final res = post == null
        ? await widget.apiService.requestJson('POST', '/api/event-info', body: result.body)
        : await widget.apiService.requestJson('PUT', '/api/event-info/${post['id']}', body: result.body);
    if (!mounted) return;
    if (!res.success) {
      reportResult(context, res, action: post == null ? context.tr('event_info.btn_post', 'Post') : context.tr('event_info.edit', 'Edit'));
      return;
    }
    final failed = await _upload(jsonStr(jsonMap(res.data)['id']), result.files);
    if (!mounted) return;
    if (failed == 0) {
      ObsidianFeedback.showSuccess(context,
          message: post == null ? context.tr('event_info.toast_posted', 'Posted.') : context.tr('event_info.toast_updated', 'Post updated.'));
    }
    _load();
  }

  Future<void> _deletePost(Map<String, dynamic> post) async {
    final ok = await confirmPortedAction(context,
        title: context.tr('event_info.delete', 'Delete'),
        message: context.tr('event_info.confirm_delete', 'Delete this post and its files?'),
        destructive: true);
    if (!ok || !mounted) return;
    final res = await widget.apiService.requestJson('DELETE', '/api/event-info/${post['id']}');
    if (!mounted) return;
    if (reportResult(context, res,
        action: context.tr('event_info.delete', 'Delete'), success: context.tr('event_info.toast_deleted', 'Post deleted.'))) {
      _load();
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> file) async {
    final res = await widget.apiService.requestBytes(jsonStr(file['url']), query: {'download': '1'});
    if (!mounted) return;
    await saveDownloadedBytes(context, res, jsonStr(file['fileName'], 'file'), jsonStr(file['contentType'], 'application/octet-stream'));
  }

  void _openImage(Map<String, dynamic> file) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(children: [
          InteractiveViewer(
            maxScale: 5,
            child: Center(child: Image.network(_fileUrl(file), headers: widget.apiService.fileHeaders, fit: BoxFit.contain)),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: Row(children: [
              IconButton(
                tooltip: ctx.tr('event_info.download', 'Download'),
                color: Colors.white,
                icon: const Icon(Icons.download_rounded),
                onPressed: () => _downloadFile(file),
              ),
              IconButton(color: Colors.white, icon: const Icon(Icons.close_rounded), onPressed: () => Navigator.pop(ctx)),
            ]),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PortedPageList(
      onRefresh: _load,
      isBarsVisible: widget.isBarsVisible,
      children: [
        PortedSection(
          title: context.tr('event_info.title', 'Event Info'),
          subtitle: _eventKey.isNotEmpty
              ? context.trArgs('event_info.subtitle_event', 'Announcements, images and files for {event}.', {'event': _eventKey})
              : context.tr('event_info.subtitle', "Announcements, images and files from your team's admins."),
          actions: [
            if (_canEdit)
              FilledButton.icon(
                onPressed: () => _editPost(null),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: Text(context.tr('event_info.new_post', 'New Post')),
              ),
          ],
        ),
        if (_loading)
          const PortedLoading()
        else if (_error != null && _posts.isEmpty)
          PortedError(message: _error!, onRetry: _load)
        else if (_posts.isEmpty)
          PortedNotice(_canEdit
              ? context.tr('event_info.empty_admin', 'Nothing posted yet. Use the form above to share announcements, images and files.')
              : context.tr('event_info.empty', 'Nothing has been posted for this event yet.'))
        else
          for (final p in _posts) _buildPost(context, p),
      ],
    );
  }

  Widget _buildPost(BuildContext context, Map<String, dynamic> p) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    final accent = ObsidianUITheme.getPrimaryAccent(context);
    final pinned = jsonBool(p['pinned']);
    final files = jsonMaps(p['files']);
    final images = files.where((f) => jsonBool(f['isImage'])).toList();
    final others = files.where((f) => !jsonBool(f['isImage'])).toList();
    final title = jsonStr(p['title']);
    final body = jsonStr(p['body']);
    final eventKey = jsonStr(p['eventKey']);

    return ObsidianGlassCard(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      child: Container(
        padding: EdgeInsets.only(left: pinned ? 10 : 0),
        decoration: pinned ? BoxDecoration(border: Border(left: BorderSide(color: accent, width: 3))) : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  if (title.isNotEmpty)
                    Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: primary)),
                  const SizedBox(height: 4),
                  Wrap(spacing: 6, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                    if (pinned) PortedBadge(context.tr('event_info.pinned', 'Pinned'), color: accent),
                    PortedBadge(eventKey.isEmpty ? context.tr('event_info.every_event', 'Every event') : eventKey),
                    Text('${jsonStr(p['authorUsername'])} · ${fmtDateTime(context, p['createdAt'])}',
                        style: TextStyle(fontSize: 12, color: secondary)),
                  ]),
                ]),
              ),
              if (_canEdit) ...[
                IconButton(
                  tooltip: context.tr('event_info.edit', 'Edit'),
                  icon: const Icon(Icons.edit_rounded, size: 20),
                  onPressed: () => _editPost(p),
                ),
                IconButton(
                  tooltip: context.tr('event_info.delete', 'Delete'),
                  icon: Icon(Icons.delete_outline_rounded, size: 20, color: ObsidianUITheme.errorRed),
                  onPressed: () => _deletePost(p),
                ),
              ],
            ]),
            if (body.isNotEmpty) ...[
              const SizedBox(height: 10),
              _LinkedText(body, style: TextStyle(fontSize: 14, height: 1.45, color: primary), linkColor: accent),
            ],
            if (images.isNotEmpty) ...[
              const SizedBox(height: 10),
              GridView.count(
                crossAxisCount: MediaQuery.sizeOf(context).width > 700 ? 4 : 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 8,
                crossAxisSpacing: 8,
                childAspectRatio: 4 / 3,
                children: [
                  for (final img in images)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        onTap: () => _openImage(img),
                        child: Image.network(
                          _fileUrl(img),
                          headers: widget.apiService.fileHeaders,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: ObsidianUITheme.getSurfaceColor(context),
                            alignment: Alignment.center,
                            child: Icon(Icons.broken_image_rounded, color: secondary),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
            if (others.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final f in others)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.insert_drive_file_rounded, color: secondary),
                  title: Text(jsonStr(f['fileName']), maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontWeight: FontWeight.w600, color: primary)),
                  subtitle: Text(fmtBytes(f['sizeBytes']), style: TextStyle(fontSize: 12, color: secondary)),
                  trailing: IconButton(
                    tooltip: context.tr('event_info.download', 'Download'),
                    icon: const Icon(Icons.download_rounded),
                    onPressed: () => _downloadFile(f),
                  ),
                  onTap: () => _downloadFile(f),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Plain text with http(s) links that open in the browser.
class _LinkedText extends StatelessWidget {
  final String text;
  final TextStyle style;
  final Color linkColor;
  const _LinkedText(this.text, {required this.style, required this.linkColor});

  @override
  Widget build(BuildContext context) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlPattern.allMatches(text)) {
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      final url = m.group(0)!;
      spans.add(WidgetSpan(
        alignment: PlaceholderAlignment.baseline,
        baseline: TextBaseline.alphabetic,
        child: GestureDetector(
          onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
          child: Text(url, style: style.copyWith(color: linkColor, decoration: TextDecoration.underline)),
        ),
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return SelectableText.rich(TextSpan(style: style, children: spans));
  }
}

class _PostDialogResult {
  final Map<String, dynamic> body;
  final List<_PendingFile> files;
  const _PostDialogResult(this.body, this.files);
}

class _PostDialog extends StatefulWidget {
  final Map<String, dynamic>? post;
  final int maxFileBytes;
  final ApiService apiService;
  const _PostDialog({this.post, required this.maxFileBytes, required this.apiService});

  @override
  State<_PostDialog> createState() => _PostDialogState();
}

class _PostDialogState extends State<_PostDialog> {
  late final _title = TextEditingController(text: jsonStr(widget.post?['title']));
  late final _body = TextEditingController(text: jsonStr(widget.post?['body']));
  late bool _pinned = jsonBool(widget.post?['pinned']);
  late bool _allEvents = widget.post != null && jsonStr(widget.post!['eventKey']).isEmpty;
  late List<Map<String, dynamic>> _existing = jsonMaps(widget.post?['files']);
  final List<_PendingFile> _pending = [];
  bool _picking = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  static Uint8List _gzip(Uint8List bytes) => Uint8List.fromList(GZipEncoder().encode(bytes));

  /// Returns the smallest attempt, even if it is still over [maxBytes].
  Future<_PendingFile> _compressToFit(String name, Uint8List bytes, int maxBytes) async {
    var best = _PendingFile(name, bytes);
    final lower = name.toLowerCase();
    if (lower.endsWith('.png') || lower.endsWith('.jpg') || lower.endsWith('.jpeg') || lower.endsWith('.webp')) {
      try {
        final processed = await ImageProcessingUtils.processImageBytesAsync(
          bytes,
          maxDimension: 3840,
          quality: 85,
          slowLink: false,
          budgetBytes: maxBytes,
        );
        final imgBytes = ImageProcessingUtils.dataUrlToBytes(processed?.dataUrl);
        if (imgBytes != null && imgBytes.length < best.bytes.length) {
          final webpName = '${name.replaceFirst(RegExp(r'\.[^.]+$'), '')}.webp';
          best = _PendingFile(webpName, imgBytes, originalSize: bytes.length);
          if (imgBytes.length <= maxBytes) return best;
        }
      } catch (_) {}
    }
    try {
      final compressed = await Isolate.run(() => _gzip(bytes));
      if (compressed.length < best.bytes.length) {
        best = _PendingFile(name, compressed, originalSize: bytes.length);
      }
    } catch (_) {}
    return best;
  }

  Future<void> _pick() async {
    final picked = await FilePicker.pickFiles();
    if (!mounted) return;
    setState(() => _picking = true);
    try {
      for (final f in picked) {
        final bytes = await f.readAsBytes();
        if (!mounted) return;
        final file = bytes.length > widget.maxFileBytes
            ? await _compressToFit(f.name, bytes, widget.maxFileBytes)
            : _PendingFile(f.name, bytes);
        if (!mounted) return;
        if (file.bytes.length > widget.maxFileBytes) {
          ObsidianFeedback.showError(context,
              message: context.trArgs('event_info.err_too_large_compressed', '{name} is still {size} after compression. The limit is {limit}.',
                  {'name': f.name, 'size': fmtBytes(file.bytes.length), 'limit': fmtBytes(widget.maxFileBytes)}));
          continue;
        }
        setState(() => _pending.add(file));
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _removeExisting(Map<String, dynamic> file) async {
    final ok = await confirmPortedAction(context,
        title: context.tr('event_info.remove', 'Remove'),
        message: context.trArgs('event_info.confirm_remove_file', 'Remove {name}?', {'name': jsonStr(file['fileName'])}),
        destructive: true);
    if (!ok || !mounted) return;
    final res = await widget.apiService.requestJson('DELETE', '/api/event-info/files/${file['id']}');
    if (!mounted) return;
    if (reportResult(context, res, action: context.tr('event_info.remove', 'Remove'))) {
      setState(() => _existing = _existing.where((f) => f['id'] != file['id']).toList());
    }
  }

  void _submit() {
    if (widget.post == null && _title.text.trim().isEmpty && _body.text.trim().isEmpty && _pending.isEmpty) {
      setState(() => _error = context.tr('event_info.err_empty', 'Add a title, an announcement or a file.'));
      return;
    }
    Navigator.pop(
      context,
      _PostDialogResult({
        'title': _title.text,
        'body': _body.text,
        'pinned': _pinned,
        'allEvents': _allEvents,
      }, List.of(_pending)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final surface = ObsidianUITheme.getSurfaceColor(context);
    final secondary = ObsidianUITheme.getSecondaryTextColor(context);
    return AlertDialog(
      backgroundColor: surface,
      title: Text(widget.post == null
          ? context.tr('event_info.new_post', 'New Post')
          : context.tr('event_info.edit_post', 'Edit Post')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _title,
                maxLength: 200,
                decoration: InputDecoration(
                  labelText: context.tr('event_info.post_title', 'Title'),
                  hintText: context.tr('event_info.placeholder_title', 'e.g. Pit map and load-in times'),
                ),
              ),
              TextField(
                controller: _body,
                minLines: 3,
                maxLines: 8,
                maxLength: 20000,
                decoration: InputDecoration(
                  labelText: context.tr('event_info.post_body', 'Announcement'),
                  hintText: context.tr('event_info.placeholder_body', 'Write an announcement for the team...'),
                  errorText: _error,
                ),
              ),
              const SizedBox(height: 8),
              Text(context.tr('event_info.attachments', 'Images and files'),
                  style: TextStyle(fontWeight: FontWeight.w600, color: ObsidianUITheme.getPrimaryTextColor(context))),
              for (final f in _existing)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(jsonBool(f['isImage']) ? Icons.image_rounded : Icons.insert_drive_file_rounded, color: secondary),
                  title: Text(jsonStr(f['fileName']), maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: IconButton(
                    tooltip: context.tr('event_info.remove', 'Remove'),
                    icon: Icon(Icons.delete_outline_rounded, color: ObsidianUITheme.errorRed),
                    onPressed: () => _removeExisting(f),
                  ),
                ),
              for (var i = 0; i < _pending.length; i++)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.attach_file_rounded, color: secondary),
                  title: Text(_pending[i].name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(_pending[i].originalSize != null
                      ? context.trArgs('event_info.compressed_from', '{size} (compressed from {original})',
                          {'size': fmtBytes(_pending[i].bytes.length), 'original': fmtBytes(_pending[i].originalSize!)})
                      : fmtBytes(_pending[i].bytes.length)),
                  trailing: IconButton(
                    tooltip: context.tr('event_info.remove', 'Remove'),
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => setState(() => _pending.removeAt(i)),
                  ),
                ),
              TextButton.icon(
                onPressed: _picking ? null : _pick,
                icon: _picking
                    ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.attach_file_rounded, size: 18),
                label: Text(context.tr('event_info.add_files', 'Add files')),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _pinned,
                title: Text(context.tr('event_info.pin', 'Pin to top')),
                onChanged: (v) => setState(() => _pinned = v ?? false),
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _allEvents,
                title: Text(context.tr('event_info.all_events', 'Show at every event (not just the current one)')),
                onChanged: (v) => setState(() => _allEvents = v ?? false),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(context.tr('common.cancel', 'Cancel'))),
        FilledButton(
          onPressed: _picking ? null : _submit,
          child: Text(widget.post == null ? context.tr('event_info.btn_post', 'Post') : context.tr('common.save', 'Save')),
        ),
      ],
    );
  }
}
