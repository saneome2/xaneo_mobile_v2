import 'package:flutter/material.dart';
import 'dart:math' as math;

/// Кастомный волновой слайдер для голосовых сообщений.
/// 
/// Отображает форму волны (waveform) с возможностью перемотки по тапу или драгу.
/// Прогресс воспроизведения показывается цветом волн.
class VoiceWaveformSlider extends StatefulWidget {
  final Duration position;
  final Duration duration;
  final bool isActive;

  /// Финальный seek — вызывается ОДИН раз, когда палец отпущен
  /// (onTapUp / onHorizontalDragEnd). Это "тяжёлый" сик с пересозданием
  /// AudioSource, поэтому дёргать его на каждое движение нельзя.
  final ValueChanged<Duration>? onSeek;

  /// Лёгкое превью позиции во время драга (onHorizontalDragUpdate).
  /// Вызывается на каждое движение пальца — должно быть дешёвым
  /// (просто обновление UI), без пересоздания плеера.
  /// Если не задан, во время драга ничего не происходит до отпускания.
  final ValueChanged<Duration>? onSeekPreview;

  final Color activeColor;
  final Color inactiveColor;
  final List<double>? waveformData;
  final int barsCount;

  const VoiceWaveformSlider({
    super.key,
    required this.position,
    required this.duration,
    required this.isActive,
    this.onSeek,
    this.onSeekPreview,
    required this.activeColor,
    required this.inactiveColor,
    this.waveformData,
    this.barsCount = 40,
  });

  @override
  State<VoiceWaveformSlider> createState() => _VoiceWaveformSliderState();
}

class _VoiceWaveformSliderState extends State<VoiceWaveformSlider> {
  late List<double> _bars;
  bool _isDragging = false;
  // Последняя позиция пальца во время драга — нужна, чтобы на
  // onHorizontalDragEnd (где нет localPosition) сделать финальный seek
  // в ту же точку, где остановился палец.
  Offset? _lastDragLocalPosition;

  @override
  void initState() {
    super.initState();
    _generateBars();
  }

  void _generateBars() {
    if (widget.waveformData != null && widget.waveformData!.isNotEmpty) {
      _bars = widget.waveformData!;
    } else {
      // Генерируем псевдо-случайные амплитуды для красивой волны
      final random = math.Random(42); // Seed для стабильности
      _bars = List.generate(widget.barsCount, (index) {
        // Создаём волну с вариациями
        final base = (math.sin(index * 0.3) + 1) / 2; // 0.0 - 1.0
        final noise = random.nextDouble() * 0.4; // Добавляем шум
        return (base * 0.6 + noise).clamp(0.2, 1.0);
      });
    }
  }

  void _handleInteraction(Offset localPosition, double width, {required bool isFinal}) {
    if (!widget.isActive) return;

    final progress = (localPosition.dx / width).clamp(0.0, 1.0);
    final newPositionMs = widget.duration.inMilliseconds * progress;
    final newPosition = Duration(milliseconds: newPositionMs.toInt());

    if (isFinal) {
      if (widget.onSeek == null) return;
      widget.onSeek!(newPosition);
    } else {
      // Превью во время драга: если onSeekPreview не задан, тихо выходим
      // (но onTapDown/onHorizontalDragEnd всё равно отработают финальный seek)
      if (widget.onSeekPreview == null) return;
      widget.onSeekPreview!(newPosition);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: LayoutBuilder(
        builder: (context, constraints) {
          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            // Добавляем excludeFromSemantics, чтобы не блокировать родительский скролл
            excludeFromSemantics: false,
            onTapDown: (details) {
              _isDragging = true;
              setState(() {});
              // Тап — это сразу финальная позиция, не превью
              _handleInteraction(details.localPosition, constraints.maxWidth, isFinal: true);
            },
            onTapUp: (details) {
              _isDragging = false;
              setState(() {});
            },
            onHorizontalDragStart: (details) {
              _isDragging = true;
              _lastDragLocalPosition = details.localPosition;
              setState(() {});
            },
            onHorizontalDragUpdate: (details) {
              _lastDragLocalPosition = details.localPosition;
              // Дешёвое превью на каждое движение пальца — не трогает плеер
              _handleInteraction(details.localPosition, constraints.maxWidth, isFinal: false);
            },
            onHorizontalDragEnd: (details) {
              _isDragging = false;
              setState(() {});
              // Тяжёлый seek делаем один раз, по факту отпускания пальца
              if (_lastDragLocalPosition != null) {
                _handleInteraction(_lastDragLocalPosition!, constraints.maxWidth, isFinal: true);
                _lastDragLocalPosition = null;
              }
            },
            child: Container(
              height: 32,
              color: Colors.transparent,
              child: CustomPaint(
                painter: _WaveformPainter(
                  bars: _bars,
                  progress: widget.duration.inMilliseconds > 0
                      ? widget.position.inMilliseconds / widget.duration.inMilliseconds
                      : 0.0,
                  activeColor: widget.activeColor,
                  inactiveColor: widget.inactiveColor,
                  isDragging: _isDragging,
                ),
                size: Size.infinite,
              ),
            ),
          );
        },
      ),
    );
  }
}

class _WaveformPainter extends CustomPainter {
  final List<double> bars;
  final double progress;
  final Color activeColor;
  final Color inactiveColor;
  final bool isDragging;

  _WaveformPainter({
    required this.bars,
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
    required this.isDragging,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (bars.isEmpty) return;

    final barWidth = 2.0;
    final barSpacing = 1.5;
    final totalBarWidth = barWidth + barSpacing;
    final maxBars = (size.width / totalBarWidth).floor();
    final barsToShow = math.min(bars.length, maxBars);
    final actualWidth = barsToShow * totalBarWidth - barSpacing;
    final startX = (size.width - actualWidth) / 2;

    final activePaint = Paint()
      ..color = activeColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..strokeWidth = barWidth
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < barsToShow; i++) {
      final barIndex = (i * bars.length / barsToShow).floor();
      final amplitude = bars[barIndex];
      final barHeight = size.height * amplitude * 0.8;
      final x = startX + i * totalBarWidth;
      final centerY = size.height / 2;

      final barProgress = i / barsToShow;
      final paint = barProgress <= progress ? activePaint : inactivePaint;

      // Рисуем столбик волны
      canvas.drawLine(
        Offset(x, centerY - barHeight / 2),
        Offset(x, centerY + barHeight / 2),
        paint,
      );
    }

    // Если драгается, показываем индикатор текущей позиции
    if (isDragging || progress > 0) {
      final cursorX = startX + (actualWidth * progress);
      final cursorPaint = Paint()
        ..color = activeColor
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(
        Offset(cursorX, size.height / 2),
        3.5,
        cursorPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.isDragging != isDragging ||
        oldDelegate.bars != bars ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
