/// Shared xHarness brand mark.
library;

import 'package:flutter/material.dart';

import 'src/theme.dart';

class BrandMark extends StatelessWidget {
  const BrandMark({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.28),
        boxShadow: [
          BoxShadow(
            color: P.accent.withValues(alpha: 0.45),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          'assets/branding/hermes-agent-icon-512.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => Container(
            decoration: BoxDecoration(gradient: P.brandGradient),
            child: Icon(
              Icons.auto_awesome,
              color: P.onAccent,
              size: size * 0.5,
            ),
          ),
        ),
      ),
    );
  }
}
