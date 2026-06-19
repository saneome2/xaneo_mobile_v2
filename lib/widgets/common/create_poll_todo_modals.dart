import 'package:flutter/material.dart';
import '../../styles/app_styles.dart';
import 'base_custom_modal.dart';

class CreatePollModal extends BaseCustomModal {
  final Function(String question, List<String> options, bool isMultipleChoice) onCreate;

  const CreatePollModal({
    super.key,
    required this.onCreate,
  });

  static void show(BuildContext context, Function(String question, List<String> options, bool isMultipleChoice) onCreate) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      builder: (context) => CreatePollModal(onCreate: onCreate),
    );
  }

  @override
  State<CreatePollModal> createState() => _CreatePollModalState();
}

class _CreatePollModalState extends BaseCustomModalState<CreatePollModal> {
  @override
  double get initialExtent => 0.85;
  @override
  double get maxExtent => 0.95;

  final _questionController = TextEditingController();
  final List<TextEditingController> _optionsControllers = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _isMultipleChoice = false;

  @override
  void dispose() {
    _questionController.dispose();
    for (var c in _optionsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 10),
        const Text(
          'СОЗДАТЬ ОПРОС',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
            letterSpacing: 1.5,
            fontFamily: AppStyles.fontFamily,
          ),
        ),
        const SizedBox(height: 24),
        
        // Question Input
        TextField(
          controller: _questionController,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            labelText: 'Вопрос',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.02),
          ),
        ),
        const SizedBox(height: 20),
        
        // Options Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Варианты ответа:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.6),
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            if (_optionsControllers.length < 10)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _optionsControllers.add(TextEditingController());
                  });
                },
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text(
                  'Добавить',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        
        // Options List
        ...List.generate(_optionsControllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _optionsControllers[index],
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Вариант ${index + 1}',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.02),
                    ),
                  ),
                ),
                if (_optionsControllers.length > 2) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                    onPressed: () {
                      setState(() {
                        final controller = _optionsControllers.removeAt(index);
                        controller.dispose();
                      });
                    },
                  ),
                ],
              ],
            ),
          );
        }),
        const SizedBox(height: 10),
        
        // Multiple Choice Setting
        Theme(
          data: ThemeData(
            unselectedWidgetColor: Colors.white38,
          ),
          child: CheckboxListTile(
            title: const Text(
              'Множественный выбор',
              style: TextStyle(color: Colors.white, fontSize: 14, fontFamily: AppStyles.fontFamily),
            ),
            value: _isMultipleChoice,
            activeColor: Colors.white,
            checkColor: Colors.black,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            onChanged: (val) {
              setState(() {
                _isMultipleChoice = val ?? false;
              });
            },
          ),
        ),
        const SizedBox(height: 24),
        
        // Submit Button
        ElevatedButton(
          onPressed: () {
            final question = _questionController.text.trim();
            final options = _optionsControllers
                .map((c) => c.text.trim())
                .where((t) => t.isNotEmpty)
                .toList();
            if (question.isEmpty || options.length < 2) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Пожалуйста, заполните вопрос и как минимум два варианта ответа')),
              );
              return;
            }
            Navigator.pop(context);
            widget.onCreate(question, options, _isMultipleChoice);
          },
          style: AppStyles.primaryButton,
          child: const Text('Создать опрос'),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

class CreateTodoModal extends BaseCustomModal {
  final Function(String title, List<String> items) onCreate;

  const CreateTodoModal({
    super.key,
    required this.onCreate,
  });

  static void show(BuildContext context, Function(String title, List<String> items) onCreate) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black54,
      builder: (context) => CreateTodoModal(onCreate: onCreate),
    );
  }

  @override
  State<CreateTodoModal> createState() => _CreateTodoModalState();
}

class _CreateTodoModalState extends BaseCustomModalState<CreateTodoModal> {
  @override
  double get initialExtent => 0.85;
  @override
  double get maxExtent => 0.95;

  final _titleController = TextEditingController();
  final List<TextEditingController> _itemsControllers = [
    TextEditingController(),
  ];

  @override
  void dispose() {
    _titleController.dispose();
    for (var c in _itemsControllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget buildContent(BuildContext context, ScrollController scrollController) {
    return ListView(
      controller: scrollController,
      physics: const BouncingScrollPhysics(),
      children: [
        const SizedBox(height: 10),
        const Text(
          'СОЗДАТЬ СПИСОК ЗАДАЧ',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: Colors.white70,
            letterSpacing: 1.5,
            fontFamily: AppStyles.fontFamily,
          ),
        ),
        const SizedBox(height: 24),
        
        // Title Input
        TextField(
          controller: _titleController,
          style: const TextStyle(color: Colors.white, fontSize: 15),
          decoration: InputDecoration(
            labelText: 'Название списка',
            labelStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 13),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.white),
            ),
            filled: true,
            fillColor: Colors.white.withOpacity(0.02),
          ),
        ),
        const SizedBox(height: 20),
        
        // Items Header
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Пункты:',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white.withOpacity(0.6),
                fontFamily: AppStyles.fontFamily,
              ),
            ),
            if (_itemsControllers.length < 20)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _itemsControllers.add(TextEditingController());
                  });
                },
                icon: const Icon(Icons.add, size: 16, color: Colors.white),
                label: const Text(
                  'Добавить',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        
        // Items List
        ...List.generate(_itemsControllers.length, (index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _itemsControllers[index],
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Пункт ${index + 1}',
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white),
                      ),
                      filled: true,
                      fillColor: Colors.white.withOpacity(0.02),
                    ),
                  ),
                ),
                if (_itemsControllers.length > 1) ...[
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white38, size: 20),
                    onPressed: () {
                      setState(() {
                        final controller = _itemsControllers.removeAt(index);
                        controller.dispose();
                      });
                    },
                  ),
                ],
              ],
            ),
          );
        }),
        const SizedBox(height: 24),
        
        // Submit Button
        ElevatedButton(
          onPressed: () {
            final title = _titleController.text.trim();
            final items = _itemsControllers
                .map((c) => c.text.trim())
                .where((t) => t.isNotEmpty)
                .toList();
            if (title.isEmpty || items.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Пожалуйста, заполните название и как минимум один пункт')),
              );
              return;
            }
            Navigator.pop(context);
            widget.onCreate(title, items);
          },
          style: AppStyles.primaryButton,
          child: const Text('Создать список задач'),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}
