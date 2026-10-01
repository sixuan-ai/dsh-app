/// Original vector-style pet sprites. Drawing them in Flutter keeps the
/// character art sharp on phones and avoids image-transform rendering issues.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// A colorful Q-style evolution sprite for one pet form.
class PetSprite extends StatelessWidget {
  const PetSprite({
    super.key,
    required this.speciesId,
    required this.stageIndex,
    this.mood = 80,
    this.hatching = false,
    this.size = 180,
  });

  final String speciesId;
  final int stageIndex;
  final int mood;

  /// Draws cracks over the egg during the final quarter-level before hatch.
  final bool hatching;

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _PetSpritePainter(
        speciesId: speciesId,
        stageIndex: stageIndex,
        mood: mood,
        hatching: hatching,
      ),
    );
  }
}

class _PetSpritePainter extends CustomPainter {
  _PetSpritePainter({
    required this.speciesId,
    required this.stageIndex,
    required this.mood,
    required this.hatching,
  });

  final String speciesId;
  final int stageIndex;
  final int mood;
  final bool hatching;

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + 8;
    final scale = size.shortestSide / 180;
    canvas.save();
    canvas.translate(cx, cy);
    canvas.scale(scale);

    final colors = _colors(speciesId);
    final accent = colors.$1;
    final light = colors.$2;
    final dark = colors.$3;
    final legendary = stageIndex >= 4;
    final evolved = stageIndex >= 2;
    final baby = stageIndex <= 1;

