import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/models/match_planning_models.dart';
import 'package:flutter/gestures.dart';
import 'package:obsidianscout_app/widgets/match_planning/draggable_team_marker.dart';
import 'package:obsidianscout_app/widgets/match_planning/canvas_toolbar.dart';
import 'package:obsidianscout_app/models/team_match_models.dart';
import 'package:obsidianscout_app/widgets/match_planning/strategy_field_canvas.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DraggableTeamMarkerWidget Tests', () {
    testWidgets('renders team number and station label correctly', (tester) async {
      TeamMarkerPosition? updatedPos;
      bool dragEnded = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                DraggableTeamMarkerWidget(
                  stationId: 'b1',
                  stationLabel: 'B1',
                  alliance: 'blue',
                  teamNumber: 254,
                  position: const TeamMarkerPosition(xRatio: 0.2, yRatio: 0.3),
                  canvasWidth: 800,
                  canvasHeight: 400,
                  onPositionChanged: (pos) => updatedPos = pos,
                  onDragEnd: () => dragEnded = true,
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('B1'), findsOneWidget);
      expect(find.text('254'), findsOneWidget);

      // Perform a drag gesture
      await tester.drag(find.text('254'), const Offset(50, 50));
      await tester.pump();

      expect(updatedPos, isNotNull);
      expect(updatedPos!.xRatio, greaterThan(0.2));
      expect(updatedPos!.yRatio, greaterThan(0.3));
      expect(dragEnded, isTrue);
    });
  });

  group('CanvasToolbar Independent Tool Sizes Tests', () {
    testWidgets('renders independent stroke widths and triggers callbacks', (tester) async {
      String activeTool = 'pen';
      double penSize = 6.0;
      double eraserSize = 22.0;

      double currentSize() => activeTool == 'eraser' ? eraserSize : penSize;

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: CanvasToolbar(
                  activeTool: activeTool,
                  currentColor: '#ffffff',
                  strokeWidth: currentSize(),
                  canUndo: false,
                  canRedo: false,
                  isFullscreen: false,
                  saveStatus: 'saved',
                  onToolChanged: (t) => setState(() => activeTool = t),
                  onColorChanged: (_) {},
                  onStrokeWidthChanged: (val) {
                    setState(() {
                      if (activeTool == 'eraser') {
                        eraserSize = val;
                      } else {
                        penSize = val;
                      }
                    });
                  },
                  onUndo: () {},
                  onRedo: () {},
                  onClear: () {},
                  onToggleFullscreen: () {},
                  onExport: () {},
                ),
              ),
            );
          },
        ),
      );

      // Initially in Pen mode, size is 6.0
      expect(currentSize(), equals(6.0));
      expect(penSize, equals(6.0));
      expect(eraserSize, equals(22.0));

      // Switch to Eraser
      await tester.tap(find.text('Eraser'));
      await tester.pumpAndSettle();

      expect(activeTool, equals('eraser'));
      expect(currentSize(), equals(22.0));

      // Drag slider to change eraser size
      final sliderFinder = find.byType(Slider);
      expect(sliderFinder, findsOneWidget);
      await tester.drag(sliderFinder, const Offset(30, 0));
      await tester.pumpAndSettle();

      // Eraser size changed, pen size remained unaffected
      expect(eraserSize, isNot(equals(22.0)));
      expect(penSize, equals(6.0));

      // Switch back to Pen
      await tester.tap(find.text('Pen'));
      await tester.pumpAndSettle();

      expect(activeTool, equals('pen'));
      expect(currentSize(), equals(6.0));
    });
  });

  group('StrategyFieldCanvas Barrel Button Tests', () {
    testWidgets('holding barrel button on touch-down activates eraser immediately without pen flash', (tester) async {
      String activeTool = 'pen';
      String currentColor = '#ffffff';
      StrokeAnnotation? completedStroke;

      final plan = MatchPlanModel();
      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return StrategyFieldCanvas(
                  repaintBoundaryKey: repaintKey,
                  plan: plan,
                  activeTool: activeTool,
                  currentColor: currentColor,
                  strokeWidth: 6.0,
                  penStrokeWidth: 6.0,
                  eraserStrokeWidth: 22.0,
                  fieldImage: null,
                  currentMatch: MatchModel(
                    matchKey: '2026test_qm1',
                    eventKey: '2026test',
                    label: 'Quals 1',
                    compLevel: 'qm',
                    matchNumber: 1,
                    blueTeams: ['frc254'],
                    redTeams: ['frc1678'],
                  ),
                  onStrokeCompleted: (s) => completedStroke = s,
                  onMarkerPositionChanged: (_, __) {},
                  onMarkerDragEnd: () {},
                  onToolChanged: (t) => setState(() => activeTool = t),
                  onColorChanged: (c) => setState(() => currentColor = c),
                );
              },
            ),
          ),
        ),
      );

      final center = tester.getCenter(find.byType(StrategyFieldCanvas));

      // Simulate stylus touch with barrel button held (kPrimaryButton | kPrimaryStylusButton)
      await tester.sendEventToBinding(
        PointerDownEvent(
          position: center,
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryButton | kPrimaryStylusButton,
        ),
      );
      await tester.pump();

      // Tool should immediately be eraser!
      expect(activeTool, equals('eraser'));

      await tester.sendEventToBinding(
        PointerMoveEvent(
          position: center + const Offset(30, 30),
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryButton | kPrimaryStylusButton,
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(
        PointerUpEvent(
          position: center + const Offset(30, 30),
          kind: PointerDeviceKind.stylus,
          buttons: 0,
        ),
      );
      await tester.pump();

      expect(completedStroke, isNotNull);
      expect(completedStroke!.tool, equals('eraser'));
    });

    testWidgets('drawing on canvas does not scroll parent Scrollable for hand and pencil', (tester) async {
      final scrollController = ScrollController();
      StrokeAnnotation? completedStroke;
      final plan = MatchPlanModel();
      final repaintKey = GlobalKey();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              controller: scrollController,
              child: Column(
                children: [
                  Container(height: 50, color: Colors.blue),
                  StrategyFieldCanvas(
                    repaintBoundaryKey: repaintKey,
                    plan: plan,
                    activeTool: 'pen',
                    currentColor: '#ffffff',
                    strokeWidth: 6.0,
                    penStrokeWidth: 6.0,
                    eraserStrokeWidth: 22.0,
                    fieldImage: null,
                    currentMatch: MatchModel(
                      matchKey: '2026test_qm1',
                      eventKey: '2026test',
                      label: 'Quals 1',
                      compLevel: 'qm',
                      matchNumber: 1,
                      blueTeams: ['frc254'],
                      redTeams: ['frc1678'],
                    ),
                    teamMap: const {},
                    onStrokeCompleted: (s) => completedStroke = s,
                    onMarkerPositionChanged: (_, __) {},
                    onMarkerDragEnd: () {},
                  ),
                  // Tall content below to allow scrolling
                  Container(key: const Key('below_canvas'), height: 1000, color: Colors.green),
                ],
              ),
            ),
          ),
        ),
      );

      final canvasCenter = tester.getCenter(find.byType(StrategyFieldCanvas));

      // 1. Draw vertically with TOUCH (hand/finger) across 150 pixels vertically
      await tester.sendEventToBinding(
        PointerDownEvent(
          position: canvasCenter,
          kind: PointerDeviceKind.touch,
          buttons: kPrimaryButton,
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(
        PointerMoveEvent(
          position: canvasCenter + const Offset(0, 150),
          kind: PointerDeviceKind.touch,
          buttons: kPrimaryButton,
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(
        PointerUpEvent(
          position: canvasCenter + const Offset(0, 150),
          kind: PointerDeviceKind.touch,
          buttons: 0,
        ),
      );
      await tester.pump();

      // Verify that stroke was drawn and scroll offset is STILL 0.0 (DID NOT SCROLL!)
      expect(completedStroke, isNotNull);
      expect(scrollController.offset, equals(0.0));

      completedStroke = null;

      // 2. Draw vertically with STYLUS (pencil) across 150 pixels vertically
      await tester.sendEventToBinding(
        PointerDownEvent(
          position: canvasCenter,
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryButton,
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(
        PointerMoveEvent(
          position: canvasCenter + const Offset(0, 150),
          kind: PointerDeviceKind.stylus,
          buttons: kPrimaryButton,
        ),
      );
      await tester.pump();

      await tester.sendEventToBinding(
        PointerUpEvent(
          position: canvasCenter + const Offset(0, 150),
          kind: PointerDeviceKind.stylus,
          buttons: 0,
        ),
      );
      await tester.pump();

      // Verify that stroke was drawn and scroll offset is STILL 0.0 (DID NOT SCROLL!)
      expect(completedStroke, isNotNull);
      expect(scrollController.offset, equals(0.0));

      // 3. Dragging on the area below the canvas DOES scroll the page normally
      await tester.dragFrom(const Offset(400, 500), const Offset(0, -100));
      await tester.pump();

      expect(scrollController.offset, greaterThan(0.0));
    });
  });

  group('Multi-Phase MatchPlanModel & Untouched Marker Inheritance Tests', () {
    test('untouched markers inherit from previous phases until touched', () {
      final plan = MatchPlanModel();

      // Initially all phases start at default b1 position (0.12, 0.20)
      expect(
        plan.markerPositionsForPhase('auto')['b1'],
        equals(const TeamMarkerPosition(xRatio: 0.12, yRatio: 0.20)),
      );
      expect(
        plan.markerPositionsForPhase('teleop')['b1'],
        equals(const TeamMarkerPosition(xRatio: 0.12, yRatio: 0.20)),
      );
      expect(
        plan.markerPositionsForPhase('endgame')['b1'],
        equals(const TeamMarkerPosition(xRatio: 0.12, yRatio: 0.20)),
      );

      // 1. Move b1 in Auto -> Teleop and Endgame inherit because they are untouched
      const autoPos1 = TeamMarkerPosition(xRatio: 0.30, yRatio: 0.40);
      plan.updateMarkerPosition('auto', 'b1', autoPos1);

      expect(plan.markerPositionsForPhase('auto')['b1'], equals(autoPos1));
      expect(plan.markerPositionsForPhase('teleop')['b1'], equals(autoPos1));
      expect(plan.markerPositionsForPhase('endgame')['b1'], equals(autoPos1));

      // 2. Touch/move b1 in Teleop -> Endgame inherits from Teleop, Auto stays at autoPos1
      const teleopPos1 = TeamMarkerPosition(xRatio: 0.55, yRatio: 0.60);
      plan.updateMarkerPosition('teleop', 'b1', teleopPos1);

      expect(plan.markerPositionsForPhase('auto')['b1'], equals(autoPos1));
      expect(plan.markerPositionsForPhase('teleop')['b1'], equals(teleopPos1));
      expect(plan.markerPositionsForPhase('endgame')['b1'], equals(teleopPos1));

      // 3. Move b1 again in Auto -> Teleop was touched so it does NOT inherit!
      const autoPos2 = TeamMarkerPosition(xRatio: 0.22, yRatio: 0.33);
      plan.updateMarkerPosition('auto', 'b1', autoPos2);

      expect(plan.markerPositionsForPhase('auto')['b1'], equals(autoPos2));
      expect(plan.markerPositionsForPhase('teleop')['b1'], equals(teleopPos1));
      expect(plan.markerPositionsForPhase('endgame')['b1'], equals(teleopPos1));

      // 4. Touch/move b1 in Endgame -> Endgame is now independent of Teleop too
      const endgamePos1 = TeamMarkerPosition(xRatio: 0.75, yRatio: 0.80);
      plan.updateMarkerPosition('endgame', 'b1', endgamePos1);

      const teleopPos2 = TeamMarkerPosition(xRatio: 0.65, yRatio: 0.70);
      plan.updateMarkerPosition('teleop', 'b1', teleopPos2);

      expect(plan.markerPositionsForPhase('auto')['b1'], equals(autoPos2));
      expect(plan.markerPositionsForPhase('teleop')['b1'], equals(teleopPos2));
      expect(plan.markerPositionsForPhase('endgame')['b1'], equals(endgamePos1));

      // 5. Round-trip JSON serialization preserves phases, drawings, and touched state
      plan.annotationsForPhase('auto').add(
            StrokeAnnotation(points: [const StrokePoint(0.1, 0.1), const StrokePoint(0.2, 0.2)]),
          );
      plan.annotationsForPhase('teleop').add(
            StrokeAnnotation(points: [const StrokePoint(0.4, 0.4), const StrokePoint(0.5, 0.5)]),
          );

      final rawJson = plan.toJsonString();
      final restored = MatchPlanModel.fromJsonString(rawJson);

      expect(restored.annotationsForPhase('auto').length, equals(1));
      expect(restored.annotationsForPhase('teleop').length, equals(1));
      expect(restored.annotationsForPhase('endgame'), isEmpty);
      expect(restored.markerPositionsForPhase('auto')['b1'], equals(autoPos2));
      expect(restored.markerPositionsForPhase('teleop')['b1'], equals(teleopPos2));
      expect(restored.markerPositionsForPhase('endgame')['b1'], equals(endgamePos1));
    });

    testWidgets('CanvasToolbar switches between Auto, Teleop, and Endgame phases', (tester) async {
      String activePhase = 'auto';

      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            return MaterialApp(
              home: Scaffold(
                body: CanvasToolbar(
                  activePhase: activePhase,
                  onPhaseChanged: (p) => setState(() => activePhase = p),
                  activeTool: 'pen',
                  currentColor: '#ffffff',
                  strokeWidth: 6.0,
                  canUndo: false,
                  canRedo: false,
                  isFullscreen: false,
                  saveStatus: 'saved',
                  onToolChanged: (_) {},
                  onColorChanged: (_) {},
                  onStrokeWidthChanged: (_) {},
                  onUndo: () {},
                  onRedo: () {},
                  onClear: () {},
                  onToggleFullscreen: () {},
                  onExport: () {},
                ),
              ),
            );
          },
        ),
      );

      expect(find.text('Auto'), findsOneWidget);
      expect(find.text('Teleop'), findsOneWidget);
      expect(find.text('Endgame'), findsOneWidget);

      await tester.tap(find.text('Teleop'));
      await tester.pumpAndSettle();
      expect(activePhase, equals('teleop'));

      await tester.tap(find.text('Endgame'));
      await tester.pumpAndSettle();
      expect(activePhase, equals('endgame'));
    });
  });
}


