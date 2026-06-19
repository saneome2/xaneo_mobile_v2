import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:drift/drift.dart' hide Column;
import '../../../services/database/app_database.dart';
import '../../../services/chat/chat_local_repository.dart';
import '../../../services/chat/chat_websocket_service.dart';
import '../../../styles/app_styles.dart';

class TodoListWidget extends StatelessWidget {
  final Message message;
  final ChatWebSocketService chatWebSocketService;
  final LocalChatRepository localChatRepo;
  final VoidCallback onStateChanged;

  const TodoListWidget({
    super.key,
    required this.message,
    required this.chatWebSocketService,
    required this.localChatRepo,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    String title = 'Список задач';
    List<dynamic> items = [];

    // Parse todo list structure from decrypted textContent
    try {
      final parsed = jsonDecode(message.textContent);
      if (parsed is Map) {
        title = parsed['title']?.toString() ?? 'Список задач';
        items = parsed['items'] as List<dynamic>? ?? [];
      }
    } catch (_) {}

    // Parse completion status
    Map<String, dynamic> completionStatus = {};
    if (message.completionStatus != null && message.completionStatus!.isNotEmpty) {
      try {
        completionStatus = Map<String, dynamic>.from(jsonDecode(message.completionStatus!));
      } catch (_) {}
    }

    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const FaIcon(
                FontAwesomeIcons.clipboardList,
                size: 16,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppStyles.fontFamily,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Items list
          ...List.generate(items.length, (index) {
            final item = items[index];
            final itemText = (item is Map ? item['text'] : item.toString()) ?? '';
            final isCompleted = completionStatus[index.toString()] == true;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: GestureDetector(
                onTap: () => _toggleItem(index, isCompleted),
                behavior: HitTestBehavior.opaque,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Premium Custom Animated Checkbox
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      curve: Curves.easeInOut,
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isCompleted ? Colors.white : Colors.transparent,
                        border: Border.all(
                          color: isCompleted ? Colors.white : Colors.white54,
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: AnimatedScale(
                          scale: isCompleted ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 150),
                          child: const Icon(
                            Icons.check,
                            color: Colors.black,
                            size: 13,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    // Item text (strike-through when completed)
                    Expanded(
                      child: Text(
                        itemText,
                        style: TextStyle(
                          color: isCompleted ? Colors.white.withValues(alpha: 0.4) : Colors.white,
                          fontSize: 13.5,
                          decoration: isCompleted ? TextDecoration.lineThrough : null,
                          decorationColor: Colors.white.withValues(alpha: 0.4),
                          fontFamily: AppStyles.fontFamily,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _toggleItem(int index, bool currentCompleted) async {
    final nextCompleted = !currentCompleted;

    // 1. Optimistic local DB update for zero-latency toggle
    Map<String, dynamic> currentStatus = {};
    if (message.completionStatus != null && message.completionStatus!.isNotEmpty) {
      try {
        currentStatus = Map<String, dynamic>.from(jsonDecode(message.completionStatus!));
      } catch (_) {}
    }

    currentStatus[index.toString()] = nextCompleted;

    await localChatRepo.updateMessageCompanion(
      MessagesCompanion(
        serverMessageId: Value(message.serverMessageId),
        completionStatus: Value(jsonEncode(currentStatus)),
      ),
    );

    // Refresh UI immediately
    onStateChanged();

    // 2. Dispatch the update to WebSocket server
    await chatWebSocketService.send({
      'type': 'todo_completion_update',
      'todo_message_id': message.messageId,
      'item_index': index,
      'is_completed': nextCompleted,
    });
  }
}

class PollWidget extends StatelessWidget {
  final Message message;
  final ChatWebSocketService chatWebSocketService;
  final LocalChatRepository localChatRepo;
  final VoidCallback onStateChanged;

  const PollWidget({
    super.key,
    required this.message,
    required this.chatWebSocketService,
    required this.localChatRepo,
    required this.onStateChanged,
  });

  @override
  Widget build(BuildContext context) {
    String question = 'Опрос';
    List<dynamic> options = [];
    bool isMultipleChoice = false;

    // Parse question and options from decrypted textContent
    try {
      final parsed = jsonDecode(message.textContent);
      if (parsed is Map) {
        question = parsed['question']?.toString() ?? 'Опрос';
        options = parsed['options'] as List<dynamic>? ?? [];
        isMultipleChoice = parsed['is_multiple_choice'] == true;
      }
    } catch (_) {}

    // Parse votes map
    Map<String, dynamic> votesByOption = {};
    if (message.votesByOption != null && message.votesByOption!.isNotEmpty) {
      try {
        votesByOption = Map<String, dynamic>.from(jsonDecode(message.votesByOption!));
      } catch (_) {}
    }

    // Parse user votes (options voted by current user)
    List<String> userVotes = [];
    if (message.userVotes != null && message.userVotes!.isNotEmpty) {
      try {
        userVotes = List<String>.from(jsonDecode(message.userVotes!));
      } catch (_) {}
    }

    // Calculate total votes count
    int totalVotes = 0;
    votesByOption.values.forEach((v) {
      if (v is num) {
        totalVotes += v.toInt();
      } else {
        totalVotes += int.tryParse(v.toString()) ?? 0;
      }
    });

    final hasVoted = userVotes.isNotEmpty;

    return Container(
      width: 250,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Poll question
          Text(
            question,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15.5,
              fontWeight: FontWeight.w600,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            isMultipleChoice ? 'Множественный выбор' : 'Одиночный выбор',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 10.5,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
          const SizedBox(height: 12),
          // Options
          ...List.generate(options.length, (index) {
            final option = options[index];
            final optionId = option['id']?.toString() ?? '';
            final optionText = option['text']?.toString() ?? '';

            // Vote statistics
            final rawVotes = votesByOption[optionId];
            final optionVotes = rawVotes is num ? rawVotes.toInt() : (int.tryParse(rawVotes?.toString() ?? '') ?? 0);
            final double percent = totalVotes > 0 ? (optionVotes / totalVotes) : 0.0;
            final percentText = '${(percent * 100).round()}%';
            final isSelected = userVotes.contains(optionId);

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4.0),
              child: GestureDetector(
                onTap: () => _toggleVote(optionId, isSelected, isMultipleChoice),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Stack(
                    children: [
                      // Animate custom progress background overlay (Telegram-like)
                      Positioned.fill(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: AnimatedFractionallySizedBox(
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeOutCubic,
                            widthFactor: percent,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOutCubic,
                              color: Colors.white.withValues(
                                alpha: isSelected ? 0.16 : 0.06,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Option content row
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOutCubic,
                        padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 10),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.3)
                                : Colors.white.withValues(alpha: 0.06),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            // Selection state indicator (check or empty with AnimatedSize)
                            AnimatedSize(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSelected) ...[
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      color: Colors.white,
                                      size: 14,
                                    ),
                                    const SizedBox(width: 6),
                                  ],
                                ],
                              ),
                            ),
                            // Option text
                            Expanded(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeOutCubic,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13.5,
                                  fontWeight: isSelected ? FontWeight.w500 : FontWeight.w400,
                                  fontFamily: AppStyles.fontFamily,
                                ),
                                child: Text(optionText),
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Percent text on the right
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white.withValues(alpha: 0.5),
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                fontFamily: AppStyles.fontFamily,
                              ),
                              child: Text(percentText),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          // Footer vote count
          Text(
            totalVotes == 0
                ? 'Нет голосов'
                : '$totalVotes ${_formatVotesCountText(totalVotes)}',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontFamily: AppStyles.fontFamily,
            ),
          ),
        ],
      ),
    );
  }

  String _formatVotesCountText(int count) {
    if (count % 10 == 1 && count % 100 != 11) {
      return 'голос';
    } else if ((count % 10 >= 2 && count % 10 <= 4) && (count % 100 < 10 || count % 100 >= 20)) {
      return 'голоса';
    } else {
      return 'голосов';
    }
  }

  Future<void> _toggleVote(String optionId, bool isSelected, bool isMultipleChoice) async {
    // 1. Optimistic local updates for zero latency
    List<String> userVotes = [];
    if (message.userVotes != null && message.userVotes!.isNotEmpty) {
      try {
        userVotes = List<String>.from(jsonDecode(message.userVotes!));
      } catch (_) {}
    }

    Map<String, dynamic> votesByOption = {};
    if (message.votesByOption != null && message.votesByOption!.isNotEmpty) {
      try {
        votesByOption = Map<String, dynamic>.from(jsonDecode(message.votesByOption!));
      } catch (_) {}
    }

    if (isSelected) {
      // Unvote option
      userVotes.remove(optionId);
      final c = votesByOption[optionId] ?? 0;
      votesByOption[optionId] = (c is num ? c.toInt() - 1 : (int.tryParse(c.toString()) ?? 1) - 1).clamp(0, 999999);
    } else {
      // Vote option
      if (!isMultipleChoice) {
        // Clear previous votes in single choice mode
        for (final prevOptionId in userVotes) {
          final c = votesByOption[prevOptionId] ?? 0;
          votesByOption[prevOptionId] = (c is num ? c.toInt() - 1 : (int.tryParse(c.toString()) ?? 1) - 1).clamp(0, 999999);
        }
        userVotes.clear();
      }
      userVotes.add(optionId);
      final c = votesByOption[optionId] ?? 0;
      votesByOption[optionId] = (c is num ? c.toInt() + 1 : (int.tryParse(c.toString()) ?? 0) + 1);
    }

    await localChatRepo.updateMessageCompanion(
      MessagesCompanion(
        serverMessageId: Value(message.serverMessageId),
        userVotes: Value(jsonEncode(userVotes)),
        votesByOption: Value(jsonEncode(votesByOption)),
      ),
    );

    onStateChanged();

    // 2. Dispatch to WebSocket
    await chatWebSocketService.send({
      'type': 'poll_vote',
      'poll_message_id': message.messageId,
      'option_id': optionId,
    });
  }
}
