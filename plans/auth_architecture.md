# План архитектуры xaneo_mobile_v2

## 1. Анализ текущих проблем xaneo_mobile

### Выявленные проблемы:
1. **Монолитные файлы** - `black_screen.dart` содержит 310KB кода (регистрация, вход, онбординг всё в одном)
2. **Хардкод конфигурации** - переменные разбросаны по коду вместо централизованного конфига
3. **Отсутствие разделения ответственности** - смешивание UI, бизнес-логики и API вызовов
4. **Небезопасное хранение токенов** - токены хранятся в SharedPreferences без дополнительной защиты

## 2. Выбор API для авторизации

### Сравнение endpoints:

#### Авторизация (Login):

| Endpoint | Описание | Безопасность | Рекомендация |
|----------|----------|--------------|--------------|
| `auth/token/` | Стандартный JWT (SimpleJWT) | Базовая, нет rate limiting | ❌ Не рекомендуется |
| `auth/login/` | Обычный вход | Базовый rate limiting | ⚠️ Можно использовать |
| `auth/mobile-login/` | Специализированный для мобильных | Rate limiting, 2FA support, IsMobileAppPermission | ✅ **Рекомендуется** |

#### Регистрация (Register):

| Endpoint | Описание | Безопасность | Рекомендация |
|----------|----------|--------------|--------------|
| `auth/register/` | Стандартная регистрация (UserRegistrationAPIView) | ✅ Проверяет флаг email в **сессии**, настоящая валидация | ✅ **Рекомендуется** |
| `auth/mobile-register/` | Мобильная регистрация (register_user_api) | ❌ НЕ проверяет сессию, просто ставит `email_verified=True` | ❌ Не рекомендуется |

**⚠️ КРИТИЧЕСКАЯ РАЗНИЦА:**

1. **`auth/register/`** (UserRegistrationAPIView + UserRegistrationSerializer):
   - `permission_classes = [permissions.AllowAny]` - доступно всем
   - ✅ **Проверяет флаг `email_verified_{email}` в СЕССИИ**
   - ✅ Флаг устанавливается ТОЛЬКО после `/auth/verify-email-code/`
   - ✅ Флаг одноразовый - удаляется после использования
   - ✅ **Настоящая валидация подтверждения email**
   - Возвращает JWT токены сразу

2. **`auth/mobile-register/`** (register_user_api):
   - `@permission_classes([IsMobileAppPermission])` - только для мобильных
   - ❌ **НЕ проверяет сессию на подтверждение email**
   - ❌ Просто ставит `email_verified=True` без проверки
   - ❌ Можно вызвать напрямую без подтверждения email
   - Не возвращает JWT токены

**ВЫВОД:** Использовать `auth/register/` для регистрации, так как он имеет **настоящую валидацию** подтверждения email через сессию!

### Преимущества mobile-specific API:

1. **Rate Limiting** - защита от brute force (5 попыток / 5 минут)
2. **2FA Support** - встроенная поддержка двухфакторной аутентификации
3. **IsMobileAppPermission** - проверка что запрос идёт от мобильного приложения
4. **Маскирование email** - безопасность в ответах API
5. **Временные токены** - для 2FA процесса с TTL 5 минут

### Flow авторизации:

```
┌─────────────────────────────────────────────────────────────────┐
│                    MOBILE LOGIN FLOW                            │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. POST /auth/mobile-login/                                    │
│     {username, password}                                        │
│         │                                                       │
│         ▼                                                       │
│  ┌─────────────────┐                                            │
│  │ auth_success?   │                                            │
│  └────────┬────────┘                                            │
│       │   │                                                     │
│   Yes │   │ No (tfa_required: true)                             │
│       │   │                                                     │
│       ▼   ▼                                                     │
│  ┌─────────┐  ┌──────────────────────────────┐                  │
│  │ SUCCESS │  │ 2FA Flow:                    │                  │
│  │ tokens  │  │ 2. POST /auth/send-tfa-code/ │                  │
│  └─────────┘  │    {token}                   │                  │
│               │         │                    │                  │
│               │         ▼                    │                  │
│               │ 3. POST /auth/verify-tfa-code│                  │
│               │    {token, code}             │                  │
│               │         │                    │                  │
│               │         ▼                    │                  │
│               │    ┌─────────┐               │                  │
│               │    │ SUCCESS │               │                  │
│               │    │ tokens  │               │                  │
│               │    └─────────┘               │                  │
│               └──────────────────────────────┘                  │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Flow регистрации:

```
┌─────────────────────────────────────────────────────────────────┐
│                  REGISTER FLOW (рекомендуется)                  │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. GET /auth/check-username/?username=X                        │
│     → {available: true/false}                                   │
│     ⚠️ IsMobileAppPermission - только для мобильных приложений   │
│                                                                 │
│  2. GET /auth/check-email/?email=X                              │
│     → {available: true/false, code: "DISPOSABLE_EMAIL"}         │
│     ⚠️ Проверка на временные email-адреса                        │
│                                                                 │
│  3. POST /auth/send-verification-code/                          │
│     {email, username}                                           │
│     → {success: true, expires_in: 600}                          │
│     ⚠️ Код действует 10 минут                                    │
│                                                                 │
│  4. POST /auth/verify-email-code/                               │
│     {email, code}                                               │
│     → {verified: true}                                          │
│     ⚠️ Устанавливает флаг email_verified_{email} в СЕССИИ        │
│     ⚠️ Обязательный шаг перед регистрацией                       │
│                                                                 │
│  5. POST /auth/register/                                        │
│     {username, email, password, password_confirm,               │
│      birth_date, email_verified: true}                          │
│     ⚠️ UserRegistrationSerializer проверяет ФЛАГ В СЕССИИ        │
│     ⚠️ Если флага нет - регистрация отклоняется                  │
│     → {user, refresh, access, message}                          │
│     ✅ Возвращает JWT токены сразу                               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘

