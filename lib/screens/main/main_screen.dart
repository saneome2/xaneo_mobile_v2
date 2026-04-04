import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/auth/user_model.dart';
import '../../providers/auth_provider.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/liquid_glass_nav_bar.dart';
import '../auth/login_screen.dart';
import '../chat/chat_list_screen.dart';

/// Главный экран приложения (после авторизации)
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;

    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      body: Stack(
        children: [
          // Анимация скольжения экранов
          PageView(
            controller: _pageController,
            physics: const NeverScrollableScrollPhysics(), // Блокируем свайп руками для точной синхронизации с панелью
            children: [
              const ChatListScreen(key: ValueKey('chats')),
              _buildContactsScreen(key: const ValueKey('contacts')),
              _buildSettingsScreen(user, key: const ValueKey('settings')),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidGlassNavBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                if (_currentIndex != index) {
                  setState(() {
                    _currentIndex = index;
                  });
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOutCubic,
                  );
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsScreen({Key? key}) {
    return SafeArea(
      key: key,
      child: Column(
        children: [
          // Заголовок
          Padding(
            padding: AppStyles.screenPadding.copyWith(top: 16),
            child: Row(
              children: [
                Text('Контакты', style: AppStyles.titleLarge),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.person_add, color: AppStyles.textPrimaryColor),
                  onPressed: () {
                    // TODO: Добавить контакт
                  },
                ),
              ],
            ),
          ),

          // Список контактов (заглушка)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.people_outline,
                    size: 64,
                    color: AppStyles.textMutedColor,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Нет контактов',
                    style: AppStyles.titleLarge.copyWith(
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

  Widget _buildSettingsScreen(UserModel? user, {Key? key}) {
    return SafeArea(
      key: key,
      child: ListView(
        physics: const ClampingScrollPhysics(), // Запрещает прокрутку за границы
        padding: const EdgeInsets.only(top: 60, bottom: 100),
        children: [
          // Профиль
          if (user != null) ...[
            _buildProfileCard(user),
            const SizedBox(height: 40),
          ],

          // Секция аккаунта
          _buildSection('Аккаунт', [
            _buildItem(
              icon: Icons.lock_outline,
              title: 'Безопасность',
              subtitle: 'Пароль, 2FA',
              onTap: () {},
            ),
            _buildItem(
              icon: Icons.notifications_outlined,
              title: 'Уведомления',
              subtitle: 'Push, звуки',
              onTap: () {},
            ),
            _buildItem(
              icon: Icons.privacy_tip_outlined,
              title: 'Приватность',
              subtitle: 'Данные, контакты',
              isLast: true,
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 24),

          // Секция приложения
          _buildSection('Приложение', [
            _buildItem(
              icon: Icons.dark_mode_outlined,
              title: 'Тема',
              subtitle: 'Тёмная',
              onTap: () {},
            ),
            _buildItem(
              icon: Icons.translate,
              title: 'Язык',
              subtitle: 'Русский',
              onTap: () {},
            ),
            _buildItem(
              icon: Icons.storage_outlined,
              title: 'Хранилище',
              subtitle: 'Кэш, данные',
              isLast: true,
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 24),

          // Секция поддержки
          _buildSection('Поддержка', [
            _buildItem(
              icon: Icons.help_outline,
              title: 'Справка',
              onTap: () {},
            ),
            _buildItem(
              icon: Icons.info_outline,
              title: 'О приложении',
              subtitle: 'Версия 2.0.0',
              isLast: true,
              onTap: () {},
            ),
          ]),

          const SizedBox(height: 40),

          // Кнопка выхода
          _buildLogoutButton(),
        ],
      ),
    );
  }

  /// Карточка профиля
  Widget _buildProfileCard(UserModel user) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          children: [
            // Аватар
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(40),
              ),
              child: Center(
                child: Text(
                  user.username[0].toUpperCase(),
                  style: const TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w300,
                    color: Colors.black,
                    fontFamily: 'Inter',
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Имя
            Text(
              user.username,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 4),

            // Email
            Text(
              user.email,
              style: const TextStyle(
                fontSize: 14,
                color: Color(0xFF888888),
                fontFamily: 'Inter',
              ),
            ),
            const SizedBox(height: 20),

            // Кнопка редактирования
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Редактировать профиль',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: Colors.white,
                  fontFamily: 'Inter',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Секция настроек
  Widget _buildSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Заголовок секции
        Padding(
          padding: const EdgeInsets.only(left: 24, bottom: 10),
          child: Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Color(0xFF666666),
              fontFamily: 'Inter',
              letterSpacing: 1.5,
            ),
          ),
        ),

        // Карточка с элементами (без фона)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(children: children),
          ),
        ),
      ],
    );
  }

  /// Элемент настройки
  Widget _buildItem({
    required IconData icon,
    required String title,
    String? subtitle,
    bool isLast = false,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.vertical(
          bottom: isLast ? const Radius.circular(16) : Radius.zero,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            border: isLast
                ? null
                : const Border(
                    bottom: BorderSide(
                      color: Color(0xFF2A2A2A),
                      width: 1,
                    ),
                  ),
          ),
          child: Row(
            children: [
              // Иконка
              Icon(
                icon,
                color: const Color(0xFFAAAAAA),
                size: 20,
              ),
              const SizedBox(width: 14),

              // Название и подзаголовок
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF666666),
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // Chevron
              const Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFF444444),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Кнопка выхода
  Widget _buildLogoutButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: GestureDetector(
        onTap: () async {
          await context.read<AuthProvider>().logout();
          if (context.mounted) {
            Navigator.of(context).pushReplacement(
              MaterialPageRoute(builder: (_) => const LoginScreen()),
            );
          }
        },
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Center(
            child: Text(
              'Выйти из аккаунта',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Color(0xFF888888),
                fontFamily: 'Inter',
              ),
            ),
          ),
        ),
      ),
    );
  }
}
