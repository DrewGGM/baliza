import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'tokens.dart';

/// Tema de la aplicación, derivado por completo de los tokens.
///
/// Ningún widget debe declarar un color, un radio o un espaciado a mano: si
/// hace falta uno nuevo, se añade a `tokens.dart`.
abstract final class BalizaTheme {
  static ThemeData build() {
    const scheme = ColorScheme.dark(
      primary: BalizaColors.amber,
      onPrimary: BalizaColors.base,
      secondary: BalizaColors.info,
      onSecondary: BalizaColors.base,
      error: BalizaColors.danger,
      onError: BalizaColors.textPrimary,
      surface: BalizaColors.surface,
      onSurface: BalizaColors.textPrimary,
      surfaceContainerHighest: BalizaColors.surfaceHighest,
      outline: BalizaColors.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: BalizaColors.base,
      canvasColor: BalizaColors.base,
      splashFactory: InkSparkle.splashFactory,
      textTheme: const TextTheme(
        displayLarge: BalizaText.display,
        headlineMedium: BalizaText.title,
        titleLarge: BalizaText.title,
        bodyLarge: BalizaText.body,
        bodyMedium: BalizaText.body,
        labelLarge: BalizaText.bodyStrong,
        bodySmall: BalizaText.caption,
        labelSmall: BalizaText.captionStrong,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: BalizaColors.base,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: BalizaText.title,
        iconTheme: IconThemeData(color: BalizaColors.textPrimary),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.light,
          statusBarBrightness: Brightness.dark,
          systemNavigationBarColor: BalizaColors.base,
          systemNavigationBarIconBrightness: Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: BalizaColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: BalizaColors.outline,
        thickness: 1,
        space: 1,
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: BalizaColors.textSecondary,
        textColor: BalizaColors.textPrimary,
        minVerticalPadding: Space.md,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return BalizaColors.base;
          return BalizaColors.textTertiary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return BalizaColors.amber;
          return BalizaColors.surfaceHighest;
        }),
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: BalizaColors.amber,
          foregroundColor: BalizaColors.base,
          textStyle: BalizaText.bodyStrong,
          minimumSize: const Size.fromHeight(Touch.minTarget),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: BalizaColors.textPrimary,
          textStyle: BalizaText.bodyStrong,
          minimumSize: const Size.fromHeight(Touch.minTarget),
          side: const BorderSide(color: BalizaColors.outline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: BalizaColors.amber,
          textStyle: BalizaText.bodyStrong,
          minimumSize: const Size(0, Touch.minTarget),
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: BalizaColors.surface,
          foregroundColor: BalizaColors.textSecondary,
          selectedBackgroundColor: BalizaColors.amberSoft,
          selectedForegroundColor: BalizaColors.amber,
          side: const BorderSide(color: BalizaColors.outline),
          textStyle: BalizaText.caption,
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: BalizaColors.surfaceHighest,
        contentTextStyle: BalizaText.body,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.md),
        ),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: BalizaColors.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: BalizaColors.surfaceHigh,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: BalizaText.title,
        contentTextStyle: BalizaText.body,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radii.lg),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: BalizaColors.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: BalizaColors.amberSoft,
        height: 72,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return BalizaText.caption.copyWith(
            color: selected ? BalizaColors.amber : BalizaColors.textTertiary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            color: selected ? BalizaColors.amber : BalizaColors.textTertiary,
            size: 26,
          );
        }),
      ),
    );
  }
}