⚠️ ВАЖНО: auth/register/ проверяет ФЛАГ В СЕССИИ!
Без предварительного вызова verify-email-code регистрация невозможна!
```

## 3. Структура проекта

```
lib/
├── main.dart                          # Точка входа
├── app/
│   └── app.dart                       # MaterialApp конфигурация
│
├── config/
│   ├── app_config.dart                # Конфигурация приложения
│   ├── api_config.dart                # API endpoints, timeouts
│   └── security_config.dart           # Настройки безопасности
│
├── models/
│   ├── auth/
│   │   ├── user.dart                  # Модель пользователя
│   │   ├── auth_response.dart         # Ответ авторизации
│   │   ├── tfa_response.dart          # Ответ 2FA
│   │   └── registration_request.dart  # Запрос регистрации
│   └── common/
│       └── api_response.dart          # Базовый ответ API
│
├── services/
│   ├── auth/
│   │   ├── auth_service.dart          # Основной сервис авторизации
│   │   ├── token_storage.dart         # Безопасное хранение токенов
│   │   └── tfa_service.dart           # Сервис 2FA
│   ├── api/
│   │   ├── api_client.dart            # HTTP клиент с interceptors
│   │   ├── auth_interceptor.dart      # Добавление токенов к запросам
│   │   └── error_handler.dart         # Обработка ошибок API
│   └── connectivity/
│       └── connectivity_service.dart  # Проверка соединения
│
├── providers/
│   ├── auth_provider.dart             # Состояние авторизации
│   ├── theme_provider.dart            # Тема приложения
│   └── locale_provider.dart           # Локализация
│
├── screens/
│   ├── auth/
│   │   ├── login_screen.dart          # Экран входа
│   │   ├── register_screen.dart       # Экран регистрации
│   │   ├── tfa_screen.dart            # Экран 2FA подтверждения
│   │   └── email_verification_screen.dart  # Подтверждение email
│   ├── main/
│   │   └── home_screen.dart           # Главный экран после входа
│   └── onboarding/
│       └── onboarding_screen.dart     # Онбординг
│
├── widgets/
│   ├── common/
│   │   ├── glass_card.dart            # Стеклянная карточка (из xaneo_pc)
│   │   ├── animated_background.dart   # Анимированный фон
│   │   ├── custom_text_field.dart     # Кастомное поле ввода
│   │   └── loading_button.dart        # Кнопка с загрузкой
│   ├── auth/
│   │   ├── auth_header.dart           # Заголовок формы авторизации
│   │   └── password_field.dart        # Поле пароля с toggle
│   └── effects/
│       ├── particle_background.dart   # Частицы на фоне
│       └── geometry_3d.dart           # 3D геометрия
│
├── styles/
│   ├── app_styles.dart                # Общие стили
│   ├── colors.dart                    # Цветовая палитра
│   └── gradients.dart                 # Градиенты
│
├── utils/
│   ├── validators.dart                # Валидаторы форм
│   ├── formatters.dart                # Форматтеры ввода
│   └── extensions.dart                # Расширения
│
└── l10n/
    ├── app_en.arb
    └── app_ru.arb
