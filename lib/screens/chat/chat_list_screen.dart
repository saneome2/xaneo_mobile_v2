import 'package:flutter/material.dart';
import '../../styles/app_styles.dart';

class ChatListScreen extends StatelessWidget {
  const ChatListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          // Заголовок
          Padding(
            padding: AppStyles.screenPadding.copyWith(top: 16),
            child: Row(
              children: [
                Text('Чаты', style: AppStyles.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.search, color: AppStyles.textPrimaryColor),
                  onPressed: () {
                    // TODO: Поиск
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.add, color: AppStyles.textPrimaryColor),
                  onPressed: () {
                    // TODO: Новый чат
                  },
                ),
              ],
            ),
          ),
          
          // Список чатов (заглушка)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.chat_bubble_outline,
                    size: 64,
                    color: AppStyles.textMutedColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет чатов',
                    style: AppStyles.titleLarge.copyWith(
                      color: AppStyles.textMutedColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Начните новый разговор',
                    style: AppStyles.bodyMedium.copyWith(
                      color: AppStyles.textMutedColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
