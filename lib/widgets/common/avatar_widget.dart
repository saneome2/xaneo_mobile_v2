import 'package:flutter/material.dart';
import '../../config/app_config.dart';
import '../../styles/app_styles.dart';

/// Виджет для отображения аватара пользователя
/// 
/// Поддерживает:
/// - Загрузку аватара по URL
/// - Градиентный аватар (если нет изображения)
/// - Инициалы пользователя как fallback
class AvatarWidget extends StatelessWidget {
  /// URL аватара
  final String? avatar;
  
  /// Градиент аватара (если нет изображения)
  final String? avatarGradient;
  
  /// Есть ли у пользователя аватар
  final bool hasAvatar;
  
  /// Имя пользователя для инициалов
  final String username;
  
  /// Размер аватара
  final double size;
  
  /// Радиус скругления (по умолчанию size / 2 - круглый)
  final double? borderRadius;

  const AvatarWidget({
    super.key,
    this.avatar,
    this.avatarGradient,
    this.hasAvatar = false,
    required this.username,
    this.size = 48,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? size / 2;
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: hasAvatar && avatar != null
            ? null
            : _parseGradient(avatarGradient),
        color: hasAvatar || avatarGradient != null
            ? null
            : Colors.grey.withOpacity(0.3),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
        image: hasAvatar && avatar != null
            ? DecorationImage(
                image: NetworkImage(
                  '${AppConfig.apiBaseUrl}${avatar!.startsWith('/') ? '' : '/'}$avatar',
                ),
                fit: BoxFit.cover,
              )
            : null,
      ),
      child: !hasAvatar || avatar == null
          ? Center(
              child: Text(
                _getInitials(),
                style: TextStyle(
                  color: Colors.white,
                  fontSize: size * 0.4,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : null,
    );
  }

  /// Получить инициалы из имени пользователя
  String _getInitials() {
    if (username.isEmpty) return '?';
    
    // Если username начинается с @, убираем его
    final name = username.startsWith('@') ? username.substring(1) : username;
    
    if (name.isEmpty) return '?';
    
    // Берём первую букву
    return name[0].toUpperCase();
  }

  /// Парсит градиент из строки
  /// 
  /// Формат: "color1,color2" или "color1,color2,color3"
  /// Цвета в формате hex: "#RRGGBB" или "RRGGBB"
  LinearGradient? _parseGradient(String? gradient) {
    if (gradient == null || gradient.isEmpty) return null;

    try {
      final parts = gradient.split(',');
      if (parts.isEmpty) return null;

      final colors = parts.map((part) {
        var colorStr = part.trim();
        if (colorStr.startsWith('#')) {
          colorStr = colorStr.substring(1);
        }
        return Color(int.parse('FF$colorStr', radix: 16));
      }).toList();

      if (colors.length == 1) {
        return LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors[0], colors[0]],
        );
      }

      return LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      );
    } catch (e) {
      return null;
    }
  }
}
