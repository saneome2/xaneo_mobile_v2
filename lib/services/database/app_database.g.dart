// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ChatsTable extends Chats with TableInfo<$ChatsTable, Chat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverChatIdMeta =
      const VerificationMeta('serverChatId');
  @override
  late final GeneratedColumn<String> serverChatId = GeneratedColumn<String>(
      'server_chat_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _avatarMeta = const VerificationMeta('avatar');
  @override
  late final GeneratedColumn<String> avatar = GeneratedColumn<String>(
      'avatar', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _avatarGradientMeta =
      const VerificationMeta('avatarGradient');
  @override
  late final GeneratedColumn<String> avatarGradient = GeneratedColumn<String>(
      'avatar_gradient', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageMeta =
      const VerificationMeta('lastMessage');
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
      'last_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageTimeMeta =
      const VerificationMeta('lastMessageTime');
  @override
  late final GeneratedColumn<DateTime> lastMessageTime =
      GeneratedColumn<DateTime>('last_message_time', aliasedName, true,
          type: DriftSqlType.dateTime, requiredDuringInsert: false);
  static const VerificationMeta _unreadCountMeta =
      const VerificationMeta('unreadCount');
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
      'unread_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isGroupMeta =
      const VerificationMeta('isGroup');
  @override
  late final GeneratedColumn<bool> isGroup = GeneratedColumn<bool>(
      'is_group', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_group" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isChannelMeta =
      const VerificationMeta('isChannel');
  @override
  late final GeneratedColumn<bool> isChannel = GeneratedColumn<bool>(
      'is_channel', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_channel" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isPersonalMeta =
      const VerificationMeta('isPersonal');
  @override
  late final GeneratedColumn<bool> isPersonal = GeneratedColumn<bool>(
      'is_personal', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_personal" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isFavoritesMeta =
      const VerificationMeta('isFavorites');
  @override
  late final GeneratedColumn<bool> isFavorites = GeneratedColumn<bool>(
      'is_favorites', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_favorites" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _otherUserJsonMeta =
      const VerificationMeta('otherUserJson');
  @override
  late final GeneratedColumn<String> otherUserJson = GeneratedColumn<String>(
      'other_user_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isEncryptedMeta =
      const VerificationMeta('isEncrypted');
  @override
  late final GeneratedColumn<bool> isEncrypted = GeneratedColumn<bool>(
      'is_encrypted', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_encrypted" IN (0, 1))'),
      defaultValue: const Constant(false));
  @override
  List<GeneratedColumn> get $columns => [
        id,
        serverChatId,
        name,
        avatar,
        avatarGradient,
        lastMessage,
        lastMessageTime,
        unreadCount,
        isGroup,
        isChannel,
        isPersonal,
        isFavorites,
        otherUserJson,
        isEncrypted
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chats';
  @override
  VerificationContext validateIntegrity(Insertable<Chat> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_chat_id')) {
      context.handle(
          _serverChatIdMeta,
          serverChatId.isAcceptableOrUnknown(
              data['server_chat_id']!, _serverChatIdMeta));
    } else if (isInserting) {
      context.missing(_serverChatIdMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar')) {
      context.handle(_avatarMeta,
          avatar.isAcceptableOrUnknown(data['avatar']!, _avatarMeta));
    }
    if (data.containsKey('avatar_gradient')) {
      context.handle(
          _avatarGradientMeta,
          avatarGradient.isAcceptableOrUnknown(
              data['avatar_gradient']!, _avatarGradientMeta));
    }
    if (data.containsKey('last_message')) {
      context.handle(
          _lastMessageMeta,
          lastMessage.isAcceptableOrUnknown(
              data['last_message']!, _lastMessageMeta));
    }
    if (data.containsKey('last_message_time')) {
      context.handle(
          _lastMessageTimeMeta,
          lastMessageTime.isAcceptableOrUnknown(
              data['last_message_time']!, _lastMessageTimeMeta));
    }
    if (data.containsKey('unread_count')) {
      context.handle(
          _unreadCountMeta,
          unreadCount.isAcceptableOrUnknown(
              data['unread_count']!, _unreadCountMeta));
    }
    if (data.containsKey('is_group')) {
      context.handle(_isGroupMeta,
          isGroup.isAcceptableOrUnknown(data['is_group']!, _isGroupMeta));
    }
    if (data.containsKey('is_channel')) {
      context.handle(_isChannelMeta,
          isChannel.isAcceptableOrUnknown(data['is_channel']!, _isChannelMeta));
    }
    if (data.containsKey('is_personal')) {
      context.handle(
          _isPersonalMeta,
          isPersonal.isAcceptableOrUnknown(
              data['is_personal']!, _isPersonalMeta));
    }
    if (data.containsKey('is_favorites')) {
      context.handle(
          _isFavoritesMeta,
          isFavorites.isAcceptableOrUnknown(
              data['is_favorites']!, _isFavoritesMeta));
    }
    if (data.containsKey('other_user_json')) {
      context.handle(
          _otherUserJsonMeta,
          otherUserJson.isAcceptableOrUnknown(
              data['other_user_json']!, _otherUserJsonMeta));
    }
    if (data.containsKey('is_encrypted')) {
      context.handle(
          _isEncryptedMeta,
          isEncrypted.isAcceptableOrUnknown(
              data['is_encrypted']!, _isEncryptedMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Chat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Chat(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serverChatId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_chat_id'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      avatar: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar']),
      avatarGradient: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar_gradient']),
      lastMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_message']),
      lastMessageTime: attachedDatabase.typeMapping.read(
          DriftSqlType.dateTime, data['${effectivePrefix}last_message_time']),
      unreadCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unread_count'])!,
      isGroup: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_group'])!,
      isChannel: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_channel'])!,
      isPersonal: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_personal'])!,
      isFavorites: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_favorites'])!,
      otherUserJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}other_user_json']),
      isEncrypted: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_encrypted'])!,
    );
  }

  @override
  $ChatsTable createAlias(String alias) {
    return $ChatsTable(attachedDatabase, alias);
  }
}

class Chat extends DataClass implements Insertable<Chat> {
  final int id;
  final String serverChatId;
  final String name;
  final String? avatar;
  final String? avatarGradient;
  final String? lastMessage;
  final DateTime? lastMessageTime;
  final int unreadCount;
  final bool isGroup;
  final bool isChannel;
  final bool isPersonal;
  final bool isFavorites;
  final String? otherUserJson;
  final bool isEncrypted;
  const Chat(
      {required this.id,
      required this.serverChatId,
      required this.name,
      this.avatar,
      this.avatarGradient,
      this.lastMessage,
      this.lastMessageTime,
      required this.unreadCount,
      required this.isGroup,
      required this.isChannel,
      required this.isPersonal,
      required this.isFavorites,
      this.otherUserJson,
      required this.isEncrypted});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_chat_id'] = Variable<String>(serverChatId);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || avatar != null) {
      map['avatar'] = Variable<String>(avatar);
    }
    if (!nullToAbsent || avatarGradient != null) {
      map['avatar_gradient'] = Variable<String>(avatarGradient);
    }
    if (!nullToAbsent || lastMessage != null) {
      map['last_message'] = Variable<String>(lastMessage);
    }
    if (!nullToAbsent || lastMessageTime != null) {
      map['last_message_time'] = Variable<DateTime>(lastMessageTime);
    }
    map['unread_count'] = Variable<int>(unreadCount);
    map['is_group'] = Variable<bool>(isGroup);
    map['is_channel'] = Variable<bool>(isChannel);
    map['is_personal'] = Variable<bool>(isPersonal);
    map['is_favorites'] = Variable<bool>(isFavorites);
    if (!nullToAbsent || otherUserJson != null) {
      map['other_user_json'] = Variable<String>(otherUserJson);
    }
    map['is_encrypted'] = Variable<bool>(isEncrypted);
    return map;
  }

  ChatsCompanion toCompanion(bool nullToAbsent) {
    return ChatsCompanion(
      id: Value(id),
      serverChatId: Value(serverChatId),
      name: Value(name),
      avatar:
          avatar == null && nullToAbsent ? const Value.absent() : Value(avatar),
      avatarGradient: avatarGradient == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarGradient),
      lastMessage: lastMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessage),
      lastMessageTime: lastMessageTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageTime),
      unreadCount: Value(unreadCount),
      isGroup: Value(isGroup),
      isChannel: Value(isChannel),
      isPersonal: Value(isPersonal),
      isFavorites: Value(isFavorites),
      otherUserJson: otherUserJson == null && nullToAbsent
          ? const Value.absent()
          : Value(otherUserJson),
      isEncrypted: Value(isEncrypted),
    );
  }

  factory Chat.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Chat(
      id: serializer.fromJson<int>(json['id']),
      serverChatId: serializer.fromJson<String>(json['serverChatId']),
      name: serializer.fromJson<String>(json['name']),
      avatar: serializer.fromJson<String?>(json['avatar']),
      avatarGradient: serializer.fromJson<String?>(json['avatarGradient']),
      lastMessage: serializer.fromJson<String?>(json['lastMessage']),
      lastMessageTime: serializer.fromJson<DateTime?>(json['lastMessageTime']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      isGroup: serializer.fromJson<bool>(json['isGroup']),
      isChannel: serializer.fromJson<bool>(json['isChannel']),
      isPersonal: serializer.fromJson<bool>(json['isPersonal']),
      isFavorites: serializer.fromJson<bool>(json['isFavorites']),
      otherUserJson: serializer.fromJson<String?>(json['otherUserJson']),
      isEncrypted: serializer.fromJson<bool>(json['isEncrypted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverChatId': serializer.toJson<String>(serverChatId),
      'name': serializer.toJson<String>(name),
      'avatar': serializer.toJson<String?>(avatar),
      'avatarGradient': serializer.toJson<String?>(avatarGradient),
      'lastMessage': serializer.toJson<String?>(lastMessage),
      'lastMessageTime': serializer.toJson<DateTime?>(lastMessageTime),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'isGroup': serializer.toJson<bool>(isGroup),
      'isChannel': serializer.toJson<bool>(isChannel),
      'isPersonal': serializer.toJson<bool>(isPersonal),
      'isFavorites': serializer.toJson<bool>(isFavorites),
      'otherUserJson': serializer.toJson<String?>(otherUserJson),
      'isEncrypted': serializer.toJson<bool>(isEncrypted),
    };
  }

  Chat copyWith(
          {int? id,
          String? serverChatId,
          String? name,
          Value<String?> avatar = const Value.absent(),
          Value<String?> avatarGradient = const Value.absent(),
          Value<String?> lastMessage = const Value.absent(),
          Value<DateTime?> lastMessageTime = const Value.absent(),
          int? unreadCount,
          bool? isGroup,
          bool? isChannel,
          bool? isPersonal,
          bool? isFavorites,
          Value<String?> otherUserJson = const Value.absent(),
          bool? isEncrypted}) =>
      Chat(
        id: id ?? this.id,
        serverChatId: serverChatId ?? this.serverChatId,
        name: name ?? this.name,
        avatar: avatar.present ? avatar.value : this.avatar,
        avatarGradient:
            avatarGradient.present ? avatarGradient.value : this.avatarGradient,
        lastMessage: lastMessage.present ? lastMessage.value : this.lastMessage,
        lastMessageTime: lastMessageTime.present
            ? lastMessageTime.value
            : this.lastMessageTime,
        unreadCount: unreadCount ?? this.unreadCount,
        isGroup: isGroup ?? this.isGroup,
        isChannel: isChannel ?? this.isChannel,
        isPersonal: isPersonal ?? this.isPersonal,
        isFavorites: isFavorites ?? this.isFavorites,
        otherUserJson:
            otherUserJson.present ? otherUserJson.value : this.otherUserJson,
        isEncrypted: isEncrypted ?? this.isEncrypted,
      );
  Chat copyWithCompanion(ChatsCompanion data) {
    return Chat(
      id: data.id.present ? data.id.value : this.id,
      serverChatId: data.serverChatId.present
          ? data.serverChatId.value
          : this.serverChatId,
      name: data.name.present ? data.name.value : this.name,
      avatar: data.avatar.present ? data.avatar.value : this.avatar,
      avatarGradient: data.avatarGradient.present
          ? data.avatarGradient.value
          : this.avatarGradient,
      lastMessage:
          data.lastMessage.present ? data.lastMessage.value : this.lastMessage,
      lastMessageTime: data.lastMessageTime.present
          ? data.lastMessageTime.value
          : this.lastMessageTime,
      unreadCount:
          data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
      isGroup: data.isGroup.present ? data.isGroup.value : this.isGroup,
      isChannel: data.isChannel.present ? data.isChannel.value : this.isChannel,
      isPersonal:
          data.isPersonal.present ? data.isPersonal.value : this.isPersonal,
      isFavorites:
          data.isFavorites.present ? data.isFavorites.value : this.isFavorites,
      otherUserJson: data.otherUserJson.present
          ? data.otherUserJson.value
          : this.otherUserJson,
      isEncrypted:
          data.isEncrypted.present ? data.isEncrypted.value : this.isEncrypted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Chat(')
          ..write('id: $id, ')
          ..write('serverChatId: $serverChatId, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('avatarGradient: $avatarGradient, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isGroup: $isGroup, ')
          ..write('isChannel: $isChannel, ')
          ..write('isPersonal: $isPersonal, ')
          ..write('isFavorites: $isFavorites, ')
          ..write('otherUserJson: $otherUserJson, ')
          ..write('isEncrypted: $isEncrypted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
      id,
      serverChatId,
      name,
      avatar,
      avatarGradient,
      lastMessage,
      lastMessageTime,
      unreadCount,
      isGroup,
      isChannel,
      isPersonal,
      isFavorites,
      otherUserJson,
      isEncrypted);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Chat &&
          other.id == this.id &&
          other.serverChatId == this.serverChatId &&
          other.name == this.name &&
          other.avatar == this.avatar &&
          other.avatarGradient == this.avatarGradient &&
          other.lastMessage == this.lastMessage &&
          other.lastMessageTime == this.lastMessageTime &&
          other.unreadCount == this.unreadCount &&
          other.isGroup == this.isGroup &&
          other.isChannel == this.isChannel &&
          other.isPersonal == this.isPersonal &&
          other.isFavorites == this.isFavorites &&
          other.otherUserJson == this.otherUserJson &&
          other.isEncrypted == this.isEncrypted);
}

class ChatsCompanion extends UpdateCompanion<Chat> {
  final Value<int> id;
  final Value<String> serverChatId;
  final Value<String> name;
  final Value<String?> avatar;
  final Value<String?> avatarGradient;
  final Value<String?> lastMessage;
  final Value<DateTime?> lastMessageTime;
  final Value<int> unreadCount;
  final Value<bool> isGroup;
  final Value<bool> isChannel;
  final Value<bool> isPersonal;
  final Value<bool> isFavorites;
  final Value<String?> otherUserJson;
  final Value<bool> isEncrypted;
  const ChatsCompanion({
    this.id = const Value.absent(),
    this.serverChatId = const Value.absent(),
    this.name = const Value.absent(),
    this.avatar = const Value.absent(),
    this.avatarGradient = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isGroup = const Value.absent(),
    this.isChannel = const Value.absent(),
    this.isPersonal = const Value.absent(),
    this.isFavorites = const Value.absent(),
    this.otherUserJson = const Value.absent(),
    this.isEncrypted = const Value.absent(),
  });
  ChatsCompanion.insert({
    this.id = const Value.absent(),
    required String serverChatId,
    required String name,
    this.avatar = const Value.absent(),
    this.avatarGradient = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isGroup = const Value.absent(),
    this.isChannel = const Value.absent(),
    this.isPersonal = const Value.absent(),
    this.isFavorites = const Value.absent(),
    this.otherUserJson = const Value.absent(),
    this.isEncrypted = const Value.absent(),
  })  : serverChatId = Value(serverChatId),
        name = Value(name);
  static Insertable<Chat> custom({
    Expression<int>? id,
    Expression<String>? serverChatId,
    Expression<String>? name,
    Expression<String>? avatar,
    Expression<String>? avatarGradient,
    Expression<String>? lastMessage,
    Expression<DateTime>? lastMessageTime,
    Expression<int>? unreadCount,
    Expression<bool>? isGroup,
    Expression<bool>? isChannel,
    Expression<bool>? isPersonal,
    Expression<bool>? isFavorites,
    Expression<String>? otherUserJson,
    Expression<bool>? isEncrypted,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverChatId != null) 'server_chat_id': serverChatId,
      if (name != null) 'name': name,
      if (avatar != null) 'avatar': avatar,
      if (avatarGradient != null) 'avatar_gradient': avatarGradient,
      if (lastMessage != null) 'last_message': lastMessage,
      if (lastMessageTime != null) 'last_message_time': lastMessageTime,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (isGroup != null) 'is_group': isGroup,
      if (isChannel != null) 'is_channel': isChannel,
      if (isPersonal != null) 'is_personal': isPersonal,
      if (isFavorites != null) 'is_favorites': isFavorites,
      if (otherUserJson != null) 'other_user_json': otherUserJson,
      if (isEncrypted != null) 'is_encrypted': isEncrypted,
    });
  }

  ChatsCompanion copyWith(
      {Value<int>? id,
      Value<String>? serverChatId,
      Value<String>? name,
      Value<String?>? avatar,
      Value<String?>? avatarGradient,
      Value<String?>? lastMessage,
      Value<DateTime?>? lastMessageTime,
      Value<int>? unreadCount,
      Value<bool>? isGroup,
      Value<bool>? isChannel,
      Value<bool>? isPersonal,
      Value<bool>? isFavorites,
      Value<String?>? otherUserJson,
      Value<bool>? isEncrypted}) {
    return ChatsCompanion(
      id: id ?? this.id,
      serverChatId: serverChatId ?? this.serverChatId,
      name: name ?? this.name,
      avatar: avatar ?? this.avatar,
      avatarGradient: avatarGradient ?? this.avatarGradient,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      unreadCount: unreadCount ?? this.unreadCount,
      isGroup: isGroup ?? this.isGroup,
      isChannel: isChannel ?? this.isChannel,
      isPersonal: isPersonal ?? this.isPersonal,
      isFavorites: isFavorites ?? this.isFavorites,
      otherUserJson: otherUserJson ?? this.otherUserJson,
      isEncrypted: isEncrypted ?? this.isEncrypted,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverChatId.present) {
      map['server_chat_id'] = Variable<String>(serverChatId.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatar.present) {
      map['avatar'] = Variable<String>(avatar.value);
    }
    if (avatarGradient.present) {
      map['avatar_gradient'] = Variable<String>(avatarGradient.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (lastMessageTime.present) {
      map['last_message_time'] = Variable<DateTime>(lastMessageTime.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (isGroup.present) {
      map['is_group'] = Variable<bool>(isGroup.value);
    }
    if (isChannel.present) {
      map['is_channel'] = Variable<bool>(isChannel.value);
    }
    if (isPersonal.present) {
      map['is_personal'] = Variable<bool>(isPersonal.value);
    }
    if (isFavorites.present) {
      map['is_favorites'] = Variable<bool>(isFavorites.value);
    }
    if (otherUserJson.present) {
      map['other_user_json'] = Variable<String>(otherUserJson.value);
    }
    if (isEncrypted.present) {
      map['is_encrypted'] = Variable<bool>(isEncrypted.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatsCompanion(')
          ..write('id: $id, ')
          ..write('serverChatId: $serverChatId, ')
          ..write('name: $name, ')
          ..write('avatar: $avatar, ')
          ..write('avatarGradient: $avatarGradient, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isGroup: $isGroup, ')
          ..write('isChannel: $isChannel, ')
          ..write('isPersonal: $isPersonal, ')
          ..write('isFavorites: $isFavorites, ')
          ..write('otherUserJson: $otherUserJson, ')
          ..write('isEncrypted: $isEncrypted')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages with TableInfo<$MessagesTable, Message> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _serverMessageIdMeta =
      const VerificationMeta('serverMessageId');
  @override
  late final GeneratedColumn<String> serverMessageId = GeneratedColumn<String>(
      'server_message_id', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: true,
      defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'));
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<int> chatId = GeneratedColumn<int>(
      'chat_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: true,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('REFERENCES chats (id)'));
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _textContentMeta =
      const VerificationMeta('textContent');
  @override
  late final GeneratedColumn<String> textContent = GeneratedColumn<String>(
      'text_content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _fileUrlMeta =
      const VerificationMeta('fileUrl');
  @override
  late final GeneratedColumn<String> fileUrl = GeneratedColumn<String>(
      'file_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _timestampMeta =
      const VerificationMeta('timestamp');
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
      'timestamp', aliasedName, false,
      type: DriftSqlType.dateTime, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        serverMessageId,
        chatId,
        senderId,
        textContent,
        fileUrl,
        isRead,
        timestamp
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<Message> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('server_message_id')) {
      context.handle(
          _serverMessageIdMeta,
          serverMessageId.isAcceptableOrUnknown(
              data['server_message_id']!, _serverMessageIdMeta));
    } else if (isInserting) {
      context.missing(_serverMessageIdMeta);
    }
    if (data.containsKey('chat_id')) {
      context.handle(_chatIdMeta,
          chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta));
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('text_content')) {
      context.handle(
          _textContentMeta,
          textContent.isAcceptableOrUnknown(
              data['text_content']!, _textContentMeta));
    } else if (isInserting) {
      context.missing(_textContentMeta);
    }
    if (data.containsKey('file_url')) {
      context.handle(_fileUrlMeta,
          fileUrl.isAcceptableOrUnknown(data['file_url']!, _fileUrlMeta));
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    if (data.containsKey('timestamp')) {
      context.handle(_timestampMeta,
          timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta));
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Message map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Message(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      serverMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}server_message_id'])!,
      chatId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}chat_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_id'])!,
      textContent: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}text_content'])!,
      fileUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_url']),
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
      timestamp: attachedDatabase.typeMapping
          .read(DriftSqlType.dateTime, data['${effectivePrefix}timestamp'])!,
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class Message extends DataClass implements Insertable<Message> {
  final int id;
  final String serverMessageId;
  final int chatId;
  final String senderId;
  final String textContent;
  final String? fileUrl;
  final bool isRead;
  final DateTime timestamp;
  const Message(
      {required this.id,
      required this.serverMessageId,
      required this.chatId,
      required this.senderId,
      required this.textContent,
      this.fileUrl,
      required this.isRead,
      required this.timestamp});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['server_message_id'] = Variable<String>(serverMessageId);
    map['chat_id'] = Variable<int>(chatId);
    map['sender_id'] = Variable<String>(senderId);
    map['text_content'] = Variable<String>(textContent);
    if (!nullToAbsent || fileUrl != null) {
      map['file_url'] = Variable<String>(fileUrl);
    }
    map['is_read'] = Variable<bool>(isRead);
    map['timestamp'] = Variable<DateTime>(timestamp);
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      id: Value(id),
      serverMessageId: Value(serverMessageId),
      chatId: Value(chatId),
      senderId: Value(senderId),
      textContent: Value(textContent),
      fileUrl: fileUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(fileUrl),
      isRead: Value(isRead),
      timestamp: Value(timestamp),
    );
  }

  factory Message.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Message(
      id: serializer.fromJson<int>(json['id']),
      serverMessageId: serializer.fromJson<String>(json['serverMessageId']),
      chatId: serializer.fromJson<int>(json['chatId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      textContent: serializer.fromJson<String>(json['textContent']),
      fileUrl: serializer.fromJson<String?>(json['fileUrl']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'serverMessageId': serializer.toJson<String>(serverMessageId),
      'chatId': serializer.toJson<int>(chatId),
      'senderId': serializer.toJson<String>(senderId),
      'textContent': serializer.toJson<String>(textContent),
      'fileUrl': serializer.toJson<String?>(fileUrl),
      'isRead': serializer.toJson<bool>(isRead),
      'timestamp': serializer.toJson<DateTime>(timestamp),
    };
  }

  Message copyWith(
          {int? id,
          String? serverMessageId,
          int? chatId,
          String? senderId,
          String? textContent,
          Value<String?> fileUrl = const Value.absent(),
          bool? isRead,
          DateTime? timestamp}) =>
      Message(
        id: id ?? this.id,
        serverMessageId: serverMessageId ?? this.serverMessageId,
        chatId: chatId ?? this.chatId,
        senderId: senderId ?? this.senderId,
        textContent: textContent ?? this.textContent,
        fileUrl: fileUrl.present ? fileUrl.value : this.fileUrl,
        isRead: isRead ?? this.isRead,
        timestamp: timestamp ?? this.timestamp,
      );
  Message copyWithCompanion(MessagesCompanion data) {
    return Message(
      id: data.id.present ? data.id.value : this.id,
      serverMessageId: data.serverMessageId.present
          ? data.serverMessageId.value
          : this.serverMessageId,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      textContent:
          data.textContent.present ? data.textContent.value : this.textContent,
      fileUrl: data.fileUrl.present ? data.fileUrl.value : this.fileUrl,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Message(')
          ..write('id: $id, ')
          ..write('serverMessageId: $serverMessageId, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('textContent: $textContent, ')
          ..write('fileUrl: $fileUrl, ')
          ..write('isRead: $isRead, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, serverMessageId, chatId, senderId,
      textContent, fileUrl, isRead, timestamp);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Message &&
          other.id == this.id &&
          other.serverMessageId == this.serverMessageId &&
          other.chatId == this.chatId &&
          other.senderId == this.senderId &&
          other.textContent == this.textContent &&
          other.fileUrl == this.fileUrl &&
          other.isRead == this.isRead &&
          other.timestamp == this.timestamp);
}

class MessagesCompanion extends UpdateCompanion<Message> {
  final Value<int> id;
  final Value<String> serverMessageId;
  final Value<int> chatId;
  final Value<String> senderId;
  final Value<String> textContent;
  final Value<String?> fileUrl;
  final Value<bool> isRead;
  final Value<DateTime> timestamp;
  const MessagesCompanion({
    this.id = const Value.absent(),
    this.serverMessageId = const Value.absent(),
    this.chatId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.textContent = const Value.absent(),
    this.fileUrl = const Value.absent(),
    this.isRead = const Value.absent(),
    this.timestamp = const Value.absent(),
  });
  MessagesCompanion.insert({
    this.id = const Value.absent(),
    required String serverMessageId,
    required int chatId,
    required String senderId,
    required String textContent,
    this.fileUrl = const Value.absent(),
    this.isRead = const Value.absent(),
    required DateTime timestamp,
  })  : serverMessageId = Value(serverMessageId),
        chatId = Value(chatId),
        senderId = Value(senderId),
        textContent = Value(textContent),
        timestamp = Value(timestamp);
  static Insertable<Message> custom({
    Expression<int>? id,
    Expression<String>? serverMessageId,
    Expression<int>? chatId,
    Expression<String>? senderId,
    Expression<String>? textContent,
    Expression<String>? fileUrl,
    Expression<bool>? isRead,
    Expression<DateTime>? timestamp,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (serverMessageId != null) 'server_message_id': serverMessageId,
      if (chatId != null) 'chat_id': chatId,
      if (senderId != null) 'sender_id': senderId,
      if (textContent != null) 'text_content': textContent,
      if (fileUrl != null) 'file_url': fileUrl,
      if (isRead != null) 'is_read': isRead,
      if (timestamp != null) 'timestamp': timestamp,
    });
  }

  MessagesCompanion copyWith(
      {Value<int>? id,
      Value<String>? serverMessageId,
      Value<int>? chatId,
      Value<String>? senderId,
      Value<String>? textContent,
      Value<String?>? fileUrl,
      Value<bool>? isRead,
      Value<DateTime>? timestamp}) {
    return MessagesCompanion(
      id: id ?? this.id,
      serverMessageId: serverMessageId ?? this.serverMessageId,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      textContent: textContent ?? this.textContent,
      fileUrl: fileUrl ?? this.fileUrl,
      isRead: isRead ?? this.isRead,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (serverMessageId.present) {
      map['server_message_id'] = Variable<String>(serverMessageId.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<int>(chatId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (textContent.present) {
      map['text_content'] = Variable<String>(textContent.value);
    }
    if (fileUrl.present) {
      map['file_url'] = Variable<String>(fileUrl.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('id: $id, ')
          ..write('serverMessageId: $serverMessageId, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('textContent: $textContent, ')
          ..write('fileUrl: $fileUrl, ')
          ..write('isRead: $isRead, ')
          ..write('timestamp: $timestamp')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ChatsTable chats = $ChatsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [chats, messages];
}

typedef $$ChatsTableCreateCompanionBuilder = ChatsCompanion Function({
  Value<int> id,
  required String serverChatId,
  required String name,
  Value<String?> avatar,
  Value<String?> avatarGradient,
  Value<String?> lastMessage,
  Value<DateTime?> lastMessageTime,
  Value<int> unreadCount,
  Value<bool> isGroup,
  Value<bool> isChannel,
  Value<bool> isPersonal,
  Value<bool> isFavorites,
  Value<String?> otherUserJson,
  Value<bool> isEncrypted,
});
typedef $$ChatsTableUpdateCompanionBuilder = ChatsCompanion Function({
  Value<int> id,
  Value<String> serverChatId,
  Value<String> name,
  Value<String?> avatar,
  Value<String?> avatarGradient,
  Value<String?> lastMessage,
  Value<DateTime?> lastMessageTime,
  Value<int> unreadCount,
  Value<bool> isGroup,
  Value<bool> isChannel,
  Value<bool> isPersonal,
  Value<bool> isFavorites,
  Value<String?> otherUserJson,
  Value<bool> isEncrypted,
});

final class $$ChatsTableReferences
    extends BaseReferences<_$AppDatabase, $ChatsTable, Chat> {
  $$ChatsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$MessagesTable, List<Message>> _messagesRefsTable(
          _$AppDatabase db) =>
      MultiTypedResultKey.fromTable(db.messages,
          aliasName: $_aliasNameGenerator(db.chats.id, db.messages.chatId));

  $$MessagesTableProcessedTableManager get messagesRefs {
    final manager = $$MessagesTableTableManager($_db, $_db.messages)
        .filter((f) => f.chatId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_messagesRefsTable($_db));
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: cache));
  }
}

class $$ChatsTableFilterComposer extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverChatId => $composableBuilder(
      column: $table.serverChatId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avatar => $composableBuilder(
      column: $table.avatar, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avatarGradient => $composableBuilder(
      column: $table.avatarGradient,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isGroup => $composableBuilder(
      column: $table.isGroup, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isChannel => $composableBuilder(
      column: $table.isChannel, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPersonal => $composableBuilder(
      column: $table.isPersonal, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFavorites => $composableBuilder(
      column: $table.isFavorites, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get otherUserJson => $composableBuilder(
      column: $table.otherUserJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEncrypted => $composableBuilder(
      column: $table.isEncrypted, builder: (column) => ColumnFilters(column));

  Expression<bool> messagesRefs(
      Expression<bool> Function($$MessagesTableFilterComposer f) f) {
    final $$MessagesTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.chatId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableFilterComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ChatsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverChatId => $composableBuilder(
      column: $table.serverChatId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avatar => $composableBuilder(
      column: $table.avatar, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avatarGradient => $composableBuilder(
      column: $table.avatarGradient,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isGroup => $composableBuilder(
      column: $table.isGroup, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isChannel => $composableBuilder(
      column: $table.isChannel, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPersonal => $composableBuilder(
      column: $table.isPersonal, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFavorites => $composableBuilder(
      column: $table.isFavorites, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get otherUserJson => $composableBuilder(
      column: $table.otherUserJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEncrypted => $composableBuilder(
      column: $table.isEncrypted, builder: (column) => ColumnOrderings(column));
}

class $$ChatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverChatId => $composableBuilder(
      column: $table.serverChatId, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatar =>
      $composableBuilder(column: $table.avatar, builder: (column) => column);

  GeneratedColumn<String> get avatarGradient => $composableBuilder(
      column: $table.avatarGradient, builder: (column) => column);

  GeneratedColumn<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => column);

  GeneratedColumn<DateTime> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => column);

  GeneratedColumn<bool> get isGroup =>
      $composableBuilder(column: $table.isGroup, builder: (column) => column);

  GeneratedColumn<bool> get isChannel =>
      $composableBuilder(column: $table.isChannel, builder: (column) => column);

  GeneratedColumn<bool> get isPersonal => $composableBuilder(
      column: $table.isPersonal, builder: (column) => column);

  GeneratedColumn<bool> get isFavorites => $composableBuilder(
      column: $table.isFavorites, builder: (column) => column);

  GeneratedColumn<String> get otherUserJson => $composableBuilder(
      column: $table.otherUserJson, builder: (column) => column);

  GeneratedColumn<bool> get isEncrypted => $composableBuilder(
      column: $table.isEncrypted, builder: (column) => column);

  Expression<T> messagesRefs<T extends Object>(
      Expression<T> Function($$MessagesTableAnnotationComposer a) f) {
    final $$MessagesTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.id,
        referencedTable: $db.messages,
        getReferencedColumn: (t) => t.chatId,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$MessagesTableAnnotationComposer(
              $db: $db,
              $table: $db.messages,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return f(composer);
  }
}

class $$ChatsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChatsTable,
    Chat,
    $$ChatsTableFilterComposer,
    $$ChatsTableOrderingComposer,
    $$ChatsTableAnnotationComposer,
    $$ChatsTableCreateCompanionBuilder,
    $$ChatsTableUpdateCompanionBuilder,
    (Chat, $$ChatsTableReferences),
    Chat,
    PrefetchHooks Function({bool messagesRefs})> {
  $$ChatsTableTableManager(_$AppDatabase db, $ChatsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> serverChatId = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> avatar = const Value.absent(),
            Value<String?> avatarGradient = const Value.absent(),
            Value<String?> lastMessage = const Value.absent(),
            Value<DateTime?> lastMessageTime = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isGroup = const Value.absent(),
            Value<bool> isChannel = const Value.absent(),
            Value<bool> isPersonal = const Value.absent(),
            Value<bool> isFavorites = const Value.absent(),
            Value<String?> otherUserJson = const Value.absent(),
            Value<bool> isEncrypted = const Value.absent(),
          }) =>
              ChatsCompanion(
            id: id,
            serverChatId: serverChatId,
            name: name,
            avatar: avatar,
            avatarGradient: avatarGradient,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageTime,
            unreadCount: unreadCount,
            isGroup: isGroup,
            isChannel: isChannel,
            isPersonal: isPersonal,
            isFavorites: isFavorites,
            otherUserJson: otherUserJson,
            isEncrypted: isEncrypted,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String serverChatId,
            required String name,
            Value<String?> avatar = const Value.absent(),
            Value<String?> avatarGradient = const Value.absent(),
            Value<String?> lastMessage = const Value.absent(),
            Value<DateTime?> lastMessageTime = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isGroup = const Value.absent(),
            Value<bool> isChannel = const Value.absent(),
            Value<bool> isPersonal = const Value.absent(),
            Value<bool> isFavorites = const Value.absent(),
            Value<String?> otherUserJson = const Value.absent(),
            Value<bool> isEncrypted = const Value.absent(),
          }) =>
              ChatsCompanion.insert(
            id: id,
            serverChatId: serverChatId,
            name: name,
            avatar: avatar,
            avatarGradient: avatarGradient,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageTime,
            unreadCount: unreadCount,
            isGroup: isGroup,
            isChannel: isChannel,
            isPersonal: isPersonal,
            isFavorites: isFavorites,
            otherUserJson: otherUserJson,
            isEncrypted: isEncrypted,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$ChatsTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({messagesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (messagesRefs) db.messages],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (messagesRefs)
                    await $_getPrefetchedData<Chat, $ChatsTable, Message>(
                        currentTable: table,
                        referencedTable:
                            $$ChatsTableReferences._messagesRefsTable(db),
                        managerFromTypedResult: (p0) =>
                            $$ChatsTableReferences(db, table, p0).messagesRefs,
                        referencedItemsForCurrentItem: (item,
                                referencedItems) =>
                            referencedItems.where((e) => e.chatId == item.id),
                        typedResults: items)
                ];
              },
            );
          },
        ));
}

typedef $$ChatsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChatsTable,
    Chat,
    $$ChatsTableFilterComposer,
    $$ChatsTableOrderingComposer,
    $$ChatsTableAnnotationComposer,
    $$ChatsTableCreateCompanionBuilder,
    $$ChatsTableUpdateCompanionBuilder,
    (Chat, $$ChatsTableReferences),
    Chat,
    PrefetchHooks Function({bool messagesRefs})>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  required String serverMessageId,
  required int chatId,
  required String senderId,
  required String textContent,
  Value<String?> fileUrl,
  Value<bool> isRead,
  required DateTime timestamp,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<int> id,
  Value<String> serverMessageId,
  Value<int> chatId,
  Value<String> senderId,
  Value<String> textContent,
  Value<String?> fileUrl,
  Value<bool> isRead,
  Value<DateTime> timestamp,
});

final class $$MessagesTableReferences
    extends BaseReferences<_$AppDatabase, $MessagesTable, Message> {
  $$MessagesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $ChatsTable _chatIdTable(_$AppDatabase db) => db.chats
      .createAlias($_aliasNameGenerator(db.messages.chatId, db.chats.id));

  $$ChatsTableProcessedTableManager get chatId {
    final $_column = $_itemColumn<int>('chat_id')!;

    final manager = $$ChatsTableTableManager($_db, $_db.chats)
        .filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_chatIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
        manager.$state.copyWith(prefetchedData: [item]));
  }
}

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverMessageId => $composableBuilder(
      column: $table.serverMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get textContent => $composableBuilder(
      column: $table.textContent, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileUrl => $composableBuilder(
      column: $table.fileUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnFilters(column));

  $$ChatsTableFilterComposer get chatId {
    final $$ChatsTableFilterComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.chatId,
        referencedTable: $db.chats,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChatsTableFilterComposer(
              $db: $db,
              $table: $db.chats,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverMessageId => $composableBuilder(
      column: $table.serverMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get textContent => $composableBuilder(
      column: $table.textContent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileUrl => $composableBuilder(
      column: $table.fileUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
      column: $table.timestamp, builder: (column) => ColumnOrderings(column));

  $$ChatsTableOrderingComposer get chatId {
    final $$ChatsTableOrderingComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.chatId,
        referencedTable: $db.chats,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChatsTableOrderingComposer(
              $db: $db,
              $table: $db.chats,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get serverMessageId => $composableBuilder(
      column: $table.serverMessageId, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get textContent => $composableBuilder(
      column: $table.textContent, builder: (column) => column);

  GeneratedColumn<String> get fileUrl =>
      $composableBuilder(column: $table.fileUrl, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  $$ChatsTableAnnotationComposer get chatId {
    final $$ChatsTableAnnotationComposer composer = $composerBuilder(
        composer: this,
        getCurrentColumn: (t) => t.chatId,
        referencedTable: $db.chats,
        getReferencedColumn: (t) => t.id,
        builder: (joinBuilder,
                {$addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer}) =>
            $$ChatsTableAnnotationComposer(
              $db: $db,
              $table: $db.chats,
              $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
              joinBuilder: joinBuilder,
              $removeJoinBuilderFromRootComposer:
                  $removeJoinBuilderFromRootComposer,
            ));
    return composer;
  }
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, $$MessagesTableReferences),
    Message,
    PrefetchHooks Function({bool chatId})> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> serverMessageId = const Value.absent(),
            Value<int> chatId = const Value.absent(),
            Value<String> senderId = const Value.absent(),
            Value<String> textContent = const Value.absent(),
            Value<String?> fileUrl = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<DateTime> timestamp = const Value.absent(),
          }) =>
              MessagesCompanion(
            id: id,
            serverMessageId: serverMessageId,
            chatId: chatId,
            senderId: senderId,
            textContent: textContent,
            fileUrl: fileUrl,
            isRead: isRead,
            timestamp: timestamp,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String serverMessageId,
            required int chatId,
            required String senderId,
            required String textContent,
            Value<String?> fileUrl = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            required DateTime timestamp,
          }) =>
              MessagesCompanion.insert(
            id: id,
            serverMessageId: serverMessageId,
            chatId: chatId,
            senderId: senderId,
            textContent: textContent,
            fileUrl: fileUrl,
            isRead: isRead,
            timestamp: timestamp,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) =>
                  (e.readTable(table), $$MessagesTableReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: ({chatId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins: <
                  T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic>>(state) {
                if (chatId) {
                  state = state.withJoin(
                    currentTable: table,
                    currentColumn: table.chatId,
                    referencedTable: $$MessagesTableReferences._chatIdTable(db),
                    referencedColumn:
                        $$MessagesTableReferences._chatIdTable(db).id,
                  ) as T;
                }

                return state;
              },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    Message,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (Message, $$MessagesTableReferences),
    Message,
    PrefetchHooks Function({bool chatId})>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ChatsTableTableManager get chats =>
      $$ChatsTableTableManager(_db, _db.chats);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
}
