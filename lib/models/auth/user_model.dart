/// Модель пользователя
class UserModel {
  final int id;
  final String username;
  final String email;
  final String? avatar;
  final String? avatarGradient;
  final String? bio;
  final bool emailVerified;
  final bool phoneVerified;
  final bool tfaEnabled;
  final DateTime? birthDate;
  final DateTime createdAt;
  final DateTime? lastSeen;

  const UserModel({
    required this.id,
    required this.username,
    required this.email,
    this.avatar,
    this.avatarGradient,
    this.bio,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.tfaEnabled = false,
    this.birthDate,
    required this.createdAt,
    this.lastSeen,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      avatar: json['avatar'] as String?,
      avatarGradient: json['avatar_gradient'] as String?,
      bio: json['bio'] as String?,
      emailVerified: json['email_verified'] as bool? ?? false,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      tfaEnabled: json['tfa_enabled'] as bool? ?? false,
      birthDate: json['birth_date'] != null
          ? DateTime.tryParse(json['birth_date'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastSeen: json['last_seen'] != null
          ? DateTime.tryParse(json['last_seen'] as String)
          : null,
    );
  }

  /// Создает UserModel из ответа mobile-login API (user_info)
  ///
  /// Mobile-login возвращает другую структуру:
  /// - id, username, email
  /// - is_verified (вместо email_verified)
  /// - tfa_enabled
  /// - last_login, date_joined (вместо created_at)
  factory UserModel.fromUserInfoJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as int,
      username: json['username'] as String,
      email: json['email'] as String,
      emailVerified: json['is_verified'] as bool? ?? false,
      tfaEnabled: json['tfa_enabled'] as bool? ?? false,
      createdAt: json['date_joined'] != null
          ? DateTime.tryParse(json['date_joined'] as String) ?? DateTime.now()
          : DateTime.now(),
      lastSeen: json['last_login'] != null
          ? DateTime.tryParse(json['last_login'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'avatar': avatar,
      'avatar_gradient': avatarGradient,
      'bio': bio,
      'email_verified': emailVerified,
      'phone_verified': phoneVerified,
      'tfa_enabled': tfaEnabled,
      'birth_date': birthDate?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'last_seen': lastSeen?.toIso8601String(),
    };
  }

  /// Создает копию с обновленными полями
  UserModel copyWith({
    int? id,
    String? username,
    String? email,
    String? avatar,
    String? avatarGradient,
    String? bio,
    bool? emailVerified,
    bool? phoneVerified,
    bool? tfaEnabled,
    DateTime? birthDate,
    DateTime? createdAt,
    DateTime? lastSeen,
  }) {
    return UserModel(
      id: id ?? this.id,
      username: username ?? this.username,
      email: email ?? this.email,
      avatar: avatar ?? this.avatar,
      avatarGradient: avatarGradient ?? this.avatarGradient,
      bio: bio ?? this.bio,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      tfaEnabled: tfaEnabled ?? this.tfaEnabled,
      birthDate: birthDate ?? this.birthDate,
      createdAt: createdAt ?? this.createdAt,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  @override
  String toString() {
    return 'UserModel(id: $id, username: $username, email: $email)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is UserModel && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}
