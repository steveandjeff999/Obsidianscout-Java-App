import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// A secure rich-text widget that safely parses and renders a restricted subset of
/// HTML and Markdown formatting (bold, italic, underline, strikethrough, code, links, line breaks).
///
/// Disallowed tags (<script>, <iframe>, <style>, etc.) and non-http(s) link schemes
/// (javascript:, file:, data:) are strictly stripped or neutralized to eliminate XSS risks.
class SanitizedBannerText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Color? linkColor;
  final int? maxLines;
  final TextOverflow? overflow;
  final TextAlign textAlign;

  const SanitizedBannerText({
    super.key,
    required this.text,
    this.style,
    this.linkColor,
    this.maxLines,
    this.overflow,
    this.textAlign = TextAlign.start,
  });

  @override
  State<SanitizedBannerText> createState() => _SanitizedBannerTextState();
}

class _SanitizedBannerTextState extends State<SanitizedBannerText> {
  final List<TapGestureRecognizer> _recognizers = [];
  late List<InlineSpan> _spans;

  @override
  void initState() {
    super.initState();
    _rebuildSpans();
  }

  @override
  void didUpdateWidget(covariant SanitizedBannerText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.linkColor != widget.linkColor) {
      _disposeRecognizers();
      _rebuildSpans();
    }
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  void _rebuildSpans() {
    _spans = _parseSanitizedText(
      widget.text,
      widget.style ?? const TextStyle(),
      widget.linkColor ?? Colors.lightBlueAccent,
    );
  }

  static final RegExp _dangerousTagBlockRegex = RegExp(
    r'<\s*(script|style|iframe|object|embed|svg|math|form|meta|link)[^>]*>[\s\S]*?<\s*/\s*\1\s*>',
    caseSensitive: false,
  );

  static final RegExp _dangerousSelfClosingRegex = RegExp(
    r'<\s*(script|style|iframe|object|embed|svg|math|form|meta|link)[^>]*?/?>',
    caseSensitive: false,
  );

  static final RegExp _paragraphRegex = RegExp(r'</?p[^>]*>', caseSensitive: false);
  static final RegExp _brRegex = RegExp(r'<br\s*/?>', caseSensitive: false);

  String _preprocessText(String raw) {
    var text = raw;
    // Strip dangerous blocks entirely (including content)
    text = text.replaceAll(_dangerousTagBlockRegex, '');
    text = text.replaceAll(_dangerousSelfClosingRegex, '');

    // Convert paragraph tags to linebreaks
    text = text.replaceAll(_paragraphRegex, '\n');
    // Convert br tags to linebreaks
    text = text.replaceAll(_brRegex, '\n');

    return text;
  }

  static String decodeHtmlEntities(String text) {
    return text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&nbsp;', ' ');
  }

  static bool _isSafeUrl(String url) {
    final trimmed = url.trim();
    final lower = trimmed.toLowerCase();
    if (lower.startsWith('javascript:') ||
        lower.startsWith('data:') ||
        lower.startsWith('file:') ||
        lower.startsWith('vbscript:')) {
      return false;
    }
    final uri = Uri.tryParse(trimmed);
    if (uri == null) return false;
    return uri.scheme == 'http' || uri.scheme == 'https' || uri.scheme == 'mailto';
  }

