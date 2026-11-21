import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../theme/obsidian_ui_theme.dart';
import 'cached_server_image.dart';

/// A small Markdown renderer for the docs library: headings, paragraphs, bullet and
/// numbered lists, block quotes, fenced code, tables, rules, images and inline
/// bold / italic / code / links. It covers what the project's docs use; anything
/// else is shown as plain text.
class SimpleMarkdown extends StatelessWidget {
  final String data;

  /// Turns a relative image path (e.g. `/assets/images/docs/x.webp`) into a full URL.
  final String Function(String src) resolveImage;

  /// Called for every link tap with the raw href.
  final void Function(String href) onLink;

  const SimpleMarkdown({super.key, required this.data, required this.resolveImage, required this.onLink});

  @override
  Widget build(BuildContext context) {
    final blocks = _parse(data);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final b in blocks) _buildBlock(context, b)],
    );
  }

  // ── Block parsing ──────────────────────────────────────────

  static final _heading = RegExp(r'^(#{1,6})\s+(.*)$');
  static final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
  static final _numbered = RegExp(r'^(\s*)(\d+)[.)]\s+(.*)$');
  static final _image = RegExp(r'^!\[([^\]]*)\]\(([^)\s]+)(?:\s+"[^"]*")?\)\s*$');
  static final _rule = RegExp(r'^\s*([-*_])(\s*\1){2,}\s*$');
  static final _tableSep = RegExp(r'^\s*\|?\s*:?-{2,}:?\s*(\|\s*:?-{2,}:?\s*)*\|?\s*$');

  List<_Block> _parse(String src) {
    final lines = src.replaceAll('\r\n', '\n').split('\n');
    final out = <_Block>[];
    var i = 0;
    final para = <String>[];
    void flushPara() {
      if (para.isNotEmpty) {
        out.add(_Block('p', text: para.join(' ')));
        para.clear();
      }
    }

    while (i < lines.length) {
      final line = lines[i];
      final trimmed = line.trim();

      if (trimmed.startsWith('```')) {
        flushPara();
        final code = <String>[];
        i++;
        while (i < lines.length && !lines[i].trim().startsWith('```')) {
          code.add(lines[i]);
          i++;
        }
        i++; // closing fence
        out.add(_Block('code', text: code.join('\n')));
        continue;
      }
      if (trimmed.isEmpty) {
        flushPara();
        i++;
        continue;
      }
      final h = _heading.firstMatch(trimmed);
      if (h != null) {
        flushPara();
        out.add(_Block('h', text: h.group(2)!.trim(), level: h.group(1)!.length));
        i++;
        continue;
      }
      if (_rule.hasMatch(trimmed)) {
        flushPara();
        out.add(_Block('hr'));
        i++;
        continue;
      }
      final img = _image.firstMatch(trimmed);
      if (img != null) {
        flushPara();
        out.add(_Block('img', text: img.group(1)!, src: img.group(2)!));
        i++;
        continue;
      }
      if (trimmed.startsWith('>')) {
        flushPara();
        final quote = <String>[];
        while (i < lines.length && lines[i].trim().startsWith('>')) {
          quote.add(lines[i].trim().replaceFirst(RegExp(r'^>\s?'), ''));
          i++;
        }
        out.add(_Block('quote', text: quote.join(' ')));
        continue;
      }
      if (trimmed.startsWith('|') && i + 1 < lines.length && _tableSep.hasMatch(lines[i + 1])) {
        flushPara();
        final rows = <List<String>>[_cells(trimmed)];
        i += 2;
        while (i < lines.length && lines[i].trim().startsWith('|')) {
          rows.add(_cells(lines[i].trim()));
          i++;
        }
        out.add(_Block('table', rows: rows));
        continue;
      }
      final b = _bullet.firstMatch(line);
      final n = _numbered.firstMatch(line);
      if (b != null || n != null) {
        flushPara();
        final items = <_ListItem>[];
        while (i < lines.length) {
          final l = lines[i];
          final bm = _bullet.firstMatch(l);
          final nm = _numbered.firstMatch(l);
          if (bm != null) {
            items.add(_ListItem(bm.group(2)!, (bm.group(1)!.length ~/ 2), null));
          } else if (nm != null) {
            items.add(_ListItem(nm.group(3)!, (nm.group(1)!.length ~/ 2), nm.group(2)));
          } else if (l.trim().isNotEmpty && l.startsWith('  ') && items.isNotEmpty) {
            final last = items.removeLast();
            items.add(_ListItem('${last.text} ${l.trim()}', last.depth, last.number));
          } else {
            break;
          }
          i++;
        }
        out.add(_Block('list', items: items));
        continue;
      }
      para.add(trimmed);
      i++;
    }
    flushPara();
    return out;
  }

  static List<String> _cells(String row) {
    var r = row.trim();
    if (r.startsWith('|')) r = r.substring(1);
    if (r.endsWith('|')) r = r.substring(0, r.length - 1);
    return r.split('|').map((c) => c.trim()).toList();
  }

  // ── Rendering ──────────────────────────────────────────────

  Widget _buildBlock(BuildContext context, _Block b) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    final border = ObsidianUITheme.getBorderColor(context);
    final base = TextStyle(fontSize: 14.5, height: 1.5, color: primary);

    switch (b.kind) {
      case 'h':
        const sizes = [24.0, 20.0, 17.0, 15.5, 14.5, 14.0];
        return Padding(
          padding: EdgeInsets.only(top: b.level <= 2 ? 18 : 12, bottom: 6),
          child: Text.rich(
            _inline(context, b.text, base.copyWith(fontSize: sizes[b.level - 1], fontWeight: FontWeight.w800, height: 1.25)),
          ),
        );
      case 'p':
        return Padding(padding: const EdgeInsets.only(bottom: 10), child: Text.rich(_inline(context, b.text, base)));
      case 'quote':
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: ObsidianUITheme.primaryAccent, width: 3)),
            color: ObsidianUITheme.primaryAccent.withValues(alpha: 0.06),
          ),
          child: Text.rich(_inline(context, b.text, base.copyWith(color: muted))),
        );
      case 'code':
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: border.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(8),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Text(b.text, style: base.copyWith(fontFamily: 'monospace', fontSize: 13)),
          ),
        );
      case 'hr':
        return Divider(height: 24, color: border);
      case 'img':
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: CachedServerImage(
              url: resolveImage(b.src),
              fit: BoxFit.contain,
              errorBuilder: (_) => Text(b.text, style: base.copyWith(color: muted, fontStyle: FontStyle.italic)),
            ),
          ),
        );
      case 'list':
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in b.items)
                Padding(
                  padding: EdgeInsets.only(left: 6.0 + item.depth * 18, bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 22,
                        child: Text(item.number != null ? '${item.number}.' : '•', style: base.copyWith(color: muted)),
                      ),
                      Expanded(child: Text.rich(_inline(context, item.text, base))),
                    ],
                  ),
                ),
            ],
          ),
        );
      case 'table':
        final header = b.rows.first;
        final cols = header.length;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(),
              border: TableBorder.all(color: border),
              children: [
                for (var r = 0; r < b.rows.length; r++)
                  TableRow(
                    decoration: r == 0 ? BoxDecoration(color: border.withValues(alpha: 0.25)) : null,
                    children: [
                      for (var c = 0; c < cols; c++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 320),
                            child: Text.rich(_inline(
                              context,
                              c < b.rows[r].length ? b.rows[r][c] : '',
                              base.copyWith(fontSize: 13, fontWeight: r == 0 ? FontWeight.w700 : null),
                            )),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        );
    }
    return const SizedBox.shrink();
  }

  // ── Inline: **bold**, *italic* / _italic_, `code`, [link](href) ──

  static final _inlineToken = RegExp(r'(\*\*[^*]+\*\*)|(`[^`]+`)|(\[[^\]]+\]\([^)\s]+\))|(\*[^*\s][^*]*\*)|((?<![A-Za-z0-9])_[^_\s][^_]*_(?![A-Za-z0-9]))');

  InlineSpan _inline(BuildContext context, String text, TextStyle style) {
    final spans = <InlineSpan>[];
    var pos = 0;
    for (final m in _inlineToken.allMatches(text)) {
      if (m.start > pos) spans.add(TextSpan(text: text.substring(pos, m.start)));
      final tok = m.group(0)!;
      if (tok.startsWith('**')) {
        spans.add(TextSpan(
          children: [_inline(context, tok.substring(2, tok.length - 2), style)],
          style: const TextStyle(fontWeight: FontWeight.w700),
        ));
      } else if (tok.startsWith('`')) {
        spans.add(TextSpan(
          text: tok.substring(1, tok.length - 1),
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: (style.fontSize ?? 14) - 1,
            backgroundColor: ObsidianUITheme.getBorderColor(context).withValues(alpha: 0.35),
          ),
        ));
      } else if (tok.startsWith('[')) {
        final close = tok.indexOf('](');
        final label = tok.substring(1, close);
        final href = tok.substring(close + 2, tok.length - 1);
        spans.add(TextSpan(
          text: label,
          style: TextStyle(color: ObsidianUITheme.primaryAccent, decoration: TextDecoration.underline),
          recognizer: TapGestureRecognizer()..onTap = () => onLink(href),
        ));
      } else {
        spans.add(TextSpan(text: tok.substring(1, tok.length - 1), style: const TextStyle(fontStyle: FontStyle.italic)));
      }
      pos = m.end;
    }
    if (pos < text.length) spans.add(TextSpan(text: text.substring(pos)));
    return TextSpan(style: style, children: spans);
  }
}

class _Block {
  final String kind;
  final String text;
  final int level;
  final String src;
  final List<_ListItem> items;
  final List<List<String>> rows;

  _Block(this.kind, {this.text = '', this.level = 1, this.src = '', this.items = const [], this.rows = const []});
}

class _ListItem {
  final String text;
  final int depth;
  final String? number;

  _ListItem(this.text, this.depth, this.number);
}
