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
  
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      body: Stack(
        children: [
          IndexedStack(
            index: _currentIndex,
            children: [
              const ChatListScreen(), // Use updated actual chat screen
              _buildContactsScreen(),
              _buildSettingsScreen(user),
            ],
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LiquidGlassNavBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactsScreen() {
    return SafeArea(
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

  Widget _buildSettingsScreen(UserModel? user) {
    return SafeArea(
      child: ListView(
        padding: AppStyles.screenPadding.copyWith(top: 16),
        children: [
          // Заголовок
          Text('Настройки', style: AppStyles.titleLarge),
          const SizedBox(height: 24),
          
          // Профиль
          if (user != null) ...[
            _buildProfileCard(user),
            const SizedBox(height: 24),
          ],
          
          // Настройки аккаунта
          _buildSettingsSection('Аккаунт', [
            _buildSettingsItem(
              icon: Icons.lock_outline,
              title: 'Безопасность',
              subtitle: 'Пароль, 2FA',
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.notifications_outlined,
              title: 'Уведомления',
              subtitle: 'Настройки уведомлений',
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.privacy_tip_outlined,
              title: 'Приватность',
              subtitle: 'Настройки приватности',
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 16),
          
          // Настройки приложения
          _buildSettingsSection('Приложение', [
            _buildSettingsItem(
              icon: Icons.palette_outlined,
              title: 'Тема',
              subtitle: 'Тёмная',
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.language,
              title: 'Язык',
              subtitle: 'Русский',
              onTap: () {},
            ),
            _buildSettingsItem(
              icon: Icons.storage_outlined,
              title: 'Данные',
              subtitle: 'Кэш, хранилище',
              onTap: () {},
            ),
          ]),
          const SizedBox(height: 24),
          
          // Выход
          SizedBox(
            height: 50,
            child: OutlinedButton(
              onPressed: () async {
                await context.read<AuthProvider>().logout();
                if (context.mounted) {
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (_) => const LoginScreen()),
                  );
                }
              },
              style: AppStyles.secondaryButton.copyWith(
                foregroundColor: WidgetStateProperty.all(AppStyles.errorColor),
                side: WidgetStateProperty.all(
                  const BorderSide(color: AppStyles.errorColor, width: 1),
                ),
              ),
              child: const Text('Выйти'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfileCard(UserModel user) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppStyles.inputBackgroundColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppStyles.borderColor, width: 1),
      ),
      child: Row(
        children: [
          // Аватар
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: AppStyles.textPrimaryColor,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Center(
              child: Text(
                user.username[0].toUpperCase(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppStyles.backgroundColor,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          
          // Информация
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user.username, style: AppStyles.titleLarge.copyWith(fontSize: 20)),
                const SizedBox(height: 4),
                Text(user.email, style: AppStyles.bodyMedium),
              ],
            ),
          ),
          
          // Редактировать
          IconButton(
            icon: const Icon(Icons.edit_outlined, color: AppStyles.textMutedColor),
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  Widget _buildSettingsSection(String title, List<Widget> children) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            title,
            style: AppStyles.bodyMedium.copyWith(color: AppStyles.textMutedColor),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: AppStyles.inputBackgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppStyles.borderColor, width: 1),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildSettingsItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: AppStyles.textPrimaryColor),
      title: Text(title, style: AppStyles.inputText),
      subtitle: Text(subtitle, style: AppStyles.bodyMedium),
      trailing: const Icon(Icons.chevron_right, color: AppStyles.textMutedColor),
      onTap: onTap,
    );
  }
}
