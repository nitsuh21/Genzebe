import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Status-bar icon style that reads against a page of the given brightness
/// (light page -> dark icons). Screens with their own dark hero (auth) pass
/// [Brightness.dark] explicitly.
SystemUiOverlayStyle systemOverlayStyleFor(Brightness pageBrightness) {
  final base = pageBrightness == Brightness.dark
      ? SystemUiOverlayStyle.light
      : SystemUiOverlayStyle.dark;
  return base.copyWith(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Colors.transparent,
  );
}

/// The brand indigo from the app icon.
const kBrandIndigo = Color(0xFF4E5AE8);

/// The icon's deeper edge tone: full-bleed brand surfaces (onboarding, the
/// balance panel), where white type and the gold coin need the contrast.
const kBrandIndigoDeep = Color(0xFF2F37B0);

/// The coin's gold, for small accents on [kBrandIndigoDeep].
const kBrandGold = Color(0xFFE9B949);

ThemeData buildLightTheme() => _buildTheme(Brightness.light);

ThemeData buildDarkTheme() => _buildTheme(Brightness.dark);

ThemeData _buildTheme(Brightness brightness) {
  const seed = kBrandIndigo;
  final isDark = brightness == Brightness.dark;
  final seeded = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );
  // The seeded light primary is a muted grey-violet that reads as stock
  // Material; buttons and links use the icon's indigo instead. Dark mode
  // keeps the seeded pale primary, which holds contrast on navy.
  final colorScheme = isDark
      ? seeded
      : seeded.copyWith(primary: kBrandIndigo, onPrimary: Colors.white);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: colorScheme,
    scaffoldBackgroundColor:
        isDark ? const Color(0xFF0C1023) : const Color(0xFFF4F6FE),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.transparent,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      // A transparent app bar can't infer icon brightness; pin it to the
      // theme so status-bar text never disappears against the background.
      systemOverlayStyle: systemOverlayStyleFor(brightness),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: isDark ? const Color(0xFF151B34) : Colors.white,
      indicatorColor: colorScheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final isSelected = states.contains(WidgetState.selected);
        return TextStyle(
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color:
              isSelected ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
        );
      }),
    ),
    // Dialogs/sheets follow the app's card language instead of stock M3.
    dialogTheme: DialogThemeData(
      backgroundColor: isDark ? const Color(0xFF151B34) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      titleTextStyle: TextStyle(
        fontSize: 19,
        fontWeight: FontWeight.w800,
        letterSpacing: -0.2,
        color: colorScheme.onSurface,
      ),
      contentTextStyle: TextStyle(
        fontSize: 14.5,
        height: 1.45,
        color: colorScheme.onSurfaceVariant,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: isDark ? const Color(0xFF151B34) : Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    cardTheme: CardThemeData(
      color: isDark ? const Color(0xFF151B34) : Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: isDark ? const Color(0xFF1B2342) : const Color(0xFFF7F8FD),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(14)),
        borderSide: BorderSide(color: colorScheme.primary, width: 1.3),
      ),
    ),
  );
}
