import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'providers/auth_provider.dart';
import 'screens/auth/login_screen.dart';
import 'screens/auth/register_screen.dart';
import 'screens/auth/onboarding_screen.dart';
import 'screens/auth/tfa_screen.dart';
import 'screens/main/main_screen.dart';
import 'styles/app_styles.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Устанавливаем чёрный статус-бар
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.black,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  
  runApp(const XaneoApp());
}

/// Точка входа в приложение Xaneo
class XaneoApp extends StatelessWidget {
  const XaneoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>(
          create: (_) => AuthProviderFactory.create()..checkAuthStatus(),
        ),
      ],
      child: MaterialApp(
        title: 'Xaneo',
        debugShowCheckedModeBanner: false,
        
        // Чёрно-белая тема
        theme: ThemeData(
          useMaterial3: true,
          brightness: Brightness.dark,
          scaffoldBackgroundColor: AppStyles.backgroundColor,
          fontFamily: AppStyles.fontFamily,
          
          colorScheme: const ColorScheme.dark(
            primary: AppStyles.textPrimaryColor,
            secondary: AppStyles.textSecondaryColor,
            surface: AppStyles.backgroundColor,
            error: AppStyles.errorColor,
          ),
          
          appBarTheme: const AppBarTheme(
            backgroundColor: AppStyles.backgroundColor,
            elevation: 0,
            centerTitle: true,
            iconTheme: IconThemeData(color: AppStyles.textPrimaryColor),
            titleTextStyle: TextStyle(
              color: AppStyles.textPrimaryColor,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
          
          inputDecorationTheme: InputDecorationTheme(
            filled: true,
            fillColor: AppStyles.inputBackgroundColor,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppStyles.borderColor, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppStyles.borderColor, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppStyles.borderActiveColor, width: 1),
            ),
            hintStyle: AppStyles.inputHint,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          ),
          
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: AppStyles.primaryButton,
          ),
          
          textButtonTheme: TextButtonThemeData(
            style: AppStyles.textButton,
          ),
          
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: AppStyles.secondaryButton,
          ),
          
          navigationBarTheme: NavigationBarThemeData(
            backgroundColor: AppStyles.backgroundColor,
            indicatorColor: AppStyles.inputBackgroundColor,
            labelTextStyle: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return AppStyles.inputText.copyWith(
                  color: AppStyles.textPrimaryColor,
                  fontSize: 12,
                );
              }
              return AppStyles.inputText.copyWith(
                color: AppStyles.textMutedColor,
                fontSize: 12,
              );
            }),
          ),
        ),
        
        // Начальный экран
        home: const AuthWrapper(),
        
        // Роуты
        routes: {
          '/login': (_) => const LoginScreen(),
          '/register': (_) => const RegisterScreen(),
          '/tfa': (_) => const TfaScreen(),
          '/main': (_) => const MainScreen(),
        },
      ),
    );
  }
}

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool? _hasSeenOnboarding;

  @override
  void initState() {
    super.initState();
    _checkOnboarding();
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _hasSeenOnboarding = prefs.getBool('has_seen_onboarding') ?? false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_hasSeenOnboarding == null) {
      return const SplashScreen();
    }

    return Consumer<AuthProvider>(
      builder: (context, auth, child) {
        if (auth.status == AuthStatus.checking) {
          return const SplashScreen();
        }
        
        if (auth.status == AuthStatus.authenticated) {
          return const MainScreen();
        }
        
        if (auth.status == AuthStatus.tfaRequired) {
          return const TfaScreen();
        }
        
        if (_hasSeenOnboarding == false) {
          return const OnboardingScreen();
        }
        
        return const LoginScreen();
      },
    );
  }
}

/// Загрузочный экран
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppStyles.backgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Логотип
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: AppStyles.textPrimaryColor,
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.chat_bubble_rounded,
                size: 50,
                color: AppStyles.backgroundColor,
              ),
            ),
            const SizedBox(height: 32),
            
            // Название
            const Text(
              'Xaneo',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: AppStyles.textPrimaryColor,
                letterSpacing: 4,
              ),
            ),
            const SizedBox(height: 48),
            
            // Индикатор загрузки
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppStyles.textPrimaryColor),
            ),
          ],
        ),
      ),
    );
  }
}
