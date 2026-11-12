import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Renders an interactive 3D graph using the shared `obsidian_3d_graph.js` engine
/// inside an embedded WebView.
class Obsidian3DGraphView extends StatefulWidget {
  final String graphType;
  final List<Map<String, dynamic>> series;
  final String xLabel;
  final String yLabel;
  final String zLabel;
  final double height;

  const Obsidian3DGraphView({
    super.key,
    required this.graphType,
    required this.series,
    required this.xLabel,
    required this.yLabel,
    required this.zLabel,
    this.height = 420,
  });

  @override
  State<Obsidian3DGraphView> createState() => _Obsidian3DGraphViewState();
}

class _Obsidian3DGraphViewState extends State<Obsidian3DGraphView> {
  InAppWebViewController? _controller;
  bool _isLoaded = false;
  bool? _lastIsDark;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    if (_lastIsDark != null && _lastIsDark != isDark && _isLoaded) {
      _pushPayload();
    }
    _lastIsDark = isDark;
  }

  @override
  void didUpdateWidget(covariant Obsidian3DGraphView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isLoaded &&
        (oldWidget.graphType != widget.graphType ||
            oldWidget.xLabel != widget.xLabel ||
            oldWidget.yLabel != widget.yLabel ||
            oldWidget.zLabel != widget.zLabel ||
            oldWidget.series != widget.series)) {
      _pushPayload();
    }
  }

  String _buildPayloadJson(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final payload = {
      'graphType': widget.graphType,
      'series': widget.series,
      'xLabel': widget.xLabel,
      'yLabel': widget.yLabel,
      'zLabel': widget.zLabel,
      'theme': {
        'dark': isDark,
        'bg': isDark ? '#11161d' : '#ffffff',
        'text': isDark ? '#e7edf3' : '#1d1a17',
      },
    };
    return jsonEncode(payload);
  }

  Future<void> _pushPayload() async {
    final ctrl = _controller;
    if (ctrl == null || !mounted) return;
    final encoded = jsonEncode(_buildPayloadJson(context));
    await ctrl.evaluateJavascript(source: 'window.renderObsidian3D($encoded);');
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: InAppWebView(
          initialFile: 'assets/web/obsidian_3d_graph.html',
          initialSettings: InAppWebViewSettings(
            transparentBackground: true,
            disableVerticalScroll: true,
            disableHorizontalScroll: true,
            supportZoom: false,
            javaScriptEnabled: true,
            allowFileAccessFromFileURLs: true,
            allowUniversalAccessFromFileURLs: true,
          ),
          gestureRecognizers: {
            Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
          },
          onWebViewCreated: (controller) {
            _controller = controller;
          },
          onLoadStop: (controller, url) async {
            _isLoaded = true;
            await _pushPayload();
          },
        ),
      ),
    );
  }
}
