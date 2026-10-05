import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import '../../models/match_planning_models.dart';

class DraggableTeamMarkerWidget extends StatefulWidget {
  final String stationId; // 'b1', 'b2', 'b3', 'r1', 'r2', 'r3'
  final String stationLabel; // 'B1', 'R1'...
  final String alliance; // 'blue' | 'red'
  final int teamNumber;
  final TeamMarkerPosition position;
  final double canvasWidth;
  final double canvasHeight;
  final ValueChanged<TeamMarkerPosition> onPositionChanged;
  final VoidCallback onDragEnd;

  const DraggableTeamMarkerWidget({
    super.key,
    required this.stationId,
    required this.stationLabel,
    required this.alliance,
    required this.teamNumber,
    required this.position,
    required this.canvasWidth,
    required this.canvasHeight,
    required this.onPositionChanged,
    required this.onDragEnd,
  });

  @override
  State<DraggableTeamMarkerWidget> createState() => _DraggableTeamMarkerWidgetState();
}

class _DraggableTeamMarkerWidgetState extends State<DraggableTeamMarkerWidget> {
  late TeamMarkerPosition _currentPosition;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _currentPosition = widget.position;
  }

  @override
  void didUpdateWidget(covariant DraggableTeamMarkerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && widget.position != oldWidget.position) {
      _currentPosition = widget.position;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.teamNumber <= 0 || widget.canvasWidth <= 0 || widget.canvasHeight <= 0) {
      return const SizedBox.shrink();
    }

    final isBlue = widget.alliance.toLowerCase() == 'blue';
    final borderColor = isBlue ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final stationTextColor = isBlue ? const Color(0xFF93C5FD) : const Color(0xFFFCA5A5);

    // Responsive box size: ~6% of width clamped between 46 and 60
    final boxSize = (widget.canvasWidth * 0.065).clamp(46.0, 60.0);
    final halfBox = boxSize / 2.0;

    final leftPos = (_currentPosition.xRatio * widget.canvasWidth) - halfBox;
    final topPos = (_currentPosition.yRatio * widget.canvasHeight) - halfBox;

    return Positioned(
      left: leftPos.clamp(0.0, widget.canvasWidth - boxSize),
      top: topPos.clamp(0.0, widget.canvasHeight - boxSize),
      child: RawGestureDetector(
        gestures: <Type, GestureRecognizerFactory>{
          EagerGestureRecognizer: GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
            () => EagerGestureRecognizer(),
            (EagerGestureRecognizer instance) {},
          ),
        },
        child: Listener(
          behavior: HitTestBehavior.opaque,
          onPointerDown: (_) {
            setState(() => _isDragging = true);
          },
          onPointerMove: (event) {
            if (!_isDragging) return;
            final newX = (_currentPosition.xRatio * widget.canvasWidth) + event.delta.dx;
            final newY = (_currentPosition.yRatio * widget.canvasHeight) + event.delta.dy;
            final newXRatio = (newX / widget.canvasWidth).clamp(0.02, 0.98);
            final newYRatio = (newY / widget.canvasHeight).clamp(0.02, 0.98);
            final updated = TeamMarkerPosition(xRatio: newXRatio, yRatio: newYRatio);
            setState(() {
              _currentPosition = updated;
            });
            widget.onPositionChanged(updated);
          },
          onPointerUp: (_) {
            if (_isDragging) {
              setState(() => _isDragging = false);
              widget.onDragEnd();
            }
          },
          onPointerCancel: (_) {
            if (_isDragging) {
              setState(() => _isDragging = false);
              widget.onDragEnd();
            }
          },
          child: RepaintBoundary(
          child: Transform.scale(
            scale: _isDragging ? 1.12 : 1.0,
            child: Container(
              width: boxSize,
              height: boxSize,
              decoration: BoxDecoration(
                color: const Color(0xE60F172A), // Dark slate
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: borderColor, width: _isDragging ? 3.0 : 2.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: _isDragging ? 0.7 : 0.45),
                    blurRadius: _isDragging ? 12 : 6,
                    offset: Offset(0, _isDragging ? 6 : 3),
                  ),
                ],
              ),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2.0, vertical: 2.0),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          widget.stationLabel,
                          style: TextStyle(
                            fontSize: (boxSize * 0.22).clamp(8.0, 11.0),
                            fontWeight: FontWeight.w900,
                            color: stationTextColor,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.teamNumber}',
                          style: TextStyle(
                            fontSize: (boxSize * 0.36).clamp(11.0, 16.0),
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            height: 1.0,
                            shadows: const [
                              Shadow(color: Color(0xCC000000), blurRadius: 4, offset: Offset(0, 1)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
}
