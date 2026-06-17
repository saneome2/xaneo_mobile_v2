import 'package:flutter/material.dart';

enum PremiumTransitionType {
  chatReveal,      // Telegram-like slide from right
  archivedReveal,  // Telegram-like slide from right
}

class PremiumPageRoute<T> extends PageRouteBuilder<T> {
  final Widget page;
  final PremiumTransitionType transitionType;

  PremiumPageRoute({
    required this.page,
    this.transitionType = PremiumTransitionType.chatReveal,
    super.settings,
    Duration duration = const Duration(milliseconds: 360),
    Duration reverseDuration = const Duration(milliseconds: 280),
  }) : super(
          pageBuilder: (context, animation, secondaryAnimation) => page,
          transitionDuration: duration,
          reverseTransitionDuration: reverseDuration,
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            // Telegram-style curve: starts with an extremely high velocity (steep curve)
            // and then decelerates sharply to settle smoothly.
            // Cubic(0.08, 0.92, 0.1, 1.0) achieves this exact response.
            // To make the reverse animation behave exactly the same (leaving with high velocity immediately
            // instead of sluggishly accelerating at the end), we use the mathematically mirrored curve:
            // Cubic(1 - x2, 1 - y2, 1 - x1, 1 - y1) -> Cubic(0.9, 0.0, 0.92, 0.08).
            final primaryCurve = CurvedAnimation(
              parent: animation,
              curve: const Cubic(0.08, 0.92, 0.1, 1.0),
              reverseCurve: const Cubic(0.9, 0.0, 0.92, 0.08),
            );

            final secondaryCurve = CurvedAnimation(
              parent: secondaryAnimation,
              curve: const Cubic(0.08, 0.92, 0.1, 1.0),
              reverseCurve: const Cubic(0.9, 0.0, 0.92, 0.08),
            );

            // Incoming page transition: slides from 100% right to center
            final slideIn = Tween<Offset>(
              begin: const Offset(1.0, 0.0),
              end: Offset.zero,
            ).animate(primaryCurve);

            // Underlying page transition: slides left from center to -30% left
            final slideOut = Tween<Offset>(
              begin: Offset.zero,
              end: const Offset(-0.3, 0.0),
            ).animate(secondaryCurve);

            // Dimming overlay color animation for the underlying page to add depth
            final overlayColor = ColorTween(
              begin: Colors.transparent,
              end: Colors.black.withValues(alpha: 0.45),
            ).animate(secondaryCurve);

            return SlideTransition(
              position: slideOut,
              child: AnimatedBuilder(
                animation: overlayColor,
                builder: (context, childWidget) {
                  final color = overlayColor.value;
                  if (color == null || color == Colors.transparent) {
                    return childWidget!;
                  }
                  return ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      color,
                      BlendMode.srcATop,
                    ),
                    child: childWidget,
                  );
                },
                child: SlideTransition(
                  position: slideIn,
                  child: Container(
                    decoration: const BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black38,
                          blurRadius: 18.0,
                          spreadRadius: 1.0,
                          offset: Offset(-6.0, 0.0),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}
