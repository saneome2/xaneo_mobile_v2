import 'package:flutter/material.dart';
import '../../styles/app_styles.dart';

class AuthSettingsModal extends StatefulWidget {
  const AuthSettingsModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => const AuthSettingsModal(),
    );
  }

  @override
  State<AuthSettingsModal> createState() => _AuthSettingsModalState();
}

class _AuthSettingsModalState extends State<AuthSettingsModal> {
  final String _appVersion = '2.0.0+1'; // Hardcoded for now
  
  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF161616),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Настройки', style: AppStyles.titleLarge),
            const SizedBox(height: 24),
            
            _buildSettingItem(
              icon: Icons.dark_mode_outlined,
              title: 'Темная тема',
              subtitle: 'Включена (по умолчанию)',
              trailing: const Icon(Icons.check, color: Colors.white),
            ),
            const Divider(color: Colors.white10),
            
            _buildSettingItem(
              icon: Icons.language,
              title: 'Язык',
              subtitle: 'Русский',
            ),
            const Divider(color: Colors.white10),
            
            _buildSettingItem(
              icon: Icons.security,
              title: 'Сетевой фильтр',
              subtitle: 'Включен',
            ),
            
            const SizedBox(height: 32),
            Center(
              child: Text(
                'Xaneo v\$_appVersion',
                style: AppStyles.bodyMuted.copyWith(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: Colors.white70),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppStyles.bodyMedium.copyWith(color: Colors.white)),
                Text(subtitle, style: AppStyles.bodyMuted.copyWith(fontSize: 13)),
              ],
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }
}
