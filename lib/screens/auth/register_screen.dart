import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter/gestures.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../providers/auth_provider.dart';
import '../../styles/app_styles.dart';
import '../../widgets/common/auth_settings_modal.dart';
import '../../widgets/common/avatar_cropper.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> with SingleTickerProviderStateMixin {
  // Steps (new order):
  // 0: Name (Как вас зовут)
  // 1: Birthdate (Дата рождения)
  // 2: Nickname (Никнейм) - с валидацией на лету
  // 3: Email (Email) - с валидацией на занятость и иконкой инфо
  // 4: Email Verification (Подтверждение email)
  // 5: Password (Пароль)
  // 6: Password Confirm (Подтверждение пароля)
  // 7: Avatar (Аватар)
  // 8: Preview (Превью)
  int _currentStep = 0;

  final _nameController = TextEditingController();
  DateTime? _selectedBirthdate;
  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordConfirmController = TextEditingController();
  final _verificationCodeController = TextEditingController();

  final _nameFocusNode = FocusNode();
  final _usernameFocusNode = FocusNode();
  final _emailFocusNode = FocusNode();
  final _passwordFocusNode = FocusNode();
  final _passwordConfirmFocusNode = FocusNode();
  final _verificationCodeFocusNode = FocusNode();

  bool _isNameValid = false;
  bool _isBirthdateValid = false;
  bool _isUsernameValid = false;
  bool _isEmailValid = false;
  bool _isPasswordValid = false;
  bool _isPasswordConfirmValid = false;
  bool _isVerificationCodeValid = false;

  bool _agreedToTerms = false;
  bool _agreedToDataStorage = false;

  // Avatar
  File? _selectedAvatarImage;

  // Validation states
  bool _isCheckingUsername = false;
  String? _usernameError;
  bool _isUsernameAvailable = false;

  bool _isCheckingEmail = false;
  String? _emailError;
  bool _isEmailAvailable = false;

  bool _isSendingCode = false;
  bool _isVerifyingCode = false;
  String? _verificationError;

  // Debounce timers
  int _usernameDebounce = 0;
  int _emailDebounce = 0;

  @override
  void initState() {
    super.initState();
    _nameController.addListener(_validateFields);
    _usernameController.addListener(_onUsernameChanged);
    _emailController.addListener(_onEmailChanged);
    _passwordController.addListener(_validateFields);
    _passwordConfirmController.addListener(_validateFields);
    _verificationCodeController.addListener(_validateFields);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Future.delayed(AppStyles.animationFast, () {
          _nameFocusNode.requestFocus();
        });
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _usernameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _passwordConfirmController.dispose();
    _verificationCodeController.dispose();
    _nameFocusNode.dispose();
    _usernameFocusNode.dispose();
    _emailFocusNode.dispose();
    _passwordFocusNode.dispose();
    _passwordConfirmFocusNode.dispose();
    _verificationCodeFocusNode.dispose();
    super.dispose();
  }

  void _validateFields() {
    setState(() {
      _isNameValid = _nameController.text.trim().isNotEmpty;
      _isBirthdateValid = _selectedBirthdate != null;
      _isPasswordValid = _passwordController.text.length >= AppConfig.minPasswordLength;
      _isPasswordConfirmValid = _passwordController.text == _passwordConfirmController.text && _passwordConfirmController.text.isNotEmpty;
      _isVerificationCodeValid = _verificationCodeController.text.length == AppConfig.verificationCodeLength;
    });
  }

  void _onUsernameChanged() {
    _validateFields();
    _usernameDebounce++;
    final currentDebounce = _usernameDebounce;

    // Reset availability status when text changes
    setState(() {
      _isUsernameValid = _usernameController.text.trim().length >= AppConfig.minUsernameLength;
      _usernameError = null;
      _isUsernameAvailable = false;
    });

    // Debounce validation
    Future.delayed(const Duration(milliseconds: 500), () {
      if (currentDebounce == _usernameDebounce && mounted) {
        _validateUsername();
      }
    });
  }

  Future<void> _validateUsername() async {
    final username = _usernameController.text.trim();
    if (username.length < AppConfig.minUsernameLength) {
      return;
    }

    setState(() {
      _isCheckingUsername = true;
      _usernameError = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final result = await auth.checkUsername(username);

      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          if (result.available) {
            _isUsernameAvailable = true;
            _usernameError = null;
          } else {
            _isUsernameAvailable = false;
            _usernameError = result.message ?? 'Никнейм уже занят';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingUsername = false;
          _usernameError = 'Ошибка проверки';
        });
      }
    }
  }

  void _onEmailChanged() {
    _validateFields();
    _emailDebounce++;
    final currentDebounce = _emailDebounce;

    // Reset availability status when text changes
    setState(() {
      _isEmailValid = _emailController.text.trim().contains('@') && _emailController.text.trim().contains('.');
      _emailError = null;
      _isEmailAvailable = false;
    });

    // Debounce validation
    Future.delayed(const Duration(milliseconds: 500), () {
      if (currentDebounce == _emailDebounce && mounted) {
        _validateEmail();
      }
    });
  }

  Future<void> _validateEmail() async {
    final email = _emailController.text.trim();
    if (!email.contains('@') || !email.contains('.')) {
      return;
    }

    setState(() {
      _isCheckingEmail = true;
      _emailError = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final result = await auth.checkEmail(email);

      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          if (result.available) {
            _isEmailAvailable = true;
            _emailError = null;
          } else {
            _isEmailAvailable = false;
            _emailError = result.message ?? 'Email недоступен';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isCheckingEmail = false;
          _emailError = 'Ошибка проверки';
        });
      }
    }
  }

  Future<void> _sendVerificationCode() async {
    final email = _emailController.text.trim();
    final username = _usernameController.text.trim();

    setState(() {
      _isSendingCode = true;
      _verificationError = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      await auth.sendVerificationCode(email, username: username);

      if (mounted) {
        setState(() {
          _isSendingCode = false;
        });
        // Move to verification step
        _goToNextStepInternal();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSendingCode = false;
          _verificationError = 'Ошибка отправки кода';
        });
      }
    }
  }

  Future<void> _verifyEmailCode() async {
    final email = _emailController.text.trim();
    final code = _verificationCodeController.text.trim();

    setState(() {
      _isVerifyingCode = true;
      _verificationError = null;
    });

    try {
      final auth = context.read<AuthProvider>();
      final result = await auth.verifyEmailCode(email: email, code: code);

      if (mounted) {
        setState(() {
          _isVerifyingCode = false;
          if (result.success) {
            // Move to password step
            _goToNextStepInternal();
          } else {
            _verificationError = result.message ?? 'Неверный код';
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isVerifyingCode = false;
          _verificationError = 'Ошибка проверки кода';
        });
      }
    }
  }

  void _focusVerificationCodeInput() {
    FocusScope.of(context).requestFocus(_verificationCodeFocusNode);
    SystemChannels.textInput.invokeMethod('TextInput.show');
  }

  void _goToNextStepInternal() {
    setState(() {
      _currentStep++;
      if (_currentStep == 0) _nameFocusNode.requestFocus();
      if (_currentStep == 1) FocusScope.of(context).unfocus();
      if (_currentStep == 2) _usernameFocusNode.requestFocus();
      if (_currentStep == 3) _emailFocusNode.requestFocus();
      if (_currentStep == 4) _focusVerificationCodeInput();
      if (_currentStep == 5) _passwordFocusNode.requestFocus();
      if (_currentStep == 6) _passwordConfirmFocusNode.requestFocus();
      if (_currentStep == 7) FocusScope.of(context).unfocus();
    });
  }

  void _goToNextStep() {
    if (_currentStep == 3 && _isEmailValid && _isEmailAvailable) {
      // Send verification code and move to verification step
      _sendVerificationCode();
    } else if (_currentStep == 4 && _isVerificationCodeValid) {
      _verifyEmailCode();
    } else if (_currentStep == 8 && _isStepValid()) {
      // Final step - register the user
      _handleRegister();
    } else if (_isStepValid()) {
      _goToNextStepInternal();
    }
  }

  void _goBack() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        if (_currentStep == 0) _nameFocusNode.requestFocus();
        if (_currentStep == 1) FocusScope.of(context).unfocus();
        if (_currentStep == 2) _usernameFocusNode.requestFocus();
        if (_currentStep == 3) _emailFocusNode.requestFocus();
        if (_currentStep == 4) _focusVerificationCodeInput();
        if (_currentStep == 5) _passwordFocusNode.requestFocus();
        if (_currentStep == 6) _passwordConfirmFocusNode.requestFocus();
      });
    } else {
      Navigator.of(context).pop();
    }
  }

  Future<void> _handleRegister() async {
    final auth = context.read<AuthProvider>();

    String? birthDateStr;
    if (_selectedBirthdate != null) {
      birthDateStr = "${_selectedBirthdate!.year}-${_selectedBirthdate!.month.toString().padLeft(2, '0')}-${_selectedBirthdate!.day.toString().padLeft(2, '0')}";
    }

    final success = await auth.register(
      username: _usernameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      passwordConfirm: _passwordConfirmController.text,
      birthDate: birthDateStr,
      realname: _nameController.text.trim(),
    );

    if (!mounted) return;

    if (success) {
      Navigator.of(context).pop();
    } else if (auth.error != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(auth.error!.message, style: AppStyles.bodyMedium.copyWith(color: Colors.white)),
          backgroundColor: AppStyles.errorColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  bool _isStepValid() {
    switch (_currentStep) {
      case 0: return _isNameValid;
      case 1: return _isBirthdateValid;
      case 2: return _isUsernameValid && _isUsernameAvailable && !_isCheckingUsername;
      case 3: return _isEmailValid && _isEmailAvailable && !_isCheckingEmail;
      case 4: return _isVerificationCodeValid && !_isVerifyingCode;
      case 5: return _isPasswordValid;
      case 6: return _isPasswordConfirmValid;
      case 7: return true;
      case 8: return _agreedToTerms && _agreedToDataStorage;
      default: return false;
    }
  }

  Future<void> _pickAvatarImage() async {
    // Request permission first
    PermissionStatus permissionStatus;
    
    // On iOS, we use photos permission, on Android storage/photos
    if (Platform.isIOS) {
      permissionStatus = await Permission.photos.request();
    } else {
      // Android 13+ uses photos, older versions use storage
      permissionStatus = await Permission.photos.request();
      if (!permissionStatus.isGranted) {
        permissionStatus = await Permission.storage.request();
      }
    }
    
    if (!permissionStatus.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Необходимо разрешение на доступ к фотографиям'),
            backgroundColor: AppStyles.errorColor,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'Настройки',
              textColor: Colors.white,
              onPressed: () => openAppSettings(),
            ),
          ),
        );
      }
      return;
    }

    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );

    if (pickedFile != null && mounted) {
      final imageFile = File(pickedFile.path);
      final result = await AvatarCropper.show(context, imageFile);
      if (result != null) {
        setState(() {
          _selectedAvatarImage = result;
        });
      }
    }
  }

  void _showEmailInfoModal() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
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
              const Text('О выборе Email', style: AppStyles.titleLarge),
              const SizedBox(height: 24),
              
              // Simple text with clickable link
              RichText(
                text: TextSpan(
                  style: AppStyles.bodyMedium.copyWith(color: Colors.white70),
                  children: [
                    const TextSpan(text: 'Поддерживаются все домены электронной почты, кроме '),
                    TextSpan(
                      text: 'запрещённых',
                      style: const TextStyle(
                        color: Colors.blue,
                        decoration: TextDecoration.underline,
                      ),
                      recognizer: TapGestureRecognizer()
                        ..onTap = () async {
                          final uri = Uri.parse('https://github.com/disposable-email-domains/disposable-email-domains');
                          if (await canLaunchUrl(uri)) {
                            await launchUrl(uri, mode: LaunchMode.externalApplication);
                          }
                        },
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLoading = context.watch<AuthProvider>().isLoading;

    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: isLoading ? null : _goBack,
        ),
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
              const SizedBox(height: 10),
              Center(
                child: Image.asset(
                  'assets/images/logo.png',
                  height: 48,
                  width: 48,
                  errorBuilder: (context, error, stackTrace) => const Icon(Icons.bubble_chart, color: Colors.white, size: 48),
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
                        begin: const Offset(0.0, 0.05),
                        end: Offset.zero,
                      ).animate(animation),
                      child: child,
                    ),
                  );
                },
                child: _buildCurrentStep(key: ValueKey('step$_currentStep')),
              ),
              const SizedBox(height: 32),
              _buildProgressIndicator(),
              const Spacer(flex: 2),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: isLoading || !_isStepValid() ? null : _goToNextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.buttonBackgroundColor,
                    disabledBackgroundColor: Colors.white24,
                    foregroundColor: AppStyles.buttonTextColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  child: isLoading || _isCheckingUsername || _isCheckingEmail || _isSendingCode || _isVerifyingCode
                      ? const SizedBox(height: 24, width: 24, child: CircularProgressIndicator(color: Colors.black, strokeWidth: 2))
                      : Text(_currentStep < 8 ? 'Далее' : 'Создать аккаунт', style: AppStyles.buttonText),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCurrentStep({Key? key}) {
    switch (_currentStep) {
      case 0: return _buildInputStep(key, 'Как вас зовут?', 'Имя', 'Например, Иван', _nameController, _nameFocusNode);
      case 1: return _buildBirthdateStep(key);
      case 2: return _buildUsernameStep(key);
      case 3: return _buildEmailStep(key);
      case 4: return _buildVerificationStep(key);
      case 5: return _buildInputStep(key, 'Задайте пароль', 'Пароль', 'Минимум 8 символов', _passwordController, _passwordFocusNode, obscureText: true);
      case 6: return _buildPasswordConfirmStep(key);
      case 7: return _buildAvatarStep(key);
      case 8: return _buildProfilePreviewStep(key);
      default: return const SizedBox.shrink();
    }
  }

  Widget _buildInputStep(Key? key, String title, String label, String hint, TextEditingController controller, FocusNode focusNode, {bool obscureText = false, TextInputType? keyboardType}) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        Text(hint, style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        TextField(
          controller: controller,
          focusNode: focusNode,
          style: AppStyles.inputText,
          cursorColor: Colors.white,
          obscureText: obscureText,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: label,
            hintStyle: AppStyles.inputHint,
            border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
          ),
          onSubmitted: (_) => _isStepValid() ? _goToNextStep() : null,
        ),
      ],
    );
  }

  Widget _buildUsernameStep(Key? key) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Придумайте никнейм', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        const Text('Уникальное имя для вашего профиля', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        TextField(
          controller: _usernameController,
          focusNode: _usernameFocusNode,
          style: AppStyles.inputText,
          cursorColor: Colors.white,
          decoration: InputDecoration(
            hintText: 'Никнейм',
            hintStyle: AppStyles.inputHint,
            border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            suffixIcon: _isCheckingUsername
                ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)))
                : _isUsernameAvailable && _usernameController.text.length >= AppConfig.minUsernameLength
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
            errorText: _usernameError,
            errorStyle: const TextStyle(color: Colors.red),
          ),
          onSubmitted: (_) => _isStepValid() ? _goToNextStep() : null,
        ),
        if (_isUsernameAvailable && _usernameController.text.length >= AppConfig.minUsernameLength)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Никнейм доступен', style: AppStyles.bodyMuted.copyWith(color: Colors.green)),
          ),
      ],
    );
  }

  Widget _buildEmailStep(Key? key) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text('Ваш Email', style: AppStyles.titleGiant)),
            IconButton(
              icon: const Icon(Icons.info_outline, color: Colors.white54),
              onPressed: _showEmailInfoModal,
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text('Для связи и восстановления доступа', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        TextField(
          controller: _emailController,
          focusNode: _emailFocusNode,
          style: AppStyles.inputText,
          cursorColor: Colors.white,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(
            hintText: 'Email адрес',
            hintStyle: AppStyles.inputHint,
            border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            suffixIcon: _isCheckingEmail
                ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white54)))
                : _isEmailAvailable && _emailController.text.contains('@')
                    ? const Icon(Icons.check_circle, color: Colors.green)
                    : null,
            errorText: _emailError,
            errorStyle: const TextStyle(color: Colors.red),
          ),
          onSubmitted: (_) => _isStepValid() ? _goToNextStep() : null,
        ),
        if (_isEmailAvailable && _emailController.text.contains('@'))
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Email доступен', style: AppStyles.bodyMuted.copyWith(color: Colors.green)),
          ),
      ],
    );
  }

  Widget _buildVerificationStep(Key? key) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Подтверждение Email', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        Text('Код отправлен на ${_emailController.text}', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        // Visual code boxes + transparent input overlay
        LayoutBuilder(
          builder: (context, constraints) {
            const int codeLength = 6;
            const double spacing = 8;
            final totalSpacing = spacing * (codeLength - 1);
            final availableWidth = constraints.maxWidth - totalSpacing;
            final calculatedWidth = availableWidth / codeLength;
            final boxWidth = calculatedWidth > 48
                ? 48.0
                : (calculatedWidth < 36 ? 36.0 : calculatedWidth);
            final rowWidth = boxWidth * codeLength + totalSpacing;

            return Center(
              child: SizedBox(
                width: rowWidth,
                height: 56,
                child: Stack(
                  children: [
                    GestureDetector(
                      onTap: _focusVerificationCodeInput,
                      behavior: HitTestBehavior.opaque,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: List.generate(codeLength, (index) {
                          return Container(
                            width: boxWidth,
                            height: 56,
                            margin: EdgeInsets.only(right: index == codeLength - 1 ? 0 : spacing),
                            decoration: BoxDecoration(
                              color: Colors.white10,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: Colors.white24),
                            ),
                            child: Center(
                              child: Text(
                                _verificationCodeController.text.length > index ? _verificationCodeController.text[index] : '',
                                style: AppStyles.titleLarge.copyWith(fontSize: 24),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                    Positioned.fill(
                      child: Opacity(
                        opacity: 0,
                        child: TextField(
                          controller: _verificationCodeController,
                          focusNode: _verificationCodeFocusNode,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.done,
                          maxLength: 6,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          style: const TextStyle(color: Colors.transparent, fontSize: 1),
                          cursorColor: Colors.transparent,
                          decoration: const InputDecoration(
                            counterText: '',
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                          onChanged: (_) => setState(() {}),
                          autofocus: true,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        if (_verificationError != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(_verificationError!, style: AppStyles.bodyMuted.copyWith(color: Colors.red)),
          ),
        TextButton(
          onPressed: _isSendingCode ? null : () => _sendVerificationCode(),
          child: Text(
            'Отправить код повторно',
            style: TextStyle(color: _isSendingCode ? Colors.white38 : Colors.white),
          ),
        ),
      ],
    );
  }

  Widget _buildPasswordConfirmStep(Key? key) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Подтвердите пароль', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        const Text('Введите пароль ещё раз', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        TextField(
          controller: _passwordConfirmController,
          focusNode: _passwordConfirmFocusNode,
          style: AppStyles.inputText,
          cursorColor: Colors.white,
          obscureText: true,
          decoration: InputDecoration(
            hintText: 'Пароль ещё раз',
            hintStyle: AppStyles.inputHint,
            border: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
            focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: Colors.white)),
            contentPadding: const EdgeInsets.symmetric(vertical: 16),
            suffixIcon: _isPasswordConfirmValid
                ? const Icon(Icons.check_circle, color: Colors.green)
                : _passwordConfirmController.text.isNotEmpty && !_isPasswordConfirmValid
                    ? const Icon(Icons.error, color: Colors.red)
                    : null,
          ),
          onSubmitted: (_) => _isStepValid() ? _goToNextStep() : null,
        ),
        if (_passwordConfirmController.text.isNotEmpty && !_isPasswordConfirmValid)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('Пароли не совпадают', style: AppStyles.bodyMuted.copyWith(color: Colors.red)),
          ),
      ],
    );
  }

  void _showCupertinoDatePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (_) => Container(
        height: 250,
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E1E),
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(24),
            topRight: Radius.circular(24),
          ),
        ),
        child: Column(
          children: [
            Container(
              height: 50,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    child: const Text('Отмена', style: TextStyle(color: Colors.white54)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  CupertinoButton(
                    child: const Text('Готово', style: TextStyle(color: Colors.white)),
                    onPressed: () {
                      setState(() {
                        if (_selectedBirthdate == null) {
                          _selectedBirthdate = DateTime(2000, 1, 1);
                        }
                        _validateFields();
                      });
                      Navigator.of(context).pop();
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoTheme(
                data: const CupertinoThemeData(
                  textTheme: CupertinoTextThemeData(
                    dateTimePickerTextStyle: TextStyle(color: Colors.white, fontSize: 22),
                  ),
                ),
                child: CupertinoDatePicker(
                  mode: CupertinoDatePickerMode.date,
                  initialDateTime: _selectedBirthdate ?? DateTime(2000, 1, 1),
                  minimumDate: DateTime(1900),
                  maximumDate: DateTime.now(),
                  onDateTimeChanged: (val) {
                    setState(() {
                      _selectedBirthdate = val;
                      _validateFields();
                    });
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBirthdateStep(Key? key) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Дата рождения', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        const Text('Укажите вашу реальную дату рождения', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        GestureDetector(
          onTap: () {
            FocusScope.of(context).unfocus();
            _showCupertinoDatePicker();
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Colors.white24)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _selectedBirthdate != null
                      ? "${_selectedBirthdate!.day.toString().padLeft(2, '0')}.${_selectedBirthdate!.month.toString().padLeft(2, '0')}.${_selectedBirthdate!.year}"
                      : "ДД.ММ.ГГГГ",
                  style: _selectedBirthdate != null ? AppStyles.inputText : AppStyles.inputHint,
                ),
                const Icon(CupertinoIcons.calendar, color: Colors.white24),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatarStep(Key? key) {
    return SizedBox(
      width: double.infinity,
      child: Column(
        key: key,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text('Добавьте фото', style: AppStyles.titleGiant),
          const SizedBox(height: 8),
          const Text('Сделайте профиль узнаваемым', style: AppStyles.bodyMuted),
          const SizedBox(height: 48),
          GestureDetector(
            onTap: _pickAvatarImage,
            child: Container(
              width: 140,
              height: 140,
              decoration: BoxDecoration(
                color: _selectedAvatarImage != null ? Colors.transparent : Colors.white10,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white24, width: 2),
                image: _selectedAvatarImage != null
                    ? DecorationImage(
                        image: FileImage(_selectedAvatarImage!),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: _selectedAvatarImage == null
                  ? const Icon(Icons.add_a_photo_outlined, color: Colors.white70, size: 40)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProfilePreviewStep(Key? key) {
    return Column(
      key: key,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Text('Профиль готов', style: AppStyles.titleGiant),
        const SizedBox(height: 8),
        const Text('Осталось всего пара шагов', style: AppStyles.bodyMuted),
        const SizedBox(height: 32),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Column(
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: _selectedAvatarImage != null ? Colors.transparent : Colors.white24,
                  shape: BoxShape.circle,
                  image: _selectedAvatarImage != null
                      ? DecorationImage(
                          image: FileImage(_selectedAvatarImage!),
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                child: _selectedAvatarImage == null
                    ? const Icon(Icons.person, color: Colors.white, size: 40)
                    : null,
              ),
              const SizedBox(height: 16),
              Text(_nameController.text, style: AppStyles.titleLarge),
              const SizedBox(height: 4),
              Text('@${_usernameController.text}', style: AppStyles.bodyMuted),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _buildCheckbox(
          title: 'Я принимаю Пользовательское соглашение',
          value: _agreedToTerms,
          onChanged: (val) {
            setState(() {
              _agreedToTerms = val ?? false;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildCheckbox(
          title: 'Я даю согласие на обработку персональных данных',
          value: _agreedToDataStorage,
          onChanged: (val) {
            setState(() {
              _agreedToDataStorage = val ?? false;
            });
          },
        ),
      ],
    );
  }

  Widget _buildCheckbox({required String title, required bool value, required ValueChanged<bool?> onChanged}) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: value,
              onChanged: onChanged,
              fillColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) return Colors.white;
                return Colors.transparent;
              }),
              checkColor: Colors.black,
              side: const BorderSide(color: Colors.white54, width: 1.5),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: List.generate(9, (index) {
        return Expanded(
          child: AnimatedContainer(
            duration: AppStyles.animationFast,
            margin: const EdgeInsets.symmetric(horizontal: 2),
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
