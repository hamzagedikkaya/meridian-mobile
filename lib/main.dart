import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/locale_mode.dart';
import 'core/reduce_motion.dart';
import 'core/session.dart';
import 'core/theme_mode.dart';
import 'l10n/app_l10n.dart';
import 'router/app_router.dart';
import 'theme/app_motion.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Draw behind the status and navigation bars (Android 15+ does it anyway);
  // the theme keeps both bars transparent and insets come from MediaQuery.
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  // Both shipped languages, since the user can switch at runtime.
  await initializeDateFormatting();
  final prefs = await SharedPreferences.getInstance();

  runApp(
    ProviderScope(
      // Fail in seconds, not after Riverpod's ~40-90 s of silent retries.
      // The read models apply it inside each fetch (see `retried`).
      retry: readRetry,
      overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      child: const MeridianApp(),
    ),
  );
}

class MeridianApp extends ConsumerWidget {
  const MeridianApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final reduceMotion = ref.watch(reduceMotionProvider);
    final systemReduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;

    return MaterialApp.router(
      title: 'Meridian',
      debugShowCheckedModeBanner: false,
      themeMode: themeMode,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      // Light ↔ dark fades every token (NokturnColors.lerp).
      themeAnimationDuration:
          reduceMotion || systemReduced ? Duration.zero : Motion.themeChange,
      themeAnimationCurve: Motion.themeCurve,
      routerConfig: router,
      builder: (context, child) => MotionPreference(
        reduce: reduceMotion,
        child: child ?? const SizedBox.shrink(),
      ),
      locale: locale,
      supportedLocales: AppL10n.supportedLocales,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
