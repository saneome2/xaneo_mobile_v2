import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/chat/chat_model.dart';
import '../../widgets/common/avatar_widget.dart';

/// Экран подробной информации о чате (собеседник, группа, канал, бот, избранное).
/// Открывается из модалки ChatInfoModal с использованием Hero-анимации.
class ChatInfoScreen extends StatefulWidget {
  final ChatModel chat;

  const ChatInfoScreen({
    super.key,
    required this.chat,
  });

  @override
  State<ChatInfoScreen> createState() => _ChatInfoScreenState();
}

class _ChatInfoScreenState extends State<ChatInfoScreen> {
  int _selectedTabIndex = 0;

  final List<Map<String, dynamic>> _tabs = [
    {'title': 'Медиа', 'count': '14', 'icon': Icons.image_rounded},
    {'title': 'Файлы', 'count': '3', 'icon': Icons.description_rounded},
    {'title': 'Голос', 'count': '8', 'icon': Icons.mic_rounded},
    {'title': 'Ссылки', 'count': '11', 'icon': Icons.link_rounded},
  ];

  @override
  Widget build(BuildContext context) {
    final chat = widget.chat;
    final otherUser = chat.otherUser;

    // Свойства пользователя/чата
    final String? username = otherUser?['username']?.toString();
    final String? phone = otherUser?['phone']?.toString();
    
    // Получение описания
    String? bio;
    if (chat.isFavorites) {
      bio = 'Ваше личное хранилище для заметок, медиафайлов и важных сообщений. Все данные зашифрованы сквозным шифрованием (E2EE).';
    } else {
      bio = otherUser?['bio']?.toString() ?? 
            otherUser?['description']?.toString() ?? 
            otherUser?['about']?.toString();
    }

    final colors = _parseGradientColors(chat.avatarGradient);
    final primaryColor = colors.first;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0E), // Ultra dark background
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // Сворачиваемая шапка с аватаркой и градиентным размытием
          SliverAppBar(
            expandedHeight: 340,
            pinned: true,
            stretch: true,
            backgroundColor: const Color(0xFF141416),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 20),
              onPressed: () => Navigator.of(context).pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              stretchModes: const [
                StretchMode.zoomBackground,
                StretchMode.blurBackground,
              ],
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Задний градиентный фон с размытием
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          primaryColor.withOpacity(0.15),
                          const Color(0xFF0D0D0E),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                  // Центрированное содержимое
                  SafeArea(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 40),
                        // Аватар (крупный с Hero-анимацией)
                        Hero(
                          tag: 'chat_avatar_${chat.id}',
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: primaryColor.withOpacity(0.2),
                                  blurRadius: 40,
                                  spreadRadius: 6,
                                ),
                              ],
                            ),
                            child: AvatarWidget(
                              avatar: chat.avatar,
                              avatarGradient: chat.avatarGradient,
                              hasAvatar: chat.avatar != null && chat.avatar!.isNotEmpty,
                              username: chat.name,
                              size: 120, // Больший размер для экрана
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Имя (Hero-анимация)
                        Hero(
                          tag: 'chat_name_${chat.id}',
                          child: Material(
                            color: Colors.transparent,
                            child: Text(
                              chat.name,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: -0.5,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // Статус
                        _buildStatusWidget(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Контентная часть
          SliverPadding(
            padding: const EdgeInsets.only(left: 20, right: 20, top: 20, bottom: 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // 1. Блок детальной информации
                Hero(
                  tag: 'chat_details_${chat.id}',
                  child: Material(
                    color: Colors.transparent,
                    child: _buildDetailsSection(username, phone, bio),
                  ),
                ),
                const SizedBox(height: 28),

                // 2. Вкладки общих материалов
                Hero(
                  tag: 'chat_tabs_${chat.id}',
                  child: Material(
                    color: Colors.transparent,
                    child: _buildSharedMediaTabs(),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  /// Парсит градиент из строки
  List<Color> _parseGradientColors(String? gradient) {
    if (gradient == null || gradient.isEmpty) {
      return [const Color(0xFF3A3A3A), const Color(0xFF1A1A1A)];
    }
    try {
      final parts = gradient.split(RegExp(r'[,|]'));
      return parts.map((part) {
        var colorStr = part.trim();
        if (colorStr.startsWith('#')) {
          colorStr = colorStr.substring(1);
        }
        return Color(int.parse('FF$colorStr', radix: 16));
      }).toList();
    } catch (_) {
      return [const Color(0xFF3A3A3A), const Color(0xFF1A1A1A)];
    }
  }

  /// Возвращает статус
  Widget _buildStatusWidget() {
    final chat = widget.chat;
    String text = '';
    Color textColor = Colors.white70;
    IconData? icon;

    if (chat.isFavorites) {
      text = 'персональное облако';
      textColor = Colors.white;
      icon = Icons.cloud_done_rounded;
    } else if (_isDeleted()) {
      text = 'удалённый аккаунт';
      textColor = Colors.white38;
    } else if (chat.isPersonal) {
      if (_isBot()) {
        text = 'бот';
        textColor = const Color(0xFF60A5FA);
        icon = Icons.android_rounded;
      } else {
        text = _formatUserStatus(chat.otherUser);
        if (text == 'в сети') {
          textColor = const Color(0xFF4ADE80);
        }
      }
    } else if (chat.isGroup) {
      final membersCount = chat.otherUser?['members_count'] as int? ?? 0;
      final onlineCount = chat.otherUser?['online_count'] as int? ?? 0;
      text = _pluralizeParticipants(membersCount);
      if (onlineCount > 0) {
        text += ', $onlineCount в сети';
      }
      textColor = Colors.white54;
      icon = Icons.people_alt_rounded;
    } else if (chat.isChannel) {
      final subscribersCount = chat.otherUser?['subscribers_count'] as int? ?? 0;
      text = _formatSubscribers(subscribersCount);
      textColor = Colors.white54;
      icon = Icons.campaign_rounded;
    }

    if (text.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      decoration: BoxDecoration(
        color: textColor.withOpacity(0.06),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: textColor.withOpacity(0.1),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: textColor),
            const SizedBox(width: 6),
          ] else if (text == 'в сети') ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                color: textColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: textColor.withOpacity(0.5),
                    blurRadius: 4,
                    spreadRadius: 1,
                  )
                ],
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: textColor.withOpacity(0.9),
            ),
          ),
        ],
      ),
    );
  }

  /// Блок детальной информации
  Widget _buildDetailsSection(String? username, String? phone, String? bio) {
    final hasBio = bio != null && bio.isNotEmpty;
    final hasPhone = phone != null && phone.isNotEmpty;
    final hasUsername = username != null && username.isNotEmpty;

    if (!hasBio && !hasPhone && !hasUsername) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: Colors.white.withOpacity(0.03),
          width: 1.5,
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          if (hasBio) ...[
            _buildInfoTile(
              icon: Icons.info_outline_rounded,
              value: bio,
              label: widget.chat.isGroup || widget.chat.isChannel ? 'Описание' : 'О себе',
            ),
            if (hasPhone || hasUsername) _buildDivider(),
          ],
          if (hasPhone) ...[
            _buildInfoTile(
              icon: Icons.phone_outlined,
              value: phone,
              label: 'Мобильный',
            ),
            if (hasUsername) _buildDivider(),
          ],
          if (hasUsername) ...[
            _buildInfoTile(
              icon: Icons.alternate_email_rounded,
              value: username.startsWith('@') ? username : '@$username',
              label: 'Имя пользователя',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDivider() {
    return Divider(
      color: Colors.white.withOpacity(0.04),
      height: 1,
      indent: 52,
    );
  }

  Widget _buildInfoTile({
    required IconData icon,
    required String value,
    required String label,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"$value" скопировано в буфер'),
              duration: const Duration(seconds: 1),
              backgroundColor: const Color(0xFF1E1E22),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.04),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: Colors.white70, size: 18),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      value,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14.5,
                        fontWeight: FontWeight.w500,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Icon(
                  Icons.copy_rounded,
                  color: Colors.white.withOpacity(0.2),
                  size: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Раздел "Общие материалы" в виде табов
  Widget _buildSharedMediaTabs() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            'Общие материалы',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: Colors.white.withOpacity(0.04),
              width: 1,
            ),
          ),
          child: Row(
            children: List.generate(_tabs.length, (index) {
              final tab = _tabs[index];
              final isSelected = _selectedTabIndex == index;
              return Expanded(
                child: GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedTabIndex = index;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.white.withOpacity(0.06) : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    alignment: Alignment.center,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          tab['title'].toString(),
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.white.withOpacity(0.4),
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.white.withOpacity(0.12) : Colors.white.withOpacity(0.04),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tab['count'].toString(),
                            style: TextStyle(
                              color: isSelected ? Colors.white70 : Colors.white.withOpacity(0.3),
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: 16),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: _buildTabContent(_selectedTabIndex),
        ),
      ],
    );
  }

  Widget _buildTabContent(int index) {
    final tab = _tabs[index];
    return Container(
      key: ValueKey<int>(index),
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.01),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.white.withOpacity(0.02),
          width: 1.5,
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              shape: BoxShape.circle,
            ),
            child: Icon(
              tab['icon'] as IconData,
              color: Colors.white.withOpacity(0.18),
              size: 24,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Нет общих файлов',
            style: TextStyle(
              color: Colors.white.withOpacity(0.6),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            'Здесь будут отображаться ваши ${tab['title'].toString().toLowerCase()}',
            style: TextStyle(
              color: Colors.white.withOpacity(0.35),
              fontSize: 11.5,
            ),
          ),
        ],
      ),
    );
  }

  // --- Вспомогательные методы ---
  bool _isBot() {
    final otherUser = widget.chat.otherUser;
    if (otherUser == null) return false;
    final isBotVal = otherUser['is_bot'];
    if (isBotVal is bool) return isBotVal;
    if (isBotVal is String) return isBotVal.toLowerCase() == 'true';
    final username = otherUser['username']?.toString() ?? '';
    return username.toLowerCase().endsWith('bot');
  }

  bool _isDeleted() {
    final otherUser = widget.chat.otherUser;
    if (otherUser == null) return false;
    final isDeletedVal = otherUser['is_deleted'];
    if (isDeletedVal is bool) return isDeletedVal;
    if (isDeletedVal is String) return isDeletedVal.toLowerCase() == 'true';
    return false;
  }

  String _formatUserStatus(Map<String, dynamic>? otherUser) {
    if (otherUser == null) return 'был(-а) недавно';
    
    final isOnlineVal = otherUser['is_online'] ?? otherUser['online'];
    if (isOnlineVal == true || isOnlineVal?.toString().toLowerCase() == 'true') {
      return 'в сети';
    }
    
    final lastSeenVal = otherUser['last_seen'] ?? otherUser['last_login'] ?? otherUser['last_activity'];
    if (lastSeenVal == null) return 'был(-а) недавно';
    
    DateTime? lastSeen;
    if (lastSeenVal is String) {
      lastSeen = DateTime.tryParse(lastSeenVal);
    } else if (lastSeenVal is int) {
      lastSeen = DateTime.fromMillisecondsSinceEpoch(lastSeenVal);
    } else if (lastSeenVal is DateTime) {
      lastSeen = lastSeenVal;
    }
    
    if (lastSeen == null) return 'был(-а) недавно';
    
    final now = DateTime.now();
    final difference = now.difference(lastSeen);
    
    if (difference.inMinutes < 5) {
      return 'в сети';
    }
    
    if (difference.inMinutes < 60) {
      final mins = difference.inMinutes;
      String minStr;
      if (mins % 10 == 1 && mins % 100 != 11) {
        minStr = 'минуту';
      } else if ([2, 3, 4].contains(mins % 10) && ![12, 13, 14].contains(mins % 100)) {
        minStr = 'минуты';
      } else {
        minStr = 'минут';
      }
      return 'был(-а) в сети $mins $minStr назад';
    }
    
    final today = DateTime(now.year, now.month, now.day);
    final lastSeenDay = DateTime(lastSeen.year, lastSeen.month, lastSeen.day);
    
    final hour = lastSeen.hour.toString().padLeft(2, '0');
    final minute = lastSeen.minute.toString().padLeft(2, '0');
    
    if (lastSeenDay == today) {
      return 'был(-а) в сети сегодня в $hour:$minute';
    }
    
    final yesterday = today.subtract(const Duration(days: 1));
    if (lastSeenDay == yesterday) {
      return 'был(-а) в сети вчера в $hour:$minute';
    }
    
    final day = lastSeen.day.toString().padLeft(2, '0');
    final month = lastSeen.month.toString().padLeft(2, '0');
    return 'был(-а) в сети $day.$month.${lastSeen.year} в $hour:$minute';
  }

  String _pluralizeParticipants(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return '$count участник';
    } else if ([2, 3, 4].contains(count % 10) && ![12, 13, 14].contains(count % 100)) {
      return '$count участника';
    } else {
      return '$count участников';
    }
  }

  String _formatSubscribers(int count) {
    String countStr;
    if (count >= 1000000000) {
      countStr = '${(count / 1000000000.0).toStringAsFixed(1).replaceAll('.0', '')}B';
    } else if (count >= 1000000) {
      countStr = '${(count / 1000000.0).toStringAsFixed(1).replaceAll('.0', '')}M';
    } else if (count >= 1000) {
      countStr = '${(count / 1000.0).toStringAsFixed(1).replaceAll('.0', '')}K';
    } else {
      countStr = count.toString();
    }

    if (count % 10 == 1 && count % 100 != 11) {
      return '$countStr подписчик';
    } else if ([2, 3, 4].contains(count % 10) && ![12, 13, 14].contains(count % 100)) {
      return '$countStr подписчика';
    } else {
      return '$countStr подписчиков';
    }
  }
}
