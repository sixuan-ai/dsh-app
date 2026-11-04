import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme.dart';

/// Reserve blur for a few floating surfaces, never scrolling list rows.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 22,
    this.tint,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? tint;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              P.isDark
                  ? P.glassHighlight.withValues(alpha: .08)
                  : P.glassHighlight,
              P.glassFill,
            ],
          ),
          border: Border(
            top: BorderSide(color: tint ?? P.glassHighlight),
            bottom: BorderSide(color: tint ?? P.glassStroke),
            left: BorderSide(color: tint ?? P.glassStroke),
            right: BorderSide(color: tint ?? P.glassStroke),
          ),
        ),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: P.neuHighlight)),
          ),
          child: child,
        ),
      ),
    ),
  );
}

class AppBackdrop extends StatelessWidget {
  const AppBackdrop({super.key, required this.child, required this.enabled});
  final Widget child;
  final bool enabled;
  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return ColoredBox(
      color: P.bg,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(.85, -1.1),
                    radius: 1.1,
                    colors: [P.accent.withValues(alpha: .12), P.transparent],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-1.1, 1.1),
                    radius: .9,
                    colors: [P.info.withValues(alpha: .08), P.transparent],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(1.1, .4),
                    radius: .7,
                    colors: [P.agent.withValues(alpha: .06), P.transparent],
                  ),
                ),
              ),
            ),
          ),
          child,
        ],
      ),
    );
  }
}
