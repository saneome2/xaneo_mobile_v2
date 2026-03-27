import 'package:flutter/material.dart';

class AppStyles {
  AppStyles._();

  static const Color backgroundColor = Colors.black;
  static const Color textPrimaryColor = Colors.white;
  static const Color textSecondaryColor = Color(0xFFB0B0B0);
  static const Color textMutedColor = Color(0xFF707070);
  static const Color buttonBackgroundColor = Colors.white;
  static const Color buttonTextColor = Colors.black;
  static const Color inputBackgroundColor = Colors.transparent;
  static const Color borderColor = Color(0xFF333333);
  static const Color borderActiveColor = Colors.white;
  static const Color errorColor = Color(0xFFFF4444);
  static const Color successColor = Color(0xFF44FF44);

  static const String fontFamily = 'Inter';

  static const double fontSizeGiant = 32.0;
  static const double fontSizeTitle = 28.0;
  static const double fontSizeLarge = 24.0;
  static const double fontSizeMedium = 18.0;
  static const double fontSizeNormal = 16.0;
  static const double fontSizeSmall = 14.0;

  static const TextStyle titleGiant = TextStyle(
    fontSize: fontSizeGiant,
    fontWeight: FontWeight.w700,
    color: textPrimaryColor,
    fontFamily: fontFamily,
    height: 1.2,
    letterSpacing: -1.0,
  );

  static const TextStyle titleLarge = TextStyle(
    fontSize: fontSizeTitle,
    fontWeight: FontWeight.w600,
    color: textPrimaryColor,
    fontFamily: fontFamily,
    height: 1.2,
    letterSpacing: -0.5,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontSize: fontSizeMedium,
    fontWeight: FontWeight.w400,
    color: textSecondaryColor,
    fontFamily: fontFamily,
    height: 1.4,
  );

  static const TextStyle bodyMuted = TextStyle(
    fontSize: fontSizeMedium,
    fontWeight: FontWeight.w400,
    color: textMutedColor,
    fontFamily: fontFamily,
  );

  static const TextStyle buttonText = TextStyle(
    fontSize: fontSizeNormal,
    fontWeight: FontWeight.w600,
    color: buttonTextColor,
    fontFamily: fontFamily,
  );

  static const TextStyle inputText = TextStyle(
    fontSize: fontSizeLarge,
    fontWeight: FontWeight.w500,
    color: textPrimaryColor,
    fontFamily: fontFamily,
    letterSpacing: -0.5,
  );

  static const TextStyle inputHint = TextStyle(
    fontSize: fontSizeLarge,
    fontWeight: FontWeight.w400,
    color: textMutedColor,
    fontFamily: fontFamily,
    letterSpacing: -0.5,
  );

  static const Duration animationFast = Duration(milliseconds: 200);
  static const Duration animationMedium = Duration(milliseconds: 400);
  static const Duration animationSlow = Duration(milliseconds: 600);

  static const Curve curveEaseInOut = Curves.easeInOutCubic;
  static const Curve curveEaseOut = Curves.easeOutCubic;
  static const Curve curveEaseIn = Curves.easeInCubic;

  // Added styles to fix dependencies
  static const EdgeInsets screenPadding = EdgeInsets.all(24.0);

  static const TextStyle errorText = TextStyle(
    fontSize: fontSizeSmall,
    fontWeight: FontWeight.w400,
    color: errorColor,
    fontFamily: fontFamily,
  );

  static final ButtonStyle primaryButton = ElevatedButton.styleFrom(
    backgroundColor: buttonBackgroundColor,
    foregroundColor: buttonTextColor,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    elevation: 0,
    textStyle: buttonText,
  );

  static final ButtonStyle secondaryButton = OutlinedButton.styleFrom(
    foregroundColor: textPrimaryColor,
    side: const BorderSide(color: borderColor, width: 1),
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    textStyle: buttonText.copyWith(color: textPrimaryColor),
  );

  static final ButtonStyle textButton = TextButton.styleFrom(
    foregroundColor: textPrimaryColor,
    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    textStyle: buttonText.copyWith(color: textPrimaryColor),
  );
}
