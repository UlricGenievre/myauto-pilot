import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Anneau de charge façon tableau de bord : arc de progression, niveau en
/// grand au centre, autonomie et etat de charge en dessous.
///
/// Trait et texte suivent [size] (taille de reference 220).
class BatteryGauge extends StatelessWidget {
  const BatteryGauge({
    super.key,
    required this.level,
    this.rangeKm,
    this.isCharging = false,
    this.size = 220,
  });

  /// 0-100, ou null si inconnu (vehicule non connecte / pas de donnee).
  final int? level;
  final int? rangeKm;
  final bool isCharging;
  final double size;

  @override
  Widget build(BuildContext context) {
    final value = (level ?? 0).clamp(0, 100) / 100;
    final color = isCharging ? AppColors.success : AppColors.accent;
    final stroke = (size * 0.075).clamp(10.0, 14.0);
    final levelFontSize = (size * 0.215).clamp(24.0, 44.0);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _GaugePainter(value: value, color: color, strokeWidth: stroke),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCharging) ...[
                Icon(Icons.bolt_rounded, color: AppColors.success, size: size < 200 ? 18 : 22),
                const SizedBox(height: 2),
              ],
              Text(
                level != null ? '$level%' : '--',
                style: TextStyle(fontSize: levelFontSize, fontWeight: FontWeight.w800, height: 1),
              ),
              SizedBox(height: size < 200 ? 4 : 6),
              Text(
                rangeKm != null ? '$rangeKm km' : 'Autonomie inconnue',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w600,
                  fontSize: size < 200 ? 13 : 14,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color, required this.strokeWidth});

  final double value;
  final Color color;
  final double strokeWidth;

  static const _startAngle = -pi / 2 - pi * 0.8;
  static const _sweepMax = pi * 1.6;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - 16) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = AppColors.surfaceHigh
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepMax, false, track);

    if (value > 0) {
      final progress = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, _startAngle, _sweepMax * value, false, progress);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color || oldDelegate.strokeWidth != strokeWidth;
}