```

## 4. Конфигурация (app_config.dart)

```dart
// lib/config/app_config.dart
class AppConfig {
  // API Configuration
  static const String apiBaseUrl = 'https://api.xaneo.net/api/v1';
  static const Duration apiTimeout = Duration(seconds: 30);
  
  // Auth endpoints
  static const String authMobileLogin = '/auth/mobile-login/';
  static const String authMobileRegister = '/auth/mobile-register/';
  static const String authCheckUsername = '/auth/check-username/';
  static const String authCheckEmail = '/auth/check-email/';
  static const String authSendVerificationCode = '/auth/send-verification-code/';
  static const String authVerifyEmailCode = '/auth/verify-email-code/';
  static const String authSendTfaCode = '/auth/send-tfa-code/';
  static const String authVerifyTfaCode = '/auth/verify-tfa-code/';
  static const String authTokenRefresh = '/auth/token/refresh/';
  
  // Security
  static const String userAgent = 'XaneoMobile/2.0';
  static const Duration tokenRefreshThreshold = Duration(minutes: 5);
  
  // Storage keys
  static const String accessTokenKey = 'xaneo_access_token';
  static const String refreshTokenKey = 'xaneo_refresh_token';
  static const String userDataKey = 'xaneo_user_data';
  
  // Validation
  static const int minPasswordLength = 8;
  static const int maxPasswordLength = 128;
  static const int minUsernameLength = 3;
  static const int maxUsernameLength = 32;
  static const int verificationCodeLength = 6;
}
```

## 5. Auth Service (auth_service.dart)

```dart
// lib/services/auth/auth_service.dart
class AuthService {
  final ApiClient _apiClient;
  final TokenStorage _tokenStorage;
  
  AuthService(this._apiClient, this._tokenStorage);
  
  /// Проверка доступности username
  Future<bool> checkUsernameAvailable(String username) async {
    final response = await _apiClient.get(
      '${AppConfig.authCheckUsername}?username=$username',
    );
    return response.data['available'] ?? false;
  }
  
  /// Проверка доступности email
  Future<EmailCheckResult> checkEmailAvailable(String email) async {
    final response = await _apiClient.get(
      '${AppConfig.authCheckEmail}?email=$email',
    );
    return EmailCheckResult.fromJson(response.data);
  }
  
  /// Отправка кода верификации email
  Future<bool> sendEmailVerificationCode(String email, String username) async {
    final response = await _apiClient.post(
      AppConfig.authSendVerificationCode,
      data: {'email': email, 'username': username},
    );
    return response.data['success'] ?? false;
  }
  
  /// Подтверждение кода email
  Future<bool> verifyEmailCode(String email, String code) async {
    final response = await _apiClient.post(
      AppConfig.authVerifyEmailCode,
      data: {'email': email, 'code': code},
    );
    return response.data['verified'] ?? false;
  }
  
  /// Мобильный вход
  Future<AuthResult> mobileLogin(String username, String password) async {
    final response = await _apiClient.post(
      AppConfig.authMobileLogin,
      data: {'username': username, 'password': password},
    );
    
    final result = AuthResult.fromJson(response.data);
    
    if (result.authSuccess && result.tokens != null) {
      await _tokenStorage.saveTokens(
        accessToken: result.tokens!.access,
        refreshToken: result.tokens!.refresh,
      );
    }
    
    return result;
  }
  
  /// Регистрация
  Future<RegistrationResult> register(RegistrationRequest request) async {
    final response = await _apiClient.post(
      AppConfig.authMobileRegister,
      data: request.toJson(),
    );
    
    final result = RegistrationResult.fromJson(response.data);
    
    if (result.success) {
      await _tokenStorage.saveTokens(
        accessToken: result.refresh!,
        refreshToken: result.access!,
      );
    }
    
    return result;
  }
  
  /// Отправка 2FA кода
  Future<bool> sendTfaCode(String token) async {
    final response = await _apiClient.post(
      AppConfig.authSendTfaCode,
      data: {'token': token},
    );
    return response.data['success'] ?? false;
  }
  
  /// Подтверждение 2FA кода
  Future<TfaVerifyResult> verifyTfaCode(String token, String code) async {
    final response = await _apiClient.post(
      AppConfig.authVerifyTfaCode,
      data: {'token': token, 'code': code},
    );
    
    final result = TfaVerifyResult.fromJson(response.data);
    
    if (result.success && result.tokens != null) {
      await _tokenStorage.saveTokens(
        accessToken: result.tokens!.access,
        refreshToken: result.tokens!.refresh,
      );
    }
    
    return result;
  }
  
  /// Выход
  Future<void> logout() async {
    await _tokenStorage.clearTokens();
  }
  
