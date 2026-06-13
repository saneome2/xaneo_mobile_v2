import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../models/auth/recent_account.dart';
import '../../providers/auth_provider.dart';
import '../../screens/main/main_screen.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/auth_settings_modal.dart';
import '../../widgets/common/avatar_widget.dart';
import 'recent_accounts_screen.dart';
import 'register_screen.dart';
import 'tfa_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with SingleTickerProviderStateMixin {
  int _currentStep = 0; // 0: Username, 1: Password

  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();

  bool _isUsernameValid = false;
  bool _isPasswordValid = false;
  bool _obscurePassword = true;
  
  // Недавние аккаунты
  List<RecentAccount> _recentAccounts = [];
  bool _isLoadingRecentAccounts = true;
  bool _showRecentAccounts = true;

  @override
  void initState() {
    super.initState();
    _usernameController.addListener(_onUsernameChanged);
    _passwordController.addListener(_onPasswordChanged);
    
    // Загружаем недавние аккаунты
    _loadRecentAccounts();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(AppStyles.animationFast, () {
        if (mounted && _currentStep == 0) _usernameFocusNode.requestFocus();
      });
    });
  }
  
  Future<void> _loadRecentAccounts() async {
    try {
      final auth = context.read<AuthProvider>();
      final response = await auth.getRecentAccounts();
      
      if (mounted) {
        setState(() {
          if (response.success) {
            _recentAccounts = response.recentAccounts;
          }
          _isLoadingRecentAccounts = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingRecentAccounts = false);
      }
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _usernameFocusNode.dispose();
    _passwordFocusNode.dispose();
    super.dispose();
  }

  void _onUsernameChanged() {
    final username = _usernameController.text.trim();
    setState(() {
      _isUsernameValid = username.length >= AppConfig.minUsernameLength;
    });
  }

  void _onPasswordChanged() {
    setState(() {
      _isPasswordValid = _passwordController.text.isNotEmpty;
    });
  }

  void _goToNextStep() {
    if (_currentStep == 0 && _isUsernameValid) {
      setState(() => _currentStep = 1);
      _passwordFocusNode.requestFocus();
    } else if (_currentStep == 1 && _isPasswordValid) {
      _handleLogin();
    }
  }

  void _goBack() {
    if (_currentStep == 1) {
      setState(() => _currentStep = 0);
      _usernameFocusNode.requestFocus();
    }
  }
  
  /// Быстрый вход по недавнему аккаунту
  Future<void> _handleQuickLogin(RecentAccount account) async {
    final auth = context.read<AuthProvider>();
    final success = await auth.quickLogin(userId: account.id);

    if (!mounted) return;

    if (auth.requiresTfa) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => TfaScreen(
            userId: account.id,
            username: account.username,
          ),
        ),
      );
    } else if (success) {
      // Навигация обрабатывается AuthWrapper
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            auth.error!.message,
            style: AppStyles.bodyMedium.copyWith(color: Colors.white),
          ),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleLogin() async {
    final auth = context.read<AuthProvider>();
    final success = await auth.login(
      username: _usernameController.text.trim(),
      password: _passwordController.text,
    );
    
    if (!mounted) return;
    
    if (auth.requiresTfa) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const TfaScreen()),
      );
    } else if (success) {
    // Переходим на главный экран
    if (mounted) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const MainScreen()),
      );
    }
  } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!.message, style: AppStyles.bodyMedium.copyWith(color: Colors.white)),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        )
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;
    final showRecentOnly = _currentStep == 0 && _showRecentAccounts && (_isLoadingRecentAccounts || _recentAccounts.isNotEmpty);
    
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep == 1 
          ? IconButton(
              icon: const FaIcon(FontAwesomeIcons.chevronLeft, color: Colors.white, size: 18),
              onPressed: isLoading ? null : _goBack,
            )
          : null,
        actions: [
          IconButton(
            icon: const FaIcon(FontAwesomeIcons.gear, color: Colors.white70, size: 18),
            onPressed: () => AuthSettingsModal.show(context),
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
                  errorBuilder: (context, error, stackTrace) => const Center(child: FaIcon(FontAwesomeIcons.comments, color: Colors.white, size: 50)),
                ),
              ),
              const Spacer(flex: 1),
              AnimatedSwitcher(
                duration: AppStyles.animationMedium,
                switchInCurve: AppStyles.curveEaseOut,
                switchOutCurve: AppStyles.curveEaseIn,
                transitionBuilder: (Widget child, Animation<double> animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.0, 0.1),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _currentStep == 0 
                  ? _buildUsernameStep(key: const ValueKey('step0'), showRecentOnly: showRecentOnly)
                  : _buildPasswordStep(key: const ValueKey('step1')),
              ),
              const SizedBox(height: 32),
              if (!showRecentOnly) _buildProgressIndicator(),
              const Spacer(flex: 2),
              
              if (!showRecentOnly) ...[
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: isLoading 
                      ? null 
                      : ((_currentStep == 0 && _isUsernameValid) || (_currentStep == 1 && _isPasswordValid))
                          ? _goToNextStep
                          : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppStyles.buttonBackgroundColor,
                      disabledBackgroundColor: Colors.white24,
                      foregroundColor: AppStyles.buttonTextColor,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: isLoading 
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Text(_currentStep == 0 ? 'Далее' : 'Войти', style: AppStyles.buttonText),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              
              if (_currentStep == 0)
                Center(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).push(
                        PageRouteBuilder(
                          pageBuilder: (context, anim, secAnim) => const RegisterScreen(),
                          transitionsBuilder: (c, anim, secAnim, child) => FadeTransition(opacity: anim, child: child),
                          transitionDuration: AppStyles.animationMedium,
                        )
                      );
                    },
                    child: Text('Создать Xaneo ID', style: AppStyles.bodyMedium.copyWith(color: Colors.white)),
                  ),
                ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUsernameStep({Key? key, required bool showRecentOnly}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('С возвращением', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        Text(
          showRecentOnly 
            ? (_isLoadingRecentAccounts ? 'Загрузка...' : 'Выберите аккаунт для входа') 
            : 'Введите ваш никнейм', 
          style: AppStyles.bodyMuted
        ),
        const SizedBox(height: 32),
        
        if (showRecentOnly) ...[
          _buildRecentAccounts(),
          if (!_isLoadingRecentAccounts) ...[
            const SizedBox(height: 32),
            Center(
              child: TextButton(
                onPressed: () {
                  setState(() {
                    _showRecentAccounts = false;
                  });
                  Future.delayed(AppStyles.animationFast, () {
                    if (mounted) _usernameFocusNode.requestFocus();
                  });
                },
                child: Text('Войти в другой аккаунт', style: AppStyles.bodyMedium.copyWith(color: Colors.white)),
              ),
            ),
          ],
        ] else ...[
          TextField(
            controller: _usernameController,
            focusNode: _usernameFocusNode,
            style: AppStyles.inputText,
            cursorColor: Colors.white,
            decoration: const InputDecoration(
              hintText: 'Никнейм',
              hintStyle: AppStyles.inputHint,
              border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
              contentPadding: EdgeInsets.symmetric(vertical: 16),
            ),
            onSubmitted: (_) => _goToNextStep(),
          ),
        ],
      ],
    );
  }
  
  /// Виджет для отображения недавних аккаунтов
  Widget _buildRecentAccounts() {
    if (_isLoadingRecentAccounts) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(16.0),
          child: SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              color: Colors.white54,
              strokeWidth: 2,
            ),
          ),
        ),
      );
    }
    
    if (_recentAccounts.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Недавние аккаунты',
              style: AppStyles.bodyMuted.copyWith(fontSize: 12),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const RecentAccountsScreen(),
                  ),
                );
              },
              child: Text(
                'Все',
                style: AppStyles.bodyMuted.copyWith(
                  fontSize: 12,
                  color: Colors.white54,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Column(
          children: _recentAccounts.take(4).map((account) => _buildRecentAccountItem(account)).toList(),
        ),
      ],
    );
  }
  
  /// Виджет для одного недавнего аккаунта
  Widget _buildRecentAccountItem(RecentAccount account) {
    return GestureDetector(
      onTap: () => _handleQuickLogin(account),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.05)),
        ),
        child: Row(
          children: [
            AvatarWidget(
              avatar: account.avatar,
              avatarGradient: account.avatarGradient,
              hasAvatar: account.hasAvatar,
              username: account.username,
              size: 44,
            ),
            const SizedBox(width: 16),
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (account.email.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      account.email,
                      style: AppStyles.bodyMuted.copyWith(fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const FaIcon(FontAwesomeIcons.chevronRight, color: Colors.white24, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildPasswordStep({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Введите пароль', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        Text('Для аккаунта @${_usernameController.text}', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        TextField(
          controller: _passwordController,
          focusNode: _passwordFocusNode,
          style: AppStyles.inputText,
          cursorColor: Colors.white,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            hintText: 'Пароль',
            hintStyle: AppStyles.inputHint,
            border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            suffixIcon: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              icon: FaIcon(
                _obscurePassword ? FontAwesomeIcons.eyeSlash : FontAwesomeIcons.eye,
                color: Colors.white70,
                size: 16,
              ),
              onPressed: () {
                setState(() {
                  _obscurePassword = !_obscurePassword;
                });
              },
            ),
          ),
          onSubmitted: (_) => _goToNextStep(),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: List.generate(2, (index) {
        return Expanded(
          child: AnimatedContainer(
            duration: AppStyles.animationFast,
            margin: const EdgeInsets.symmetric(horizontal: 4),
            height: 4,
            decoration: BoxDecoration(
              color: _currentStep >= index ? Colors.white : Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        );
      }),
    );
  }
}
