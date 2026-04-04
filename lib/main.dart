import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';
import 'firebase_options.dart';
import 'src/config/router.dart';
import 'src/providers/step_light_provider.dart';
import 'src/providers/theme_provider.dart';
import 'src/screens/app_splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  bool _showIntroSplash = true;
  Timer? _splashTimer;

  @override
  void initState() {
    super.initState();
    _splashTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() {
        _showIntroSplash = false;
      });
    });
  }

  @override
  void dispose() {
    _splashTimer?.cancel();
    super.dispose();
  }

  ThemeData _buildThemeData(Brightness brightness) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF1A73E8),
      brightness: brightness,
    );

    return ThemeData(
      brightness: brightness,
      colorScheme: colorScheme,
      useMaterial3: true,
      scaffoldBackgroundColor: colorScheme.surface,
      visualDensity: VisualDensity.standard,
      textTheme: TextTheme(
        displayLarge: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        displayMedium: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        headlineLarge: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        headlineMedium: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        titleLarge: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
        titleMedium: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: TextStyle(color: colorScheme.onSurface),
        bodyMedium: TextStyle(color: colorScheme.onSurfaceVariant),
        labelLarge: TextStyle(
          color: colorScheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colorScheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: colorScheme.surface,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        toolbarHeight: 64,
        titleSpacing: 20,
        iconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        titleTextStyle: TextStyle(
          color: colorScheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w800,
          letterSpacing: -0.2,
          height: 1.1,
        ),
        shape: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colorScheme.surface,
        indicatorColor: colorScheme.secondaryContainer,
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected
                ? colorScheme.onSecondaryContainer
                : colorScheme.onSurfaceVariant,
          );
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.onSurfaceVariant,
        indicatorColor: colorScheme.primary,
        dividerColor: colorScheme.outlineVariant,
        labelStyle: const TextStyle(fontWeight: FontWeight.w700),
        unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colorScheme.inverseSurface,
        contentTextStyle: TextStyle(color: colorScheme.onInverseSurface),
        actionTextColor: colorScheme.inversePrimary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      dividerTheme: DividerThemeData(
        color: colorScheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primaryContainer;
          }
          return colorScheme.surfaceContainerHighest;
        }),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline;
        }),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colorScheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primaryContainer,
        foregroundColor: colorScheme.onPrimaryContainer,
        elevation: 0,
        highlightElevation: 0,
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colorScheme.primary;
          }
          return colorScheme.outline;
        }),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colorScheme.surfaceContainerHighest,
        selectedColor: colorScheme.secondaryContainer,
        side: BorderSide(color: colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        labelStyle: TextStyle(color: colorScheme.onSurface),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colorScheme.surfaceContainerLowest,
        isDense: true,
        floatingLabelBehavior: FloatingLabelBehavior.auto,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.4),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colorScheme.primary,
        circularTrackColor: colorScheme.surfaceContainerHighest,
        linearTrackColor: colorScheme.surfaceContainerHighest,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(stepLightMonitorProvider);
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);

    if (_showIntroSplash) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: _buildThemeData(Brightness.light),
        darkTheme: _buildThemeData(Brightness.dark),
        themeMode: themeMode,
        home: const AppSplashScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Personal Health Diary',
      routerConfig: router,
      theme: _buildThemeData(Brightness.light),
      darkTheme: _buildThemeData(Brightness.dark),
      themeMode: themeMode,
      debugShowCheckedModeBanner: false,
    );
  }
}
