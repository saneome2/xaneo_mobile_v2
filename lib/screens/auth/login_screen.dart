import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../models/auth/recent_account.dart';
import '../../providers/auth_provider.dart';
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
      // Main screen navigation is handled by auth wrapper 
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
    
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: _currentStep == 1 
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
              onPressed: isLoading ? null : _goBack,
            )
          : null,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: Colors.white70),
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
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.bubble_chart, color: Colors.white, size: 60),
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
                  ? _buildUsernameStep(key: const ValueKey('step0'))
                  : _buildPasswordStep(key: const ValueKey('step1')),
              ),
              const SizedBox(height: 32),
              _buildProgressIndicator(),
              const Spacer(flex: 2),
              
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

  Widget _buildUsernameStep({Key? key}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('С возвращением', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        const Text('Введите ваш никнейм', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
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
        // Недавние аккаунты
        if (_showRecentAccounts && _recentAccounts.isNotEmpty) ...[
          const SizedBox(height: 24),
          _buildRecentAccounts(),
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
        const SizedBox(height: 12),
        SizedBox(
          height: 80,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _recentAccounts.length > 5 ? 5 : _recentAccounts.length,
            itemBuilder: (context, index) {
              final account = _recentAccounts[index];
              return _buildRecentAccountItem(account);
            },
          ),
        ),
      ],
    );
  }
  
  /// Виджет для одного недавнего аккаунта
  Widget _buildRecentAccountItem(RecentAccount account) {
    return GestureDetector(
      onTap: () => _handleQuickLogin(account),
      child: Container(
        width: 72,
        margin: const EdgeInsets.only(right: 12),
        child: Column(
          children: [
            AvatarWidget(
              avatar: account.avatar,
              avatarGradient: account.avatarGradient,
              hasAvatar: account.hasAvatar,
              username: account.username,
              size: 48,
            ),
            const SizedBox(height: 8),
            Text(
              '@${account.username}',
              style: AppStyles.bodyMuted.copyWith(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
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
          obscureText: true,
          decoration: const InputDecoration(
            hintText: 'Пароль',
            hintStyle: AppStyles.inputHint,
            border: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: EdgeInsets.symmetric(vertical: 16),
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
