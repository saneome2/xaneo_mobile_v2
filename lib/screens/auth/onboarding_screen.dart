import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../styles/app_styles.dart';
import 'login_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _currentStep = 0;

  final List<Map<String, String>> _steps = [
    {
      'title': 'Добро пожаловать в Xaneo',
      'description': 'Xaneo — теперь и в мобильном приложении! Данный мессенджер еще никогда не был таким удобным и быстрым.',
      'image': 'assets/images/medved.png',
      'button': 'Мне уже интересно',
    },
    {
      'title': 'Все ваши данные под защитой',
      'description': 'Все сообщения защищены сквозным шифрованием. Ни на одном из этапов Xaneo не знает их содержимого.',
      'image': 'assets/images/medvedprivate.png',
      'button': 'Продолжить',
    },
    {
      'title': 'Локальные дата центры',
      'description': 'Ваши данные никогда не покидают пределы страны и хранятся в защищенных дата центрах.',
      'image': 'assets/images/medved_database.png',
      'button': 'Завершить',
    },
  ];

  void _nextStep() async {
    if (_currentStep < _steps.length - 1) {
      setState(() {
        _currentStep++;
      });
    } else {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('has_seen_onboarding', true);
      
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => const LoginScreen(),
          transitionsBuilder: (context, animation, secondaryAnimation, child) {
            return FadeTransition(opacity: animation, child: child);
          },
          transitionDuration: AppStyles.animationMedium,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final step = _steps[_currentStep];

    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 24.0),
          child: Column(
            children: [
              // Progress indicator
              Row(
                children: List.generate(_steps.length, (index) {
                  return Expanded(
                    child: AnimatedContainer(
                      duration: AppStyles.animationFast,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      height: 4,
                      decoration: BoxDecoration(
                        color: _currentStep >= index ? Colors.white : Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
              const Spacer(flex: 1),
              
              // Animated Content
              Expanded(
                flex: 6,
                child: AnimatedSwitcher(
                  duration: AppStyles.animationMedium,
                  child: Column(
                    key: ValueKey<int>(_currentStep),
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        step['image']!,
                        height: 200,
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 48),
                      Text(
                        step['title']!,
                        style: AppStyles.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        step['description']!,
                        style: AppStyles.bodyMuted,
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
              
              const Spacer(flex: 1),
              
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _nextStep,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppStyles.buttonBackgroundColor,
                    foregroundColor: AppStyles.buttonTextColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  child: Text(step['button']!, style: AppStyles.buttonText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
