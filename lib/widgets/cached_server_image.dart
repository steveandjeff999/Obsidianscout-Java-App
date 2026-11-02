import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/net/server_file_cache.dart';

/// An image that shows the copy on this device straight away, then swaps in a newer one if the server has it.
/// On the web the browser's own HTTP cache does this job.
class CachedServerImage extends StatefulWidget {
  final String url;
  final Map<String, String>? webHeaders;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final WidgetBuilder? errorBuilder;

  const CachedServerImage({
    super.key,
    required this.url,
    this.webHeaders,
    this.width,
    this.height,
    this.fit,
    this.errorBuilder,
  });

  @override
  State<CachedServerImage> createState() => _CachedServerImageState();
}

class _CachedServerImageState extends State<CachedServerImage> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb) _load();
  }

  @override
  void didUpdateWidget(covariant CachedServerImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!kIsWeb && oldWidget.url != widget.url) {
      _bytes = null;
      _failed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final url = widget.url;
    final cache = ServerFileCache.instance;
    final stored = await cache.stored(url);
    if (!mounted || url != widget.url) return;
    if (stored != null) setState(() => _bytes = stored);

    final fresh = await cache.refresh(url);
    if (!mounted || url != widget.url) return;
    if (fresh != null) {
      setState(() => _bytes = fresh);
    } else if (_bytes == null) {
      setState(() => _failed = true);
    }
  }

  Widget _error(BuildContext context) =>
      widget.errorBuilder?.call(context) ??
      SizedBox(width: widget.width, height: widget.height);

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        widget.url,
        headers: widget.webHeaders,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (context, _, __) => _error(context),
      );
    }
    final bytes = _bytes;
    if (bytes != null) {
      return Image.memory(
        bytes,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        gaplessPlayback: true,
        errorBuilder: (context, _, __) => _error(context),
      );
    }
    if (_failed) return _error(context);
    return SizedBox(width: widget.width, height: widget.height);
  }
}
