import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/obsidian_glass_card.dart';
import '../widgets/ported_page_kit.dart';
import '../widgets/simple_markdown.dart';

/// The docs library from the server (`/api/docs`), the same guides as the site's /docs page.
/// Docs are cached, so ones opened before stay readable offline.
class DocsScreen extends StatefulWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  /// Doc to open first, e.g. "GETTING_STARTED.md".
  final String? initialDoc;

  const DocsScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
    this.initialDoc,
  });

  @override
  State<DocsScreen> createState() => _DocsScreenState();
}

class _DocsScreenState extends State<DocsScreen> {
  List<Map<String, String>> _docs = [];
  bool _loadingList = true;
  String? _openFile;
  String? _content;
  bool _loadingDoc = false;
  final ScrollController _scroll = ScrollController();

  String get _lang {
    final code = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    return RegExp(r'^[a-z]{2}$').hasMatch(code) ? code : 'en';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadList());
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadList() async {
    setState(() => _loadingList = true);
    final docs = await widget.apiService.fetchDocsList(lang: _lang);
    if (!mounted) return;
    setState(() {
      _docs = docs;
      _loadingList = false;
    });
    if (widget.initialDoc != null && _openFile == null) _open(widget.initialDoc!);
  }

  Future<void> _open(String filename) async {
    setState(() {
      _openFile = filename;
      _content = null;
      _loadingDoc = true;
    });
    final content = await widget.apiService.fetchDoc(filename, lang: _lang);
    if (!mounted || _openFile != filename) return;
    setState(() {
      _content = content;
      _loadingDoc = false;
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  String _resolveImage(String src) {
    if (src.startsWith('http://') || src.startsWith('https://')) return src;
    final base = widget.apiService.currentServerUrl;
    final path = src.startsWith('/') ? src : '/$src';
    return '$base$path';
  }

  Future<void> _onLink(String href) async {
    // Another doc: "GETTING_STARTED.md", "docs/X.md", "X.md#section".
    final mdMatch = RegExp(r'([A-Za-z0-9_\-]+\.md)(#.*)?$').firstMatch(href);
    if (mdMatch != null && !href.startsWith('http')) {
      _open(mdMatch.group(1)!);
      return;
    }
    if (href.startsWith('#')) return; // in-page anchors aren't supported
    final uri = href.startsWith('http://') || href.startsWith('https://')
        ? Uri.tryParse(href)
        : Uri.tryParse(_resolveImage(href));
    if (uri == null) return;
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_openFile != null) return _buildDoc(context);
    return PortedPageList(
      onRefresh: _loadList,
      isBarsVisible: widget.isBarsVisible,
      children: [
        const PortedSection(
          title: 'Docs',
          subtitle: 'Guides for every part of ObsidianScout, from the server you are signed in to.',
        ),
        if (_loadingList)
          const PortedLoading()
        else if (_docs.isEmpty)
          const PortedNotice("Couldn't load the docs. Connect to the server and pull to refresh.", icon: Icons.cloud_off_rounded)
        else
          for (final d in _docs)
            ObsidianGlassCard(
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              onTap: () => _open(d['filename']!),
              child: Row(
                children: [
                  Icon(Icons.description_outlined, color: ObsidianUITheme.primaryAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      d['title']!,
                      style: TextStyle(fontWeight: FontWeight.w600, color: ObsidianUITheme.getPrimaryTextColor(context)),
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: ObsidianUITheme.getSecondaryTextColor(context)),
                ],
              ),
            ),
      ],
    );
  }

  Widget _buildDoc(BuildContext context) {
    final title = _docs.firstWhere((d) => d['filename'] == _openFile, orElse: () => {'title': _openFile!})['title']!;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 16, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'All docs',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _openFile = null;
                  _content = null;
                }),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: ObsidianUITheme.getPrimaryTextColor(context)),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingDoc
              ? const PortedLoading()
              : _content == null
                  ? Center(
                      child: PortedError(message: "Couldn't load this doc.", onRetry: () => _open(_openFile!)),
                    )
                  : SingleChildScrollView(
                      controller: _scroll,
                      padding: EdgeInsets.fromLTRB(16, 8, 16, widget.isBarsVisible ? 96 : 24),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 860),
                          child: SimpleMarkdown(data: _content!, resolveImage: _resolveImage, onLink: _onLink),
                        ),
                      ),
                    ),
        ),
      ],
    );
  }
}
