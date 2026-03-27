/// Модель недавнего аккаунта для отображения на экране входа
class RecentAccount {
  final int id;
  final String username;
  final String email;
  final String? avatar;
  final DateTime lastLogin;
  final DateTime firstLogin;
  
  // Локальные данные (не с сервера)
  final String? avatarGradient;
  final bool hasAvatar;

  const RecentAccount({
    required this.id,
    required this.username,
    required this.email,
    this.avatar,
    required this.lastLogin,
    required this.firstLogin,
    this.avatarGradient,
    this.hasAvatar = false,
  });

  factory RecentAccount.fromJson(Map<String, dynamic> json) {
    return RecentAccount(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      avatar: json['avatar'] as String?,
      lastLogin: DateTime.parse(json['last_login'] as String),
      firstLogin: DateTime.parse(json['first_login'] as String),
      avatarGradient: json['avatar_gradient'] as String?,
      hasAvatar: json['avatar'] != null && json['avatar'].toString().isNotEmpty,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar': avatar,
      'last_login': lastLogin.toIso8601String(),
      'first_login': firstLogin.toIso8601String(),
      'avatar_gradient': avatarGradient,
      'has_avatar': hasAvatar,
    };
  }

  /// Создает копию с обновленными полями
  RecentAccount copyWith({
    int? id,
    String? username,
    String? email,
    String? avatar,
    DateTime? lastLogin,
    DateTime? firstLogin,
    String? avatarGradient,
    bool? hasAvatar,
  }) {
    return RecentAccount(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      lastLogin: lastLogin ?? this.lastLogin,
      firstLogin: firstLogin ?? this.firstLogin,
      avatarGradient: avatarGradient ?? this.avatarGradient,
      hasAvatar: hasAvatar ?? this.hasAvatar,
    );
  }

  @override
  String toString() {
    return 'RecentAccount(id: $id, username: $username, email: $email)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecentAccount && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Ответ на запрос недавних аккаунтов
class RecentAccountsResponse {
  final bool success;
  final List<RecentAccount> recentAccounts;
  final int count;
  final String? error;

  const RecentAccountsResponse({
    required this.success,
    this.recentAccounts = const [],
    this.count = 0,
    this.error,
  });

  factory RecentAccountsResponse.fromJson(Map<String, dynamic> json) {
    final accountsList = json['recent_accounts'] as List<dynamic>?;
    final accounts = accountsList
        ?.map((e) => RecentAccount.fromJson(e as Map<String, dynamic>))
        .toList() ?? [];

    return RecentAccountsResponse(
      success: json['success'] as bool? ?? false,
      recentAccounts: accounts,
      count: json['count'] as int? ?? accounts.length,
      error: json['error'] as String?,
    );
  }
}
