import 'package:flutter/material.dart';

/// Custom PageTransitionsBuilder implementing Samsung One UI style horizontal slide-over.
class SamsungSlideTransitionsBuilder extends PageTransitionsBuilder {
  const SamsungSlideTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Samsung One UI cubic bezier deceleration curve
    final primaryCurve = CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      reverseCurve: Curves.easeInCubic,
    );

    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
      reverseCurve: Curves.easeInCubic,
    );

    // Primary: slide in from right with subtle fade
    final slideIn = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(primaryCurve);

    final fadeIn = Tween<double>(
      begin: 0.4,
      end: 1.0,
    ).animate(primaryCurve);

    // Secondary (when another page is pushed on top): slide slightly left with subtle dim
    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.25, 0.0),
    ).animate(secondaryCurve);

    final fadeOut = Tween<double>(
      begin: 1.0,
      end: 0.85,
    ).animate(secondaryCurve);

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeOut,
        child: SlideTransition(
          position: slideIn,
          child: FadeTransition(
            opacity: fadeIn,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Custom PageTransitionsBuilder implementing Windows 11 / Fluent UI style vertical slide-up.
class WindowsSlideUpTransitionsBuilder extends PageTransitionsBuilder {
  const WindowsSlideUpTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Windows Fluent UI smooth entrance curve
    final primaryCurve = CurvedAnimation(
      parent: animation,
      curve: const Cubic(0.0, 0.0, 0.0, 1.0),
      reverseCurve: Curves.easeInQuad,
    );

    final secondaryCurve = CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInQuad,
    );

    // Primary: subtle slide up from bottom + smooth fade in
    final slideUp = Tween<Offset>(
      begin: const Offset(0.0, 0.06),
      end: Offset.zero,
    ).animate(primaryCurve);

    final fadeIn = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(primaryCurve);

    // Secondary: subtle upward drift + fade out
    final slideOut = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(0.0, -0.02),
    ).animate(secondaryCurve);

    final fadeOut = Tween<double>(
      begin: 1.0,
      end: 0.0,
    ).animate(secondaryCurve);

    return SlideTransition(
      position: slideOut,
      child: FadeTransition(
        opacity: fadeOut,
        child: SlideTransition(
          position: slideUp,
          child: FadeTransition(
            opacity: fadeIn,
            child: child,
          ),
        ),
      ),
    );
  }
}

/// A state-preserving AnimatedIndexedStack that smoothly transitions between
/// children using Samsung-style horizontal slide-over on mobile and Windows-style
/// vertical slide-up on desktop/computer.
class ObsidianAnimatedIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const ObsidianAnimatedIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = const Duration(milliseconds: 280),
  });

  @override
  State<ObsidianAnimatedIndexedStack> createState() => _ObsidianAnimatedIndexedStackState();
}

class _ObsidianAnimatedIndexedStackState extends State<ObsidianAnimatedIndexedStack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  int _currentIndex = 0;
  int _previousIndex = 0;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _previousIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: const Cubic(0.22, 1.0, 0.36, 1.0),
    );
    _controller.value = 1.0;
  }

  @override
  void didUpdateWidget(ObsidianAnimatedIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != _currentIndex) {
      setState(() {
        _previousIndex = _currentIndex;
        _currentIndex = widget.index;
      });
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool _isMobile(BuildContext context) {
    final platform = Theme.of(context).platform;
    return platform == TargetPlatform.android || platform == TargetPlatform.iOS;
  }

  @override
  Widget build(BuildContext context) {
    final isMobile = _isMobile(context);
    final isMovingForward = _currentIndex >= _previousIndex;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        final animValue = _animation.value;
        final isAnimating = _controller.isAnimating && _currentIndex != _previousIndex;

        return Stack(
          fit: StackFit.expand,
          children: List.generate(widget.children.length, (index) {
            final isCurrent = index == _currentIndex;
            final isPrevious = index == _previousIndex;

            if (!isCurrent && !isPrevious) {
              return Offstage(
                offstage: true,
                child: TickerMode(
                  enabled: false,
                  child: widget.children[index],
                ),
              );
            }

            if (!isAnimating) {
              if (isCurrent) {
                return TickerMode(
                  enabled: true,
                  child: widget.children[index],
                );
              } else {
                return Offstage(
                  offstage: true,
                  child: TickerMode(
                    enabled: false,
                    child: widget.children[index],
                  ),
                );
              }
            }

            // During animation:
            if (isMobile) {
              // Samsung One UI slide-over
              if (isCurrent) {
                final startOffset = isMovingForward ? const Offset(1.0, 0.0) : const Offset(-0.35, 0.0);
                final offset = Offset.lerp(startOffset, Offset.zero, animValue)!;
                final opacity = (0.2 + 0.8 * animValue).clamp(0.0, 1.0);
                return FractionalTranslation(
                  translation: offset,
                  child: Opacity(
                    opacity: opacity,
                    child: TickerMode(
                      enabled: true,
                      child: widget.children[index],
                    ),
                  ),
                );
              } else if (isPrevious) {
                final endOffset = isMovingForward ? const Offset(-0.25, 0.0) : const Offset(1.0, 0.0);
                final offset = Offset.lerp(Offset.zero, endOffset, animValue)!;
                final opacity = (1.0 - 0.3 * animValue).clamp(0.0, 1.0);
                return FractionalTranslation(
                  translation: offset,
                  child: Opacity(
                    opacity: opacity,
                    child: TickerMode(
                      enabled: false,
                      child: widget.children[index],
                    ),
                  ),
                );
              }
            } else {
              // Windows Fluent UI slide-up + fade
              if (isCurrent) {
                final offset = Offset.lerp(const Offset(0.0, 0.05), Offset.zero, animValue)!;
                final opacity = animValue.clamp(0.0, 1.0);
                return FractionalTranslation(
                  translation: offset,
                  child: Opacity(
                    opacity: opacity,
                    child: TickerMode(
                      enabled: true,
                      child: widget.children[index],
                    ),
                  ),
                );
              } else if (isPrevious) {
                final offset = Offset.lerp(Offset.zero, const Offset(0.0, -0.02), animValue)!;
                final opacity = (1.0 - animValue).clamp(0.0, 1.0);
                return FractionalTranslation(
                  translation: offset,
                  child: Opacity(
                    opacity: opacity,
                    child: TickerMode(
                      enabled: false,
                      child: widget.children[index],
                    ),
                  ),
                );
              }
            }

            return Offstage(
              offstage: true,
              child: TickerMode(
                enabled: false,
                child: widget.children[index],
              ),
            );
          }),
        );
      },
    );
  }
}
