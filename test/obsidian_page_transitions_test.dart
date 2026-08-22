import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:obsidianscout_app/theme/obsidian_page_transitions.dart';
import 'package:obsidianscout_app/theme/obsidian_ui_theme.dart';

void main() {
  group('Obsidian Page Transitions', () {
    testWidgets('SamsungSlideTransitionsBuilder produces slide and fade transitions', (tester) async {
      const builder = SamsungSlideTransitionsBuilder();
      late AnimationController controller;
      late AnimationController secondaryController;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              final tickerProvider = tester;
              controller = AnimationController(
                vsync: tickerProvider,
                duration: const Duration(milliseconds: 300),
              );
              secondaryController = AnimationController(
                vsync: tickerProvider,
                duration: const Duration(milliseconds: 300),
              );

              return builder.buildTransitions(
                MaterialPageRoute(builder: (_) => const SizedBox()),
                context,
                controller,
                secondaryController,
                const Text('Samsung Transition Test'),
              );
            },
          ),
        ),
      );

      expect(find.text('Samsung Transition Test'), findsOneWidget);
      expect(find.byType(SlideTransition), findsWidgets);
      expect(find.byType(FadeTransition), findsWidgets);

      controller.dispose();
      secondaryController.dispose();
    });

    testWidgets('WindowsSlideUpTransitionsBuilder produces vertical slide and fade transitions', (tester) async {
      const builder = WindowsSlideUpTransitionsBuilder();
      late AnimationController controller;
      late AnimationController secondaryController;

      await tester.pumpWidget(
        MaterialApp(
          home: StatefulBuilder(
            builder: (context, setState) {
              final tickerProvider = tester;
              controller = AnimationController(
                vsync: tickerProvider,
                duration: const Duration(milliseconds: 300),
              );
              secondaryController = AnimationController(
                vsync: tickerProvider,
                duration: const Duration(milliseconds: 300),
              );

              return builder.buildTransitions(
                MaterialPageRoute(builder: (_) => const SizedBox()),
                context,
                controller,
                secondaryController,
                const Text('Windows Transition Test'),
              );
            },
          ),
        ),
      );

      expect(find.text('Windows Transition Test'), findsOneWidget);
      expect(find.byType(SlideTransition), findsWidgets);
      expect(find.byType(FadeTransition), findsWidgets);

      controller.dispose();
      secondaryController.dispose();
    });

    testWidgets('ObsidianAnimatedIndexedStack smoothly displays active child', (tester) async {
      int activeIndex = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ObsidianUITheme.darkTheme,
          home: StatefulBuilder(
            builder: (context, setState) {
              return Scaffold(
                body: ObsidianAnimatedIndexedStack(
                  index: activeIndex,
                  children: const [
                    Text('Screen 0: Dashboard'),
                    Text('Screen 1: Match Scout'),
                    Text('Screen 2: Pit Scout'),
                  ],
                ),
                floatingActionButton: FloatingActionButton(
                  onPressed: () {
                    setState(() {
                      activeIndex = 1;
                    });
                  },
                  child: const Icon(Icons.navigate_next),
                ),
              );
            },
          ),
        ),
      );

      expect(find.text('Screen 0: Dashboard'), findsOneWidget);

      // Tap to switch tab
      await tester.tap(find.byType(FloatingActionButton));
      await tester.pump(); // Start animation
      await tester.pump(const Duration(milliseconds: 150)); // Midway
      await tester.pumpAndSettle(); // Complete transition

      expect(find.text('Screen 1: Match Scout'), findsOneWidget);
    });

    test('ObsidianUITheme includes custom page transitions builders', () {
      final dark = ObsidianUITheme.darkTheme;
      final light = ObsidianUITheme.lightTheme;

      expect(dark.pageTransitionsTheme.builders[TargetPlatform.android], isA<SamsungSlideTransitionsBuilder>());
      expect(dark.pageTransitionsTheme.builders[TargetPlatform.windows], isA<WindowsSlideUpTransitionsBuilder>());
      expect(light.pageTransitionsTheme.builders[TargetPlatform.android], isA<SamsungSlideTransitionsBuilder>());
      expect(light.pageTransitionsTheme.builders[TargetPlatform.windows], isA<WindowsSlideUpTransitionsBuilder>());
    });
  });
}
