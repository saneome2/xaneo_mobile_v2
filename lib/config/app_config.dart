/// Конфигурация приложения Xaneo Mobile v2
///
/// Все константы вынесены в отдельный файл для:
/// - Централизованного управления
/// - Легкого изменения среды (dev/staging/prod)
/// - Безопасности (нет хардкода в коде)
class AppConfig {
// ========== API Configuration ==========

  /// Базовый URL API сервера
  /// TODO: Изменить на продакшн перед релизом
  static const String apiBaseUrl = 'https://192.168.3.65/api/v1';
  
  /// Таймаут для API запросов
  static const Duration apiTimeout = Duration(seconds: 30);
  
  /// Таймаут для долгих операций (загрузка файлов)
  static const Duration apiLongTimeout = Duration(minutes: 5);

  // ========== Auth Endpoints ==========

  /// Мобильный вход (рекомендуется)
  /// - Rate limiting: 5 попыток / 5 минут
  /// - Поддержка 2FA
  /// - IsMobileAppPermission
  /// - Возвращает auth_success + user_info (БЕЗ JWT токенов!)
  static const String authMobileLogin = '/auth/mobile-login/';

  /// Стандартный вход (возвращает JWT токены)
  /// - Rate limiting: 5 попыток / 5 минут
  /// - Возвращает access + refresh токены
  /// - Использовать после успешного mobile-login
  static const String authLogin = '/auth/login/';

  /// Стандартная регистрация (web)
  /// - Проверяет флаг email_verified в сессии
  /// - Возвращает JWT токены сразу
  static const String authRegister = '/auth/register/';

  /// Мобильная регистрация (рекомендуется для мобильных приложений)
  /// - IsMobileAppPermission
  /// - Проверяет флаг email_verified в сессии
  /// - Возвращает user_id, username, email, first_name
  static const String authMobileRegister = '/auth/mobile-register/';
  
  /// Проверка доступности username
  /// - IsMobileAppPermission
  static const String authCheckUsername = '/auth/check-username/';
  
  /// Проверка доступности email
  /// - IsMobileAppPermission
  /// - Проверка на временные email-адреса
  static const String authCheckEmail = '/auth/check-email/';
  
  /// Отправка кода верификации email
  /// - Код действует 10 минут
  static const String authSendVerificationCode = '/auth/send-verification-code/';
  
  /// Подтверждение кода email
  /// - Устанавливает флаг в сессии
  static const String authVerifyEmailCode = '/auth/verify-email-code/';

  /// Недавние аккаунты для устройства
  /// - IsMobileAppPermission
  /// - Возвращает список аккаунтов, в которые входили на этом устройстве
  static const String authRecentAccounts = '/auth/recent-accounts/';

  /// Быстрый вход в аккаунт
  /// - IsMobileAppPermission
  /// - Проверяет, входил ли пользователь с этого устройства ранее
  /// - Поддержка 2FA
  static const String authQuickLogin = '/auth/quick-login/';

  /// Отправка 2FA кода
  static const String authSendTfaCode = '/auth/send-tfa-code/';
  
  /// Подтверждение 2FA кода
  static const String authVerifyTfaCode = '/auth/verify-tfa-code/';
  
  /// Обновление JWT токена
  static const String authTokenRefresh = '/auth/token/refresh/';
  
  /// Проверка JWT токена
  static const String authTokenVerify = '/auth/token/verify/';

  // ========== Chat Endpoints ==========

  /// Получение списка чатов пользователя
  static const String chatsList = '/chats/';

  // ========== XSEC-2 Endpoints ==========

  /// Загрузка ключей на сервер
  static const String xsec2UploadKeys = '/xsec2/upload-keys/';

  /// Получение своих ключей
  static const String xsec2MyKeys = '/xsec2/my-keys/';

  /// Получение ключа чата (группа/канал)
  /// chat_id должен быть в формате 'group_{id}' или 'channel_{id}'
  static const String xsec2ChatKey = '/xsec2/keys/chat';

  /// Получение публичных ключей пользователя
  /// Формат: /xsec2/keys/{user_id_or_username}/
  static const String xsec2UserKeys = '/xsec2/keys';

  /// Получение текущей эпохи и ключей для пользователя
  static const String xsec2GroupEpochCurrent = '/xsec2/group/epoch/current';

  // ========== Security ==========
  
  /// User-Agent для идентификации мобильного приложения
  static const String userAgent = 'XaneoMobile/2.0';
  
  /// Порог для автоматического обновления токена (за 5 минут до истечения)
  static const Duration tokenRefreshThreshold = Duration(minutes: 5);
  
  /// Время жизни access токена (для справки)
  static const Duration accessTokenLifetime = Duration(minutes: 15);
  
  /// Время жизни refresh токена (для справки)
  static const Duration refreshTokenLifetime = Duration(days: 7);

  // ========== Storage Keys ==========
  
  /// Ключ для хранения access токена
  static const String accessTokenKey = 'xaneo_access_token';
  
  /// Ключ для хранения refresh токена
  static const String refreshTokenKey = 'xaneo_refresh_token';
  
  /// Ключ для хранения данных пользователя
  static const String userDataKey = 'xaneo_user_data';
  
  /// Ключ для хранения настроек темы
  static const String themeKey = 'xaneo_theme';
  
  /// Ключ для хранения языка
  static String localeKey = 'xaneo_locale';

  // ========== Validation ==========
  
  /// Минимальная длина пароля
  static const int minPasswordLength = 8;
  
  /// Максимальная длина пароля
  static const int maxPasswordLength = 128;
  
  /// Минимальная длина username
  static const int minUsernameLength = 3;
  
  /// Максимальная длина username
  static const int maxUsernameLength = 32;
  
  /// Длина кода верификации
  static const int verificationCodeLength = 6;
  
  /// Минимальный возраст пользователя
  static const int minUserAge = 13;

  // ========== Supported Email Domains ==========
  
  /// Поддерживаемые почтовые провайдеры
  static const Set<String> supportedEmailDomains = {
    'yandex.ru', 'yandex.com', 'yandex.by', 'yandex.kz', 'yandex.ua',
    'gmail.com', 'googlemail.com',
    'icloud.com', 'me.com', 'mac.com',
    'mail.ru', 'inbox.ru', 'bk.ru', 'list.ru',
    'yahoo.com', 'yahoo.ru', 'yahoo.de', 'yahoo.fr', 'yahoo.es', 'yahoo.co.uk',
    'outlook.com', 'outlook.ru', 'hotmail.com', 'live.com',
  };

  // ========== UI Constants ==========
  
  /// Длительность анимации появления
  static const Duration fadeInDuration = Duration(milliseconds: 800);
  
  /// Длительность анимации слайда
  static const Duration slideInDuration = Duration(milliseconds: 1000);
  
  /// Длительность анимации пульсации
  static const Duration pulseDuration = Duration(milliseconds: 1500);
  
  /// Длительность вращения фона
  static const Duration backgroundRotationDuration = Duration(seconds: 30);

  // ========== Error Messages ==========
  
  /// Сообщение о превышении rate limit
  static const String rateLimitError = 'Слишком много попыток. Попробуйте позже.';
  
  /// Сообщение об ошибке сети
  static const String networkError = 'Ошибка сети. Проверьте подключение.';
  
  /// Сообщение об ошибке сервера
  static const String serverError = 'Ошибка сервера. Попробуйте позже.';
  
  /// Сообщение о неверных учетных данных
  static const String invalidCredentials = 'Неверные учетные данные.';

  // ========== Private Constructor ==========
  
  // Запрещаем создание экземпляров
  AppConfig._();
}
