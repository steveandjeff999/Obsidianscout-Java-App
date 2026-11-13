import 'dart:convert';
import 'dart:io' show Platform;
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_windows/webview_windows.dart' as win_wv;

/// Renders an interactive 3D graph using the shared `obsidian_3d_graph.js` engine
/// via `webview_flutter` (Android/iOS/macOS), `webview_windows` (Windows),
/// or a pure-Flutter 3D CustomPainter fallback (Linux/Web).
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
  WebViewController? _mobileController;
  win_wv.WebviewController? _winController;
  bool _isLoaded = false;
  bool? _lastIsDark;

  bool get _useWindowsWebView => !kIsWeb && Platform.isWindows;
  bool get _useMobileWebView =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS || Platform.isMacOS);

  @override
  void initState() {
    super.initState();
    _initRenderer();
  }

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

  @override
  void dispose() {
    _winController?.dispose();
    super.dispose();
  }

  Future<String> _buildHostHtml() async {
    final js = await rootBundle.loadString('assets/web/obsidian_3d_graph.js');
    return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no" />
  <style>
    html, body, #viewport {
      margin: 0; padding: 0; width: 100%; height: 100%;
      overflow: hidden; background: transparent;
      font-family: system-ui, -apple-system, sans-serif;
    }
  </style>
</head>
<body>
  <div id="viewport"></div>
  <script>$js</script>
  <script>
    window.__obsidian3DPending = null;
    window.renderObsidian3D = function (payload) {
      try {
        var config = typeof payload === "string" ? JSON.parse(payload) : payload;
        if (window.Obsidian3DGraph) {
          window.Obsidian3DGraph.render(document.getElementById("viewport"), config);
        } else {
          window.__obsidian3DPending = config;
        }
      } catch (e) {
        console.error("renderObsidian3D error:", e);
      }
    };
  </script>
