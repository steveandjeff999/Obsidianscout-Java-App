import 'package:flutter/material.dart';
import '../../models/match_planning_models.dart';

class DraggableTeamMarkerWidget extends StatelessWidget {
  final String stationId; // 'b1', 'b2', 'b3', 'r1', 'r2', 'r3'
  final String stationLabel; // 'B1', 'R1'...
  final String alliance; // 'blue' | 'red'
  final int teamNumber;
  final TeamMarkerPosition position;
  final double canvasWidth;
  final double canvasHeight;
  final bool isDragging;
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
    this.isDragging = false,
    required this.onPositionChanged,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    if (teamNumber <= 0 || canvasWidth <= 0 || canvasHeight <= 0) {
      return const SizedBox.shrink();
    }

    final isBlue = alliance.toLowerCase() == 'blue';
    final borderColor = isBlue ? const Color(0xFF3B82F6) : const Color(0xFFEF4444);
    final stationTextColor = isBlue ? const Color(0xFF93C5FD) : const Color(0xFFFCA5A5);

    // Responsive box size: ~6% of width clamped between 46 and 60
    final boxSize = (canvasWidth * 0.065).clamp(46.0, 60.0);
    final halfBox = boxSize / 2.0;

    final leftPos = (position.xRatio * canvasWidth) - halfBox;
    final topPos = (position.yRatio * canvasHeight) - halfBox;

    return Positioned(
      left: leftPos.clamp(0.0, canvasWidth - boxSize),
      top: topPos.clamp(0.0, canvasHeight - boxSize),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: (details) {
          final newX = (position.xRatio * canvasWidth) + details.delta.dx;
          final newY = (position.yRatio * canvasHeight) + details.delta.dy;
          final newXRatio = (newX / canvasWidth).clamp(0.02, 0.98);
          final newYRatio = (newY / canvasHeight).clamp(0.02, 0.98);
          onPositionChanged(TeamMarkerPosition(xRatio: newXRatio, yRatio: newYRatio));
        },
        onPanEnd: (_) => onDragEnd(),
        onPanCancel: () => onDragEnd(),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 100),
          scale: isDragging ? 1.15 : 1.0,
          child: Container(
            width: boxSize,
            height: boxSize,
            decoration: BoxDecoration(
              color: const Color(0xE60F172A), // Dark slate
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: borderColor, width: isDragging ? 3.0 : 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDragging ? 0.7 : 0.45),
                  blurRadius: isDragging ? 12 : 6,
                  offset: Offset(0, isDragging ? 6 : 3),
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
                        stationLabel,
                        style: TextStyle(
                          fontSize: (boxSize * 0.22).clamp(8.0, 11.0),
                          fontWeight: FontWeight.w900,
                          color: stationTextColor,
                          height: 1.0,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$teamNumber',
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
    );
  }
}
