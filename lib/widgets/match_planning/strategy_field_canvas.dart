import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../models/match_planning_models.dart';
import '../../models/team_match_models.dart';
import 'draggable_team_marker.dart';

class StrategyFieldCanvas extends StatefulWidget {
  final GlobalKey repaintBoundaryKey;
  final MatchPlanModel plan;
  final String activeTool; // 'pen' | 'eraser'
  final String currentColor;
  final double strokeWidth;
  final ui.Image? fieldImage;
  final MatchModel? currentMatch;
  final Map<int, TeamModel> teamMap;
  final ValueChanged<StrokeAnnotation> onStrokeCompleted;
  final Function(String stationId, TeamMarkerPosition pos) onMarkerPositionChanged;
  final VoidCallback onMarkerDragEnd;

  const StrategyFieldCanvas({
    super.key,
    required this.repaintBoundaryKey,
    required this.plan,
    required this.activeTool,
    required this.currentColor,
    required this.strokeWidth,
    required this.fieldImage,
    required this.currentMatch,
    this.teamMap = const {},
    required this.onStrokeCompleted,
    required this.onMarkerPositionChanged,
    required this.onMarkerDragEnd,
  });

  @override
  State<StrategyFieldCanvas> createState() => _StrategyFieldCanvasState();
}

class _StrategyFieldCanvasState extends State<StrategyFieldCanvas> {
  StrokeAnnotation? _currentStroke;
  String? _draggingStationId;

  void _handlePanStart(DragStartDetails details, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final xRatio = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
    final yRatio = (details.localPosition.dy / size.height).clamp(0.0, 1.0);

    final widthRatio = (widget.activeTool == 'eraser'
            ? widget.strokeWidth * 3.5
            : widget.strokeWidth) /
        1000.0;

    setState(() {
      _currentStroke = StrokeAnnotation(
        tool: widget.activeTool,
        color: widget.currentColor,
        widthRatio: widthRatio,
        points: [StrokePoint(xRatio, yRatio)],
      );
    });
  }

  void _handlePanUpdate(DragUpdateDetails details, Size size) {
    if (_currentStroke == null || size.width <= 0 || size.height <= 0) return;

    final xRatio = (details.localPosition.dx / size.width).clamp(0.0, 1.0);
    final yRatio = (details.localPosition.dy / size.height).clamp(0.0, 1.0);

    setState(() {
      _currentStroke!.points.add(StrokePoint(xRatio, yRatio));
    });
  }

  void _handlePanEnd(DragEndDetails details) {
    if (_currentStroke != null) {
      final finished = _currentStroke!;
      _currentStroke = null;
      widget.onStrokeCompleted(finished);
    }
  }

