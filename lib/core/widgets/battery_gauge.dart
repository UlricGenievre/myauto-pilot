import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Anneau de charge façon tableau de bord : arc de progression, niveau en
/// grand au centre, autonomie et etat de charge en dessous.
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

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _GaugePainter(value: value, color: color),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isCharging) ...[
                const Icon(Icons.bolt_rounded, color: AppColors.success, size: 22),
                const SizedBox(height: 2),
              ],
              Text(
                level != null ? '$level%' : '--',
                style: const TextStyle(fontSize: 44, fontWeight: FontWeight.w800, height: 1),
              ),
              const SizedBox(height: 6),
              Text(
                rangeKm != null ? '$rangeKm km' : 'Autonomie inconnue',
                style: const TextStyle(color: AppColors.textSecondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  _GaugePainter({required this.value, required this.color});

  final double value;
  final Color color;

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
      ..strokeWidth = 14
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _startAngle, _sweepMax, false, track);

    if (value > 0) {
      final progress = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 14
        ..strokeCap = StrokeCap.round;
      canvas.drawArc(rect, _startAngle, _sweepMax * value, false, progress);
    }
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) =>
      oldDelegate.value != value || oldDelegate.color != color;
}