    // Soft aura and sparkles make stage upgrades visually obvious.
    final auraPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          accent.withValues(alpha: legendary ? 0.42 : 0.24),
          accent.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 88));
    canvas.drawCircle(Offset.zero, legendary ? 82 : 72, auraPaint);
    if (evolved) _sparkles(canvas, accent, legendary);

    if (stageIndex == 0) {
      _drawEgg(canvas, accent, light, dark, hatching);
    } else {
      if (speciesId == 'phoenix') {
        _wings(canvas, accent, light, dark, legendary);
      }
      if (speciesId == 'dragon') {
        _wings(canvas, accent, light, dark, legendary);
      }
      _drawBody(canvas, accent, light, dark, baby, evolved, legendary);
      if (speciesId == 'cat' || speciesId == 'spirit') {
        _ears(canvas, accent, dark, legendary);
      }
      if (speciesId == 'dog') {
        _ears(canvas, accent, dark, legendary, round: true);
      }
      if (speciesId == 'dragon') _horns(canvas, light, dark, legendary);
      _face(canvas, dark, legendary);
      if (evolved) _tail(canvas, accent, light, dark, legendary);
    }
    if (mood <= 25) _moodMark(canvas, accent);
    if (mood >= 80 && stageIndex > 0) _happySpark(canvas, light);
    canvas.restore();
  }

  (Color, Color, Color) _colors(String id) {
    switch (id) {
      case 'cat':
        return (
          const Color(0xFF4E8CFF),
          const Color(0xFFB8D7FF),
          const Color(0xFF263B7A),
        );
      case 'dog':
        return (
          const Color(0xFF9A62E8),
          const Color(0xFFE4C9FF),
          const Color(0xFF4A2A75),
        );
      case 'dragon':
        return (
          const Color(0xFFFF6A2A),
          const Color(0xFFFFC35A),
          const Color(0xFF7F2020),
        );
      case 'phoenix':
        return (
          const Color(0xFFFF4F8B),
          const Color(0xFFFFD36A),
          const Color(0xFF8B245C),
        );
      default:
        return (
          const Color(0xFF4BC7B8),
          const Color(0xFFB9FFF0),
          const Color(0xFF166B72),
        );
    }
  }

  void _drawEgg(
    Canvas c,
    Color accent,
    Color light,
    Color dark,
    bool hatching,
  ) {
    final egg = Path()
      ..moveTo(0, -64)
      ..cubicTo(-36, -55, -47, -18, -42, 22)
      ..cubicTo(-37, 58, -18, 72, 0, 72)
      ..cubicTo(24, 72, 42, 52, 43, 20)
      ..cubicTo(45, -20, 29, -56, 0, -64)
      ..close();
    c.drawShadow(egg, dark.withValues(alpha: 0.35), 10, true);
    c.drawPath(
      egg,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [light, accent],
        ).createShader(const Rect.fromLTWH(-45, -65, 90, 140)),
    );
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = dark.withValues(alpha: 0.8);
    c.drawPath(egg, outline);
    c.drawCircle(
      const Offset(-13, -6),
      7,
      Paint()..color = Colors.white.withValues(alpha: 0.75),
    );
    c.drawCircle(
      const Offset(18, 25),
      5,
      Paint()..color = dark.withValues(alpha: 0.28),
    );
    c.drawArc(
      const Rect.fromLTWH(-20, -30, 40, 42),
      0.2,
      2.0,
      false,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    if (hatching) {
      final crack = Paint()
        ..color = dark
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      final path = Path()
        ..moveTo(-8, -52)
        ..lineTo(-17, -34)
        ..lineTo(-5, -26)
        ..lineTo(-14, -7)
        ..moveTo(8, -48)
        ..lineTo(17, -31)
        ..lineTo(7, -20);
      c.drawPath(path, crack);
    }
  }

  void _drawBody(
    Canvas c,
    Color accent,
    Color light,
    Color dark,
    bool baby,
    bool evolved,
    bool legendary,
  ) {
    final bodyW = legendary
        ? 48.0
        : evolved
        ? 43.0
        : 36.0;
    final bodyH = legendary
        ? 62.0
        : evolved
        ? 55.0
        : 45.0;
    final body = RRect.fromRectAndRadius(
      Rect.fromCenter(
        center: Offset(0, 20),
        width: bodyW * 2,
        height: bodyH * 2,
      ),
      Radius.circular(bodyW),
    );
    c.drawShadow(Path()..addRRect(body), dark.withValues(alpha: 0.35), 8, true);
    c.drawRRect(
      body,
      Paint()
        ..shader =
            LinearGradient(
              colors: [light, accent, dark],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ).createShader(
              Rect.fromCenter(
                center: const Offset(0, 20),
                width: bodyW * 2,
                height: bodyH * 2,
              ),
            ),
    );
    c.drawRRect(
      body,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = dark.withValues(alpha: 0.8),
    );
    // Belly highlight.
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0, 27),
        width: bodyW * 1.15,
        height: bodyH * 1.2,
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.22),
    );
    // Feet.
    final foot = Paint()..color = dark.withValues(alpha: 0.75);
    c.drawOval(const Rect.fromLTWH(-35, 58, 28, 15), foot);
    c.drawOval(const Rect.fromLTWH(7, 58, 28, 15), foot);
  }

  void _face(Canvas c, Color dark, bool legendary) {
    final eye = Paint()..color = const Color(0xFF171A35);
    final shine = Paint()..color = Colors.white;
    final eyeR = legendary ? 7.0 : 6.0;
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(-17, -11),
        width: eyeR * 2,
        height: eyeR * 2.5,
      ),
      eye,
    );
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(17, -11),
        width: eyeR * 2,
        height: eyeR * 2.5,
      ),
      eye,
    );
    c.drawCircle(const Offset(-15, -14), 2.3, shine);
    c.drawCircle(const Offset(19, -14), 2.3, shine);
    final mouth = Paint()
      ..color = dark.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    c.drawArc(const Rect.fromLTWH(-8, 0, 16, 12), 0, math.pi, false, mouth);
    c.drawCircle(
      const Offset(-25, 2),
      4,
      Paint()..color = const Color(0xFFFF8EA5).withValues(alpha: 0.65),
    );
    c.drawCircle(
      const Offset(25, 2),
      4,
      Paint()..color = const Color(0xFFFF8EA5).withValues(alpha: 0.65),
    );
  }

  void _ears(
    Canvas c,
    Color accent,
    Color dark,
    bool legendary, {
    bool round = false,
  }) {
    final left = Path()
      ..moveTo(-31, -37)
      ..lineTo(-48, round ? -52 : -65)
      ..lineTo(-7, -48)
      ..close();
    final right = Path()
      ..moveTo(31, -37)
      ..lineTo(48, round ? -52 : -65)
      ..lineTo(7, -48)
      ..close();
    final p = Paint()..color = accent;
    c.drawPath(left, p);
    c.drawPath(right, p);
    if (legendary) {
      c.drawCircle(const Offset(-42, -55), 4, Paint()..color = Colors.white);
      c.drawCircle(const Offset(42, -55), 4, Paint()..color = Colors.white);
    }
    c.drawPath(
      left,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = dark.withValues(alpha: 0.75),
    );
    c.drawPath(
      right,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = dark.withValues(alpha: 0.75),
    );
  }

  void _horns(Canvas c, Color light, Color dark, bool legendary) {
    final p = Paint()..color = light;
    final left = Path()
      ..moveTo(-26, -40)
      ..lineTo(-20, -75)
      ..lineTo(-5, -43)
      ..close();
    final right = Path()
      ..moveTo(26, -40)
      ..lineTo(20, -75)
      ..lineTo(5, -43)
      ..close();
    c.drawPath(left, p);
    c.drawPath(right, p);
    if (legendary) {
      c.drawLine(
        const Offset(-20, -70),
        const Offset(-10, -50),
        Paint()
          ..color = dark
          ..strokeWidth = 3,
      );
      c.drawLine(
        const Offset(20, -70),
        const Offset(10, -50),
        Paint()
          ..color = dark
          ..strokeWidth = 3,
      );
    }
  }

  void _wings(Canvas c, Color accent, Color light, Color dark, bool legendary) {
    final wing = Path()
      ..moveTo(-32, 8)
      ..quadraticBezierTo(-78, -10, -62, -54)
      ..quadraticBezierTo(-35, -35, -22, 8)
      ..close();
    final wing2 = Path()
      ..moveTo(32, 8)
      ..quadraticBezierTo(78, -10, 62, -54)
      ..quadraticBezierTo(35, -35, 22, 8)
      ..close();
    final p = Paint()
      ..shader = LinearGradient(
        colors: [light, accent],
      ).createShader(const Rect.fromLTWH(-80, -55, 160, 70));
    c.drawPath(wing, p);
    c.drawPath(wing2, p);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = dark.withValues(alpha: 0.75);
    c.drawPath(wing, outline);
    c.drawPath(wing2, outline);
    if (legendary) {
      c.drawLine(const Offset(-56, -32), const Offset(-35, -3), outline);
      c.drawLine(const Offset(56, -32), const Offset(35, -3), outline);
    }
  }

  void _tail(Canvas c, Color accent, Color light, Color dark, bool legendary) {
    final tail = Path()
      ..moveTo(32, 42)
      ..quadraticBezierTo(76, 72, 60, 18)
      ..quadraticBezierTo(53, 2, 36, 13)
      ..close();
    c.drawPath(
      tail,
      Paint()
        ..shader = LinearGradient(
          colors: [accent, light],
        ).createShader(const Rect.fromLTWH(30, 0, 50, 80)),
    );
    c.drawPath(
      tail,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = dark.withValues(alpha: 0.75),
    );
    if (legendary) {
      c.drawCircle(
        const Offset(62, 20),
        7,
        Paint()..color = Colors.white.withValues(alpha: 0.8),
      );
    }
  }

  void _sparkles(Canvas c, Color accent, bool legendary) {
    final p = Paint()..color = accent.withValues(alpha: 0.9);
    final points = legendary
        ? const [
            Offset(-68, -58),
            Offset(70, -42),
            Offset(-72, 36),
            Offset(70, 52),
          ]
        : const [Offset(-62, -45), Offset(64, -28)];
    for (final point in points) {
      c.drawCircle(point, legendary ? 4 : 3, p);
      c.drawLine(
        point - const Offset(0, 9),
        point + const Offset(0, 9),
        p..strokeWidth = 2,
      );
      c.drawLine(
        point - const Offset(9, 0),
        point + const Offset(9, 0),
        p..strokeWidth = 2,
      );
    }
  }

  void _happySpark(Canvas c, Color light) {
    c.drawCircle(const Offset(-54, -22), 3, Paint()..color = light);
    c.drawCircle(const Offset(54, -18), 3, Paint()..color = light);
  }

  void _moodMark(Canvas c, Color accent) {
    final p = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    c.drawArc(const Rect.fromLTWH(-8, -2, 16, 12), math.pi, math.pi, false, p);
  }

  @override
  bool shouldRepaint(covariant _PetSpritePainter oldDelegate) =>
      oldDelegate.speciesId != speciesId ||
      oldDelegate.stageIndex != stageIndex ||
      oldDelegate.mood != mood ||
      oldDelegate.hatching != hatching;
}
