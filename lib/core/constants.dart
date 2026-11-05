import 'package:flutter/material.dart';

class AppColors {
  static const spaceBlue = Color(0xFF070A14);
  static const surfaceNavy = Color(0xFF101625);
  static const accentCyan = Color(0xFF00E5FF);
  static const accentBlue = Color(0xFF007BFF);
  static const actionBlue = Color(0xFF007BFF);
  static const successEmerald = Color(0xFF00C853);
  static const warningAmber = Color(0xFFFFAB00);
  static const dangerRose = Color(0xFFFF1744);
  static const glassWhite = Color(0x0DFFFFFF);
  
  static const primaryGradient = LinearGradient(
    colors: [accentBlue, accentCyan],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );
}

class AppSpacing {
  static const double base = 8.0;
  static const double s1 = 8.0;
  static const double s2 = 16.0;
  static const double s3 = 24.0;
  static const double s4 = 32.0;
  static const double edge = 24.0;
}

class AppRadius {
  static const double standard = 12.0;
  static const double large = 20.0;
  static const double button = 10.0;
  static const double card = 16.0;
}

class AppShadows {
  static final glowBlue = BoxShadow(
    color: AppColors.accentBlue.withOpacity(0.3),
    blurRadius: 15,
    offset: const Offset(0, 4),
  );
  static final surfaceShadow = BoxShadow(
    color: Colors.black.withOpacity(0.5),
    blurRadius: 20,
    offset: const Offset(0, 10),
  );
}