  int _parseTeamNumber(dynamic raw) {
    if (raw == null) return 0;
    final str = raw.toString().replaceAll(RegExp(r'^(frc|ftc)', caseSensitive: false), '').trim();
    return int.tryParse(str) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        // Default aspect ratio: 2.0 (length : width of FRC field, e.g. 54'x26')
        double fieldAspect = 2.0;
        if (widget.fieldImage != null && widget.fieldImage!.width > 0) {
          fieldAspect = widget.fieldImage!.width / widget.fieldImage!.height;
        }

        double canvasWidth = availableWidth;
        double canvasHeight = canvasWidth / fieldAspect;

        if (constraints.maxHeight.isFinite && canvasHeight > constraints.maxHeight) {
          canvasHeight = constraints.maxHeight;
          canvasWidth = canvasHeight * fieldAspect;
        } else if (!constraints.maxHeight.isFinite) {
          canvasHeight = (canvasWidth / fieldAspect).clamp(100.0, 750.0);
        }

        final canvasSize = Size(canvasWidth, canvasHeight);

        return RepaintBoundary(
          key: widget.repaintBoundaryKey,
          child: Container(
            width: canvasWidth,
            height: canvasHeight,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black54,
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                children: [
                  // 1. Field Background & User Annotations Drawing Layer
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: (d) => _handlePanStart(d, canvasSize),
                    onPanUpdate: (d) => _handlePanUpdate(d, canvasSize),
                    onPanEnd: _handlePanEnd,
                    child: CustomPaint(
                      size: canvasSize,
                      painter: _FieldStrategyPainter(
                        plan: widget.plan,
                        currentStroke: _currentStroke,
                        fieldImage: widget.fieldImage,
                      ),
                    ),
                  ),

                  // 2. Draggable Square Robot Team Markers
                  if (widget.currentMatch != null) ..._buildTeamMarkers(canvasWidth, canvasHeight),

                  // 3. Placeholder Empty State when no match loaded
                  if (widget.currentMatch == null)
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xCC0F172A),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.dashboard_customize_rounded, color: Color(0xFF94A3B8), size: 24),
                            SizedBox(width: 10),
                            Text(
                              'Select a match above to load field and driver stations',
                              style: TextStyle(
                                color: Color(0xFFCBD5E1),
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildTeamMarkers(double canvasWidth, double canvasHeight) {
    final match = widget.currentMatch;
    if (match == null) return [];

    final blueTeams = match.blueTeams;
    final redTeams = match.redTeams;

    final markers = <Widget>[];

    final stationConfigs = [
      {'id': 'b1', 'label': 'B1', 'alliance': 'blue', 'teams': blueTeams, 'idx': 0},
      {'id': 'b2', 'label': 'B2', 'alliance': 'blue', 'teams': blueTeams, 'idx': 1},
      {'id': 'b3', 'label': 'B3', 'alliance': 'blue', 'teams': blueTeams, 'idx': 2},
      {'id': 'r1', 'label': 'R1', 'alliance': 'red', 'teams': redTeams, 'idx': 0},
      {'id': 'r2', 'label': 'R2', 'alliance': 'red', 'teams': redTeams, 'idx': 1},
      {'id': 'r3', 'label': 'R3', 'alliance': 'red', 'teams': redTeams, 'idx': 2},
    ];

    for (final cfg in stationConfigs) {
      final stId = cfg['id'] as String;
      final stLabel = cfg['label'] as String;
      final alliance = cfg['alliance'] as String;
      final teamsList = cfg['teams'] as List<String>;
      final idx = cfg['idx'] as int;

      if (idx < teamsList.length) {
        final teamNum = _parseTeamNumber(teamsList[idx]);
        if (teamNum > 0) {
          final pos = widget.plan.teamMarkerPositions[stId] ??
              MatchPlanModel.defaultMarkerPositions()[stId] ??
              const TeamMarkerPosition(xRatio: 0.5, yRatio: 0.5);

          markers.add(
            DraggableTeamMarkerWidget(
              stationId: stId,
              stationLabel: stLabel,
              alliance: alliance,
              teamNumber: teamNum,
              position: pos,
              canvasWidth: canvasWidth,
              canvasHeight: canvasHeight,
              isDragging: _draggingStationId == stId,
              onPositionChanged: (newPos) {
                setState(() => _draggingStationId = stId);
                widget.onMarkerPositionChanged(stId, newPos);
              },
              onDragEnd: () {
                setState(() => _draggingStationId = null);
                widget.onMarkerDragEnd();
              },
            ),
          );
        }
      }
    }

    return markers;
  }
}

class _FieldStrategyPainter extends CustomPainter {
  final MatchPlanModel plan;
  final StrokeAnnotation? currentStroke;
  final ui.Image? fieldImage;

  _FieldStrategyPainter({
    required this.plan,
    required this.currentStroke,
    required this.fieldImage,
  });

  Color _parseColor(String hex) {
    String clean = hex.replaceAll('#', '').trim();
    if (clean.length == 6) clean = 'FF$clean';
    final val = int.tryParse(clean, radix: 16);
    return val != null ? Color(val) : Colors.white;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // 1. Paint Field Background or Gradient Fallback
    if (fieldImage != null) {
      final src = Rect.fromLTWH(0, 0, fieldImage!.width.toDouble(), fieldImage!.height.toDouble());
      canvas.drawImageRect(fieldImage!, src, rect, Paint()..filterQuality = FilterQuality.medium);
    } else {
      final gradient = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: const [
          Color(0xFF1E3A8A), // Blue side
          Color(0xFF1E293B), // Center field
          Color(0xFF7F1D1D), // Red side
        ],
        stops: const [0.0, 0.5, 1.0],
      );
      canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));

      // Field Center Dividing Line
      final centerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.2)
        ..strokeWidth = 2;
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height), centerPaint);
    }

    // 2. Replay User Annotations in an isolated Layer (Eraser uses BlendMode.clear without erasing background)
    canvas.saveLayer(rect, Paint());

    final allStrokes = <StrokeAnnotation>[
      ...plan.annotations,
      if (currentStroke != null) currentStroke!,
    ];

    for (final stroke in allStrokes) {
      if (stroke.points.isEmpty) continue;

      final isEraser = stroke.tool.toLowerCase() == 'eraser';
      final strokeWidth = (stroke.widthRatio * size.width).clamp(1.5, 60.0);

      final paint = Paint()
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth;

      if (isEraser) {
        paint.blendMode = BlendMode.clear;
        paint.color = const Color(0x00000000);
      } else {
        paint.blendMode = BlendMode.srcOver;
        paint.color = _parseColor(stroke.color);
      }

      if (stroke.points.length == 1) {
        final pt = stroke.points[0];
        final center = Offset(pt.xRatio * size.width, pt.yRatio * size.height);
        final dotPaint = Paint()
          ..blendMode = paint.blendMode
          ..color = paint.color
          ..style = PaintingStyle.fill;
        canvas.drawCircle(center, strokeWidth / 2.0, dotPaint);
      } else {
        final path = Path();
        final first = stroke.points[0];
        path.moveTo(first.xRatio * size.width, first.yRatio * size.height);

        for (int i = 1; i < stroke.points.length; i++) {
          final pt = stroke.points[i];
          path.lineTo(pt.xRatio * size.width, pt.yRatio * size.height);
        }
        canvas.drawPath(path, paint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FieldStrategyPainter oldDelegate) {
    return true;
  }
}
