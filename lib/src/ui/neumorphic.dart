import 'package:flutter/material.dart';
import '../theme.dart';

class NeuSurface extends StatelessWidget {
  const NeuSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.radius = 18,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: P.card,
      borderRadius: BorderRadius.circular(radius),
      boxShadow: P.neuShadows,
    ),
    child: Material(color: P.transparent, child: child),
  );
}

/// A dark leading edge and light trailing edge simulate a recessed well.
class NeuInset extends StatelessWidget {
  const NeuInset({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(4),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(P.neuShadow.withValues(alpha: .25), P.code),
            P.code,
            Color.alphaBlend(P.neuHighlight, P.code),
          ],
        ),
        border: Border(
          top: BorderSide(color: P.neuShadow),
          bottom: BorderSide(color: P.neuHighlight),
        ),
      ),
      child: child,
    ),
  );
}

class NeuSegmented<T> extends StatelessWidget {
  const NeuSegmented({
    super.key,
    required this.values,
    required this.selected,
    required this.onSelected,
  });
  final Map<T, String> values;
  final T selected;
  final ValueChanged<T> onSelected;
  @override
  Widget build(BuildContext context) => NeuInset(
    child: Row(
      children: [
        for (final entry in values.entries)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: Material(
                color: P.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => onSelected(entry.key),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      vertical: 10,
                      horizontal: 4,
                    ),
                    decoration: entry.key == selected
                        ? BoxDecoration(
                            color: P.cardAlt,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: P.neuShadows,
                          )
                        : null,
                    child: Text(
                      entry.value,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: entry.key == selected
                            ? P.accentLight
                            : P.textSecondary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class NeonButton extends StatelessWidget {
  const NeonButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
  });
  final VoidCallback? onPressed;
  final String label;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: P.brandGradient,
      borderRadius: BorderRadius.circular(16),
      boxShadow: onPressed == null
          ? []
          : [
              BoxShadow(
                color: P.accentGlow,
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
    ),
    child: FilledButton(
      onPressed: onPressed,
      style: FilledButton.styleFrom(
        backgroundColor: P.transparent,
        shadowColor: P.transparent,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon), const SizedBox(width: 8)],
          Flexible(child: Text(label, textAlign: TextAlign.center)),
        ],
      ),
    ),
  );
}
