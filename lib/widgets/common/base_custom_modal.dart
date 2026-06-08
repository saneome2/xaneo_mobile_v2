import 'package:flutter/material.dart';

/// Базовый класс для кастомных модальных окон (Bottom Sheet).
/// Реализует общий дизайн, скругленные углы, индикатор перетаскивания (drag handle),
/// кнопку закрытия и плавное пролистывание.
abstract class BaseCustomModal extends StatefulWidget {
  const BaseCustomModal({super.key});
}

abstract class BaseCustomModalState<T extends BaseCustomModal> extends State<T> {
  /// Высота модалки при открытии (в процентах от высоты экрана: 0.0 - 1.0)
  double get initialExtent => 0.65;

  /// Минимальная высота модалки при сворачивании
  double get minExtent => 0.35;

  /// Максимальная высота модалки при полном развертывании
  double get maxExtent => 0.95;

  /// Цвет фона модалки
  Color get backgroundColor => const Color(0xFF141416);

  /// Метод для отрисовки содержимого. Должен быть переопределен в наследниках.
  /// Передаваемый [scrollController] должен быть привязан к ListView/SingleChildScrollView
  /// внутри контента для правильной работы перетаскивания модалки.
  Widget buildContent(BuildContext context, ScrollController scrollController);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: initialExtent,
      minChildSize: minExtent,
      maxChildSize: maxExtent,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            border: Border(
              top: BorderSide(
                color: Colors.white.withOpacity(0.08),
                width: 1.5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 25,
                spreadRadius: 2,
                offset: const Offset(0, -4),
              )
            ],
          ),
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
            child: Stack(
              children: [
                // Основной контент
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      children: [
                        const SizedBox(height: 12),
                        // Индикатор перетаскивания (Drag Handle)
                        Center(
                          child: Container(
                            width: 36,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Контент наследника
                        Expanded(
                          child: buildContent(context, scrollController),
                        ),
                      ],
                    ),
                  ),
                ),
                // Премиальная кнопка закрытия в углу
                Positioned(
                  top: 16,
                  right: 16,
                  child: Material(
                    color: Colors.white.withOpacity(0.05),
                    shape: const CircleBorder(),
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      customBorder: const CircleBorder(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withOpacity(0.05),
                            width: 1,
                          ),
                        ),
                        child: const Icon(
                          Icons.close_rounded,
                          color: Colors.white70,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
