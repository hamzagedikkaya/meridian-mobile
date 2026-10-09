/// Shared setup for the WP-2 component tests: one component on a phone-sized
/// screen, in the app's theme and languages, with the real fonts.
library;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:meridian_mobile/l10n/app_l10n.dart';
import 'package:meridian_mobile/theme/app_theme.dart';

import '../../support/app_fonts.dart';

/// Loads the bundled fonts once per file, so sizes are measured as on a
/// phone.
void setUpComponentFonts() => setUpAll(loadAppFonts);

/// One theme per brightness for the whole run: pumping a new but equal
/// `ThemeData` would start `MaterialApp`'s 200 ms theme animation, a frame
/// that no component asked for.
final _themes = <Brightness, ThemeData>{};

/// Pumps [child] in a [Scaffold] body (or as [home] itself when [bare]).
Future<void> pumpComponent(
  WidgetTester tester,
  Widget child, {
  Brightness brightness = Brightness.dark,
  double textScale = 1.0,
  bool reduceMotion = false,
  bool bare = false,
  Size size = const Size(360, 780),
  Locale locale = const Locale('tr'),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _themes.putIfAbsent(brightness, () => buildTheme(brightness)),
      locale: locale,
      localizationsDelegates: const [
        AppL10n.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppL10n.supportedLocales,
      builder: (context, app) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: reduceMotion,
        ),
        child: app!,
      ),
      home: bare ? child : Scaffold(body: child),
    ),
  );
}

/// A centred, padded host for small components.
Widget centred(Widget child) => Center(
  child: Padding(padding: const EdgeInsets.all(20), child: child),
);

/// The semantics data of the one node labelled [label].
SemanticsData semanticsOf(String label) =>
    find.semantics.byLabel(label).evaluate().single.getSemanticsData();