</body>
</html>
''';
  }

  Future<void> _initRenderer() async {
    if (_useWindowsWebView) {
      try {
        final ctrl = win_wv.WebviewController();
        await ctrl.initialize();
        final html = await _buildHostHtml();
        await ctrl.loadStringContent(html);
        if (!mounted) {
          ctrl.dispose();
          return;
        }
        setState(() {
          _winController = ctrl;
          _isLoaded = true;
        });
        await _pushPayload();
      } catch (e) {
        debugPrint('Windows 3D WebView init error: $e');
      }
      return;
    }

    if (_useMobileWebView) {
      final ctrl = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(Colors.transparent)
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (_) async {
              _isLoaded = true;
              await _pushPayload();
            },
          ),
        );
      final html = await _buildHostHtml();
      await ctrl.loadHtmlString(html);
      if (!mounted) return;
      setState(() {
        _mobileController = ctrl;
      });
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
    if (!mounted) return;
    final encoded = jsonEncode(_buildPayloadJson(context));
    final script = 'window.renderObsidian3D($encoded);';
    if (_useWindowsWebView && _winController != null) {
      await _winController!.executeScript(script);
    } else if (_useMobileWebView && _mobileController != null) {
      await _mobileController!.runJavaScript(script);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_useWindowsWebView) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _winController == null
              ? const Center(child: CircularProgressIndicator())
              : win_wv.Webview(_winController!),
        ),
      );
    }

    if (_useMobileWebView) {
      return SizedBox(
        height: widget.height,
        width: double.infinity,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: _mobileController == null
              ? const Center(child: CircularProgressIndicator())
              : WebViewWidget(
                  controller: _mobileController!,
                  gestureRecognizers: {
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                ),
        ),
      );
    }

    // Linux / Web fallback: pure Flutter 3D viewport
    return _Fallback3DViewport(
      series: widget.series,
      xLabel: widget.xLabel,
      yLabel: widget.yLabel,
      zLabel: widget.zLabel,
      height: widget.height,
    );
  }
}

class _Fallback3DViewport extends StatefulWidget {
  final List<Map<String, dynamic>> series;
  final String xLabel;
  final String yLabel;
  final String zLabel;
  final double height;

  const _Fallback3DViewport({
    required this.series,
    required this.xLabel,
    required this.yLabel,
    required this.zLabel,
    required this.height,
  });

  @override
  State<_Fallback3DViewport> createState() => _Fallback3DViewportState();
}

class _Fallback3DViewportState extends State<_Fallback3DViewport> {
  double _yaw = -0.68;
  double _pitch = 0.42;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: widget.height,
      width: double.infinity,
      child: GestureDetector(
        onPanUpdate: (d) {
          setState(() {
            _yaw += d.delta.dx * 0.01;
            _pitch = (_pitch + d.delta.dy * 0.01).clamp(-1.4, 1.4);
          });
        },
        child: CustomPaint(
          painter: _Fallback3DPainter(
            series: widget.series,
            yaw: _yaw,
            pitch: _pitch,
            isDark: isDark,
          ),
        ),
      ),
    );
  }
}

class _Fallback3DPainter extends CustomPainter {
  final List<Map<String, dynamic>> series;
  final double yaw;
  final double pitch;
  final bool isDark;

  _Fallback3DPainter({
    required this.series,
    required this.yaw,
    required this.pitch,
    required this.isDark,
  });

  static const _fallbackPalette = <Color>[
    Color(0xFF0B8F88),
    Color(0xFF255A9C),
    Color(0xFFD97706),
    Color(0xFFDC2626),
    Color(0xFF7C3AED),
    Color(0xFF059669),
    Color(0xFFDB2777),
    Color(0xFF0284C7),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final pts = <({double x, double y, double z, String label, Color color})>[];
    for (int sIdx = 0; sIdx < series.length; sIdx++) {
      final s = series[sIdx];
      final pointsList = s['points'] as List<dynamic>? ?? [];
      for (int pIdx = 0; pIdx < pointsList.length; pIdx++) {
        final p = pointsList[pIdx];
        if (p is Map) {
          final colorIdx = series.length == 1 ? pIdx : sIdx;
          pts.add((
            x: ((p['x'] as num?) ?? 0).toDouble(),
            y: ((p['y'] as num?) ?? 0).toDouble(),
            z: ((p['z'] as num?) ?? 0).toDouble(),
            label: (p['label'] ?? '').toString(),
            color: _fallbackPalette[colorIdx % _fallbackPalette.length],
          ));
        }
      }
    }
    if (pts.isEmpty) return;

    double minX = pts.first.x, maxX = pts.first.x;
    double minY = pts.first.y, maxY = pts.first.y;
    double minZ = pts.first.z, maxZ = pts.first.z;
    for (final p in pts) {
      if (p.x < minX) minX = p.x;
      if (p.x > maxX) maxX = p.x;
      if (p.y < minY) minY = p.y;
      if (p.y > maxY) maxY = p.y;
      if (p.z < minZ) minZ = p.z;
      if (p.z > maxZ) maxZ = p.z;
    }

    Offset project(double nx, double ny, double nz) {
      final rx = nx * math.cos(yaw) - ny * math.sin(yaw);
      final ry = nx * math.sin(yaw) + ny * math.cos(yaw);
      final rz2 = ry * math.sin(pitch) + nz * math.cos(pitch);
      final scale = math.min(size.width, size.height) * 0.34;
      return Offset(size.width * 0.5 + rx * scale, size.height * 0.52 - rz2 * scale);
    }

    final textColor = isDark ? Colors.white : Colors.black87;
    for (final p in pts) {
      final nx = ((p.x - minX) / ((maxX - minX) == 0 ? 1 : (maxX - minX))) * 2 - 1;
      final ny = ((p.y - minY) / ((maxY - minY) == 0 ? 1 : (maxY - minY))) * 2 - 1;
      final nz = ((p.z - minZ) / ((maxZ - minZ) == 0 ? 1 : (maxZ - minZ))) * 2 - 1;
      final o = project(nx, ny, nz);
      canvas.drawCircle(o, 5, Paint()..color = p.color);
      if (p.label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(text: p.label, style: TextStyle(color: textColor, fontSize: 10)),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, o + const Offset(7, -6));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _Fallback3DPainter old) =>
      old.yaw != yaw || old.pitch != pitch || old.series != series || old.isDark != isDark;
}