  List<InlineSpan> _parseSanitizedText(
    String raw,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    if (raw.trim().isEmpty) {
      return [TextSpan(text: '', style: baseStyle)];
    }

    final cleaned = _preprocessText(raw);
    final spans = <InlineSpan>[];

    // Pattern to identify formatting tokens:
    // 1) HTML links: <a\s+[^>]*href=["']?([^"'>]+)["']?[^>]*>(.*?)</a>
    // 2) Markdown links: \[(.*?)\]\((.*?)\)
    // 3) HTML tags: <(b|strong|i|em|u|s|strike|del|code)>(.*?)</\1>
    // 4) Markdown bold: \*\*(.*?)\*\*
    // 5) Markdown italic: \*(.*?)\*
    // 6) Markdown strikethrough: ~~(.*?)~~
    // 7) Markdown code: `(.*?)`
    // 8) Any generic residual HTML tag: <[^>]+>
    final tokenPattern = RegExp(
      r'(?:<a\s+[^>]*href=["' "'" r']?([^"' "'" r'>\s]+)["' "'" r']?[^>]*>(.*?)</a>)|' // Group 1, 2
      r'(?:\[(.*?)\]\((.*?)\))|' // Group 3, 4
      r'(?:<(b|strong|i|em|u|s|strike|del|code)>(.*?)</\5>)|' // Group 5, 6
      r'(?:\*\*(.*?)\*\*)|' // Group 7
      r'(?:\*(.*?)\*)|' // Group 8
      r'(?:~~(.*?)~~)|' // Group 9
      r'(?:`([^`]+)`)|' // Group 10
      r'(?:<[^>]+>)', // Fallback tag match to strip
      caseSensitive: false,
    );

    int lastIndex = 0;
    for (final match in tokenPattern.allMatches(cleaned)) {
      if (match.start > lastIndex) {
        final textBefore = cleaned.substring(lastIndex, match.start);
        if (textBefore.isNotEmpty) {
          spans.add(TextSpan(
            text: decodeHtmlEntities(textBefore),
            style: baseStyle,
          ));
        }
      }

      // Check which token group matched
      final htmlLinkUrl = match.group(1);
      final htmlLinkText = match.group(2);
      final mdLinkText = match.group(3);
      final mdLinkUrl = match.group(4);
      final htmlTag = match.group(5)?.toLowerCase();
      final htmlTagContent = match.group(6);
      final mdBold = match.group(7);
      final mdItalic = match.group(8);
      final mdStrike = match.group(9);
      final mdCode = match.group(10);

      if (htmlLinkUrl != null && htmlLinkText != null) {
        spans.add(_buildLinkSpan(htmlLinkText, htmlLinkUrl, baseStyle, linkColor));
      } else if (mdLinkText != null && mdLinkUrl != null) {
        spans.add(_buildLinkSpan(mdLinkText, mdLinkUrl, baseStyle, linkColor));
      } else if (htmlTag != null && htmlTagContent != null) {
        TextStyle tagStyle = baseStyle;
        switch (htmlTag) {
          case 'b':
          case 'strong':
            tagStyle = baseStyle.copyWith(fontWeight: FontWeight.bold);
            break;
          case 'i':
          case 'em':
            tagStyle = baseStyle.copyWith(fontStyle: FontStyle.italic);
            break;
          case 'u':
            tagStyle = baseStyle.copyWith(decoration: TextDecoration.underline);
            break;
          case 's':
          case 'strike':
          case 'del':
            tagStyle = baseStyle.copyWith(decoration: TextDecoration.lineThrough);
            break;
          case 'code':
            tagStyle = baseStyle.copyWith(
              fontFamily: 'monospace',
              backgroundColor: baseStyle.color?.withValues(alpha: 0.12) ?? Colors.white12,
            );
            break;
        }
        spans.add(TextSpan(
          text: decodeHtmlEntities(htmlTagContent),
          style: tagStyle,
        ));
      } else if (mdBold != null) {
        spans.add(TextSpan(
          text: decodeHtmlEntities(mdBold),
          style: baseStyle.copyWith(fontWeight: FontWeight.bold),
        ));
      } else if (mdItalic != null) {
        spans.add(TextSpan(
          text: decodeHtmlEntities(mdItalic),
          style: baseStyle.copyWith(fontStyle: FontStyle.italic),
        ));
      } else if (mdStrike != null) {
        spans.add(TextSpan(
          text: decodeHtmlEntities(mdStrike),
          style: baseStyle.copyWith(decoration: TextDecoration.lineThrough),
        ));
      } else if (mdCode != null) {
        spans.add(TextSpan(
          text: decodeHtmlEntities(mdCode),
          style: baseStyle.copyWith(
            fontFamily: 'monospace',
            backgroundColor: baseStyle.color?.withValues(alpha: 0.12) ?? Colors.white12,
          ),
        ));
      }
      // Any remaining tags without groups (e.g. residual <span class="...">) are simply stripped.

      lastIndex = match.end;
    }

    if (lastIndex < cleaned.length) {
      final trailing = cleaned.substring(lastIndex);
      if (trailing.isNotEmpty) {
        spans.add(TextSpan(
          text: decodeHtmlEntities(trailing),
          style: baseStyle,
        ));
      }
    }

    if (spans.isEmpty) {
      spans.add(TextSpan(text: '', style: baseStyle));
    }

    return spans;
  }

  InlineSpan _buildLinkSpan(
    String linkText,
    String linkUrl,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    final displayText = decodeHtmlEntities(linkText.trim().isEmpty ? linkUrl : linkText);
    final isSafe = _isSafeUrl(linkUrl);

    if (!isSafe) {
      // Disallowed URL scheme (e.g. javascript:), render text without interactive link
      return TextSpan(
        text: displayText,
        style: baseStyle,
      );
    }

    final recognizer = TapGestureRecognizer()
      ..onTap = () async {
        final uri = Uri.tryParse(linkUrl.trim());
        if (uri != null) {
          try {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          } catch (_) {
            // Ignored launch error
          }
        }
      };
    _recognizers.add(recognizer);

    return TextSpan(
      text: displayText,
      style: baseStyle.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor,
        fontWeight: FontWeight.w600,
      ),
      recognizer: recognizer,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: _spans),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      textAlign: widget.textAlign,
    );
  }
}
