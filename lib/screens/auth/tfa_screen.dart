import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../styles/app_styles.dart';
import 'login_screen.dart';
import '../main/main_screen.dart';

/// Экран подтверждения 2FA
class TfaScreen extends StatefulWidget {
  /// ID пользователя (для быстрого входа)
  final int? userId;
  
  /// Имя пользователя (для отображения)
  final String? username;

  const TfaScreen({
    super.key,
    this.userId,
    this.username,
  });

  @override
  State<TfaScreen> createState() => _TfaScreenState();
}

class _TfaScreenState extends State<TfaScreen>
    with SingleTickerProviderStateMixin {
  final _codeController = TextEditingController();
  final List<FocusNode> _focusNodes = List.generate(6, (_) => FocusNode());
  final List<String> _codeDigits = List.filled(6, '');
  
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: AppStyles.animationMedium,
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController, curve: AppStyles.curveEaseOut),
    );
    
    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _codeController.dispose();
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onDigitEntered(int index, String value) {
    if (value.isNotEmpty) {
      _codeDigits[index] = value;
      if (index < 5) {
        _focusNodes[index + 1].requestFocus();
      } else {
        _verifyCode();
      }
    } else {
      _codeDigits[index] = '';
      if (index > 0) {
        _focusNodes[index - 1].requestFocus();
      }
    }
    setState(() {});
  }

  void _verifyCode() {
    final code = _codeDigits.join();
    if (code.length == 6) {
      final auth = context.read<AuthProvider>();
      
      // Если это быстрый вход (есть userId)
      if (widget.userId != null) {
        auth.quickLogin(
          userId: widget.userId!,
          tfaCode: code,
        );
      } else {
        // Обычный вход после 2FA
        auth.verifyTfaCode(code);
      }
    }
  }

  void _resendCode() {
    // TODO: Вызвать API для повторной отправки кода
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Код отправлен повторно'),
        backgroundColor: AppStyles.textPrimaryColor,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      body: SafeArea(
        child: Consumer<AuthProvider>(
          builder: (context, auth, child) {
            if (auth.isAuthenticated) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const MainScreen()),
                );
              });
            }
            
            return _buildContent(auth);
          },
        ),
      ),
    );
  }

  Widget _buildContent(AuthProvider auth) {
    return FadeTransition(
      opacity: _fadeAnimation,
      child: Padding(
        padding: AppStyles.screenPadding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 80),
            
            // Иконка
            _buildIcon(),
            const SizedBox(height: 32),
            
            // Заголовок
            Text(
              'Двухфакторная\nаутентификация',
              style: AppStyles.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            // Описание
            Text(
              'На ваш email отправлен 6-значный код',
              style: AppStyles.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 48),
            
            // Поля для ввода кода
            _buildCodeFields(auth),
            const SizedBox(height: 16),
            
            // Ошибка
            if (auth.error != null) ...[
              Text(auth.error!.message, style: AppStyles.errorText, textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            
            // Кнопка подтверждения
            _buildVerifyButton(auth),
            const Spacer(),
            
            // Отправить код повторно
            _buildResendLink(),
            const SizedBox(height: 16),
            
            // Отмена
            _buildCancelButton(auth),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildIcon() {
    return Center(
      child: Container(
        width: 80,
        height: 80,
        decoration: BoxDecoration(
          color: AppStyles.inputBackgroundColor,
          borderRadius: BorderRadius.circular(40),
          border: Border.all(color: AppStyles.borderColor, width: 1),
        ),
        child: const Icon(
          Icons.security,
          size: 40,
          color: AppStyles.textPrimaryColor,
        ),
      ),
    );
  }

  Widget _buildCodeFields(AuthProvider auth) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(6, (index) {
        return SizedBox(
          width: 48,
          height: 56,
          child: TextField(
            focusNode: _focusNodes[index],
            textAlign: TextAlign.center,
            keyboardType: TextInputType.number,
            maxLength: 1,
            enabled: !auth.isLoading,
            style: AppStyles.inputText.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              counterText: '',
              filled: true,
              fillColor: AppStyles.inputBackgroundColor,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppStyles.borderColor, width: 1),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppStyles.borderColor, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppStyles.borderActiveColor, width: 1),
              ),
            ),
            onChanged: (value) => _onDigitEntered(index, value),
          ),
        );
      }),
    );
  }

  Widget _buildVerifyButton(AuthProvider auth) {
    return SizedBox(
      height: 50,
      child: ElevatedButton(
        onPressed: auth.isLoading ? null : _verifyCode,
        style: AppStyles.primaryButton,
        child: auth.isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppStyles.backgroundColor),
                ),
              )
            : const Text('Подтвердить', style: AppStyles.buttonText),
      ),
    );
  }

  Widget _buildResendLink() {
    return Center(
      child: TextButton(
        onPressed: _resendCode,
        style: AppStyles.textButton,
        child: const Text('Не получили код? Отправить повторно'),
      ),
    );
  }

  Widget _buildCancelButton(AuthProvider auth) {
    return Center(
      child: TextButton(
        onPressed: () {
          auth.resetTfaState();
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(builder: (_) => const LoginScreen()),
          );
        },
        style: AppStyles.textButton,
        child: const Text('Отмена'),
      ),
    );
  }
}
