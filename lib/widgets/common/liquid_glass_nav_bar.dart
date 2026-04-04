import 'dart:ui';
import 'package:flutter/material.dart';
import '../../styles/app_styles.dart';

/// Навигационная панель с эффектом "Liquid Glass"
///
/// Особенности:
/// - Закруглённый прямоугольник с blur эффектом
/// - Иконки Font Awesome
/// - Плавная анимация индикатора при переключении
/// - Glassmorphism эффект
class LiquidGlassNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  const LiquidGlassNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.only(left: 32, right: 32, bottom: 16),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(32),
            border: Border.all(
              color: Colors.white.withOpacity(0.15),
              width: 1,
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(32),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.transparent,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final itemWidth = (constraints.maxWidth - 16) / 3;
                    return Stack(
                      children: [
                        // Анимированный индикатор (прозрачная "штуковина" - pill)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: AnimatedAlign(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            alignment: _getAlignment(selectedIndex),
                            child: Container(
                              width: itemWidth - 8,
                              height: 40,
                              margin: const EdgeInsets.only(top: 8, bottom: 8),
                              decoration: BoxDecoration(
                                color: Colors.white.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                          ),
                        ),
                        // Кнопки навигации
                        Row(
                          children: [
                            Expanded(
                              child: _NavItem(
                                icon: Icons.chat_bubble_rounded,
                                label: 'Чаты',
                                isSelected: selectedIndex == 0,
                                onTap: () => onDestinationSelected(0),
                              ),
                            ),
                            Expanded(
                              child: _NavItem(
                                icon: Icons.people_alt_rounded,
                                label: 'Контакты',
                                isSelected: selectedIndex == 1,
                                onTap: () => onDestinationSelected(1),
                              ),
                            ),
                            Expanded(
                              child: _NavItem(
                                icon: Icons.settings_rounded,
                                label: 'Настройки',
                                isSelected: selectedIndex == 2,
                                onTap: () => onDestinationSelected(2),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Получить выравнивание для индикатора в зависимости от индекса
  Alignment _getAlignment(int index) {
    switch (index) {
      case 0:
        return Alignment.centerLeft;
      case 1:
        return Alignment.center;
      case 2:
        return Alignment.centerRight;
      default:
        return Alignment.centerLeft;
    }
  }
}

/// Элемент навигационной панели
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Icon(
                icon,
                size: isSelected ? 24 : 22,
                color: isSelected
                    ? AppStyles.textPrimaryColor
                    : AppStyles.textMutedColor,
              ),
            ),
            const SizedBox(height: 2),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              style: TextStyle(
                fontSize: isSelected ? 10 : 9,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected
                    ? AppStyles.textPrimaryColor
                    : AppStyles.textMutedColor,
                fontFamily: AppStyles.fontFamily,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
