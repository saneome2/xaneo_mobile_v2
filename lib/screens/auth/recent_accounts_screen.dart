import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/auth/recent_account.dart';
import '../../providers/auth_provider.dart';
import '../../services/auth/recent_accounts_service.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/avatar_widget.dart';
import 'login_screen.dart';
import 'tfa_screen.dart';

/// Экран выбора недавнего аккаунта для быстрого входа
/// 
/// Отображает список аккаунтов, в которые ранее входили на этом устройстве.
/// Позволяет быстро войти в аккаунт без ввода пароля.
class RecentAccountsScreen extends StatefulWidget {
  const RecentAccountsScreen({super.key});

  @override
  State<RecentAccountsScreen> createState() => _RecentAccountsScreenState();
}

class _RecentAccountsScreenState extends State<RecentAccountsScreen> {
  List<RecentAccount> _accounts = [];
  bool _isLoading = true;
  String? _error;
  int? _selectedAccountId;

  @override
  void initState() {
    super.initState();
    _loadRecentAccounts();
  }

  Future<void> _loadRecentAccounts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      final response = await authProvider.getRecentAccounts();

      if (mounted) {
        setState(() {
          if (response.success) {
            _accounts = response.recentAccounts;
          } else {
            _error = response.error ?? 'Не удалось загрузить аккаунты';
          }
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onAccountTap(RecentAccount account) async {
    setState(() => _selectedAccountId = account.id);

    try {
      final authProvider = context.read<AuthProvider>();
      final success = await authProvider.quickLogin(userId: account.id);

      if (!mounted) return;

      if (authProvider.requiresTfa) {
        // Требуется 2FA
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => TfaScreen(
              userId: account.id,
              username: account.username,
            ),
          ),
        );
      } else if (success) {
        // Успешный вход - навигация обрабатывается AuthWrapper
      } else if (authProvider.error != null) {
        _showError(authProvider.error!.message);
        setState(() => _selectedAccountId = null);
      }
    } catch (e) {
      if (mounted) {
        _showError(e.toString());
        setState(() => _selectedAccountId = null);
      }
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: AppStyles.bodyMedium.copyWith(color: Colors.white),
        ),
        backgroundColor: AppStyles.errorColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _goToLogin() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
            onPressed: () {
              // TODO: Открыть настройки
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 60,
                  width: 60,
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.bubble_chart,
                    color: Colors.white,
                    size: 60,
                  ),
                ),
              ),
              const Spacer(flex: 1),
              const Text(
                'Выберите аккаунт',
                style: AppStyles.titleGiant,
              ),
              const SizedBox(height: 8),
              const Text(
                'Быстрый вход на этом устройстве',
                style: AppStyles.bodyMuted,
              ),
              const SizedBox(height: 32),
              _buildContent(),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _goToLogin,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.buttonBackgroundColor,
                    disabledBackgroundColor: Colors.white24,
                    foregroundColor: AppStyles.buttonTextColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    elevation: 0,
                  ),
                  child: const Text('Войти с паролем', style: AppStyles.buttonText),
                ),
              ),
              const SizedBox(height: 16),
              Center(
                child: TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          // TODO: Переход к регистрации
                          Navigator.of(context).pushReplacement(
                            MaterialPageRoute(
                              builder: (_) => const LoginScreen(),
                            ),
                          );
                        },
                  child: Text(
                    'Создать Xaneo ID',
                    style: AppStyles.bodyMedium.copyWith(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: CircularProgressIndicator(color: Colors.white),
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              Text(
                'Не удалось загрузить аккаунты',
                style: AppStyles.bodyMedium,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: _loadRecentAccounts,
                child: const Text('Повторить'),
              ),
            ],
          ),
        ),
      );
    }

    if (_accounts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'Нет сохранённых аккаунтов',
            style: AppStyles.bodyMuted,
          ),
        ),
      );
    }

    return Expanded(
      child: ListView.builder(
        itemCount: _accounts.length,
        itemBuilder: (context, index) {
          final account = _accounts[index];
          final isSelected = _selectedAccountId == account.id;
          final isLoading = isSelected && context.watch<AuthProvider>().isLoading;

          return _AccountCard(
            account: account,
            isLoading: isLoading,
            onTap: () => _onAccountTap(account),
          );
        },
      ),
    );
  }
}

/// Карточка аккаунта для быстрого входа
class _AccountCard extends StatelessWidget {
  final RecentAccount account;
  final bool isLoading;
  final VoidCallback onTap;

  const _AccountCard({
    required this.account,
    required this.isLoading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                // Аватар
                AvatarWidget(
                  avatar: account.avatar,
                  avatarGradient: account.avatarGradient,
                  hasAvatar: account.hasAvatar,
                  username: account.username,
                  size: 48,
                ),
                const SizedBox(width: 16),
                // Информация об аккаунте
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '@${account.username}',
                        style: AppStyles.bodyMedium.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _formatLastLogin(account.lastLogin),
                        style: AppStyles.bodyMuted.copyWith(
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                // Индикатор загрузки или стрелка
                if (isLoading)
                  const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  )
                else
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white54,
                    size: 16,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatLastLogin(DateTime lastLogin) {
    final now = DateTime.now();
    final difference = now.difference(lastLogin);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return 'Только что';
        }
        return '${difference.inMinutes} мин. назад';
      }
      return '${difference.inHours} ч. назад';
    } else if (difference.inDays == 1) {
      return 'Вчера';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} дн. назад';
    } else {
      return '${lastLogin.day}.${lastLogin.month}.${lastLogin.year}';
    }
  }
}