  /// Проверка авторизации
  Future<bool> isAuthenticated() async {
    final accessToken = await _tokenStorage.getAccessToken();
    return accessToken != null;
  }
}
```

## 6. Безопасное хранение токенов (token_storage.dart)

```dart
// lib/services/auth/token_storage.dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class TokenStorage {
  final FlutterSecureStorage _storage;
  
  TokenStorage() : _storage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );
  
  Future<void> saveTokens({
    required String accessToken,
    required String refreshToken,
  }) async {
    await _storage.write(
      key: AppConfig.accessTokenKey,
      value: accessToken,
    );
    await _storage.write(
      key: AppConfig.refreshTokenKey,
      value: refreshToken,
    );
  }
  
  Future<String?> getAccessToken() async {
    return await _storage.read(key: AppConfig.accessTokenKey);
  }
  
  Future<String?> getRefreshToken() async {
    return await _storage.read(key: AppConfig.refreshTokenKey);
  }
  
  Future<void> clearTokens() async {
    await _storage.delete(key: AppConfig.accessTokenKey);
    await _storage.delete(key: AppConfig.refreshTokenKey);
    await _storage.delete(key: AppConfig.userDataKey);
  }
}
```

## 7. UI Компоненты из xaneo_pc

### GlassCard (стеклянная карточка)

```dart
// lib/widgets/common/glass_card.dart
class GlassCard extends StatelessWidget {
  final Widget child;
  final double blur;
  final double opacity;
  final BorderRadius? borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  
  const GlassCard({
    super.key,
    required this.child,
    this.blur = 10.0,
    this.opacity = 0.2,
    this.borderRadius,
    this.padding,
    this.margin,
  });
  
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: borderRadius ?? BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding ?? const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(opacity),
              borderRadius: borderRadius ?? BorderRadius.circular(20),
              border: Border.all(
                color: Colors.white.withOpacity(0.3),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 20,
                  spreadRadius: 5,
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
```

### AnimatedBackground (анимированный фон)

```dart
// lib/widgets/common/animated_background.dart
class AnimatedBackground extends StatefulWidget {
  final Widget child;
  
  const AnimatedBackground({super.key, required this.child});
  
  @override
  State<AnimatedBackground> createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground>
    with TickerProviderStateMixin {
  late AnimationController _controller;
  
  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 30),
      vsync: this,
    )..repeat();
  }
  
  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Gradient background
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color.lerp(Colors.deepPurple, Colors.indigo, _controller.value)!,
                    Color.lerp(Colors.indigo, Colors.purple, _controller.value)!,
                    Color.lerp(Colors.purple, Colors.deepPurple, _controller.value)!,
                  ],
                ),
              ),
            );
          },
        ),
        // Particle effect
        ParticleBackground(),
        // Content
        widget.child,
      ],
    );
  }
}
```

## 8. Экраны авторизации

### LoginScreen

```dart
// lib/screens/auth/login_screen.dart
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  
  // Animation controllers
  late AnimationController _fadeController;
  late AnimationController _slideController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;
  
  @override
  void initState() {
    super.initState();
    _initAnimations();
  }
  
  void _initAnimations() {
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0)
        .animate(CurvedAnimation(parent: _fadeController, curve: Curves.easeOut));
    
    _slideAnimation = Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero)
        .animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOutCubic));
    
    _fadeController.forward();
    _slideController.forward();
  }
  
  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    
    try {
      final authProvider = context.read<AuthProvider>();
      final result = await authProvider.login(
        _usernameController.text.trim(),
        _passwordController.text,
      );
      
      if (result.tfaRequired) {
        // Navigate to 2FA screen
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TfaScreen(token: result.token!),
          ),
        );
      } else if (result.authSuccess) {
        // Navigate to home
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      setState(() => _isLoading = false);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AnimatedBackground(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: SlideTransition(
                  position: _slideAnimation,
                  child: GlassCard(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Logo
                            _buildLogo(),
                            const SizedBox(height: 32),
                            // Username field
                            CustomTextField(
                              controller: _usernameController,
                              label: 'Username',
                              prefixIcon: Icons.person,
                              validator: Validators.username,
                            ),
                            const SizedBox(height: 16),
                            // Password field
                            PasswordField(
                              controller: _passwordController,
                              obscureText: _obscurePassword,
                              onToggle: () => setState(
                                () => _obscurePassword = !_obscurePassword,
                              ),
                            ),
                            const SizedBox(height: 24),
                            // Error message
                            if (_errorMessage != null)
                              Text(_errorMessage!, style: TextStyle(color: Colors.red)),
                            // Login button
                            LoadingButton(
                              text: 'Войти',
                              isLoading: _isLoading,
                              onPressed: _handleLogin,
                            ),
                            const SizedBox(height: 16),
                            // Register link
                            TextButton(
                              onPressed: () => Navigator.pushNamed(context, '/register'),
                              child: const Text('Нет аккаунта? Зарегистрироваться'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
```

## 9. Модели данных

### AuthResult

```dart
// lib/models/auth/auth_response.dart
class AuthResult {
  final bool authSuccess;
  final bool tfaRequired;
  final String? token;
  final String? message;
  final UserInfo? userInfo;
  final Tokens? tokens;
  
  AuthResult({
    required this.authSuccess,
    this.tfaRequired = false,
    this.token,
    this.message,
    this.userInfo,
    this.tokens,
  });
  
  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      authSuccess: json['auth_success'] ?? false,
      tfaRequired: json['tfa_required'] ?? false,
      token: json['token'],
      message: json['message'],
      userInfo: json['user_info'] != null 
          ? UserInfo.fromJson(json['user_info']) 
          : null,
      tokens: json['tokens'] != null 
          ? Tokens.fromJson(json['tokens']) 
          : null,
    );
  }
}

class UserInfo {
  final String username;
  final String email;
  final int? id;
  final bool isVerified;
  final bool tfaEnabled;
  
  UserInfo({
    required this.username,
    required this.email,
    this.id,
    this.isVerified = false,
    this.tfaEnabled = false,
  });
  
  factory UserInfo.fromJson(Map<String, dynamic> json) {
    return UserInfo(
      username: json['username'] ?? '',
      email: json['email'] ?? '',
      id: json['id'],
      isVerified: json['is_verified'] ?? false,
      tfaEnabled: json['tfa_enabled'] ?? false,
    );
  }
}

class Tokens {
  final String access;
  final String refresh;
  
  Tokens({required this.access, required this.refresh});
  
  factory Tokens.fromJson(Map<String, dynamic> json) {
    return Tokens(
      access: json['access'] ?? '',
      refresh: json['refresh'] ?? '',
    );
  }
}
```

## 10. Меры безопасности

### Реализованные меры:

1. **Secure Storage** - использование `flutter_secure_storage` с шифрованием
2. **User-Agent Header** - идентификация мобильного приложения
3. **Token Refresh** - автоматическое обновление токенов
4. **Rate Limiting** - обработка 429 responses
5. **Input Validation** - валидация на клиенте перед отправкой
6. **Error Handling** - безопасное отображение ошибок без утечки данных
7. **2FA Support** - полная поддержка двухфакторной аутентификации
8. **Email Verification** - обязательная верификация email при регистрации

### Рекомендации:

1. Не логировать чувствительные данные (токены, пароли)
2. Использовать HTTPS для всех запросов
3. Реализовать certificate pinning для production
4. Добавить biometric authentication для быстрого входа
5. Реализовать автоматический logout при неактивности

## 11. Зависимости pubspec.yaml

```yaml
dependencies:
  flutter:
    sdk: flutter
  
  # State Management
  provider: ^6.1.1
  
  # HTTP & API
  dio: ^5.4.0
  
  # Secure Storage
  flutter_secure_storage: ^9.2.1
  
  # Local Storage (for non-sensitive data)
  shared_preferences: ^2.2.2
  
  # UI Components
  google_fonts: ^6.1.0
  
  # Localization
  flutter_localizations:
    sdk: flutter
  intl: ^0.19.0
  
  # Connectivity
  connectivity_plus: ^5.0.2
  
  # Animations
  animations: ^2.0.8
  
  # Form validation
  form_field_validator: ^1.1.0
  
  # Biometric (optional)
  local_auth: ^2.1.8

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^3.0.1
```

## 12. Следующие шаги

1. **Создать Flutter проект** - `flutter create xaneo_mobile_v2`
2. **Настроить структуру директорий** - согласно разделу 3
3. **Реализовать конфигурацию** - app_config.dart, api_config.dart
4. **Реализовать API клиент** - с interceptors и error handling
5. **Реализовать Auth Service** - полная интеграция с mobile API
6. **Создать UI компоненты** - GlassCard, AnimatedBackground, CustomTextField
7. **Создать экраны авторизации** - Login, Register, TFA, EmailVerification
8. **Добавить локализацию** - русский и английский
9. **Написать тесты** - unit и integration тесты
10. **Настроить CI/CD** - для автоматической сборки

---

*Документ создан: 2026-03-22*
*Версия: 1.0*
