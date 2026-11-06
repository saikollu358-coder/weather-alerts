import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'routing/app_router.dart';

/// Root widget of the application.
class WeatherAlertsApp extends StatelessWidget {
  const WeatherAlertsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer(
      builder: (context, ref, _) {
        final router = ref.watch(appRouterProvider);
        return MaterialApp.router(
          title: AppConstants.appName,
          routerConfig: router,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          // The dashboard is built on the dark navy tokens in WeatherPalette,
          // so following the system setting would render the tabs against a
          // light canvas while the shell stays dark. Dark is the design.
          themeMode: ThemeMode.dark,
          debugShowCheckedModeBanner: false,
        );
      },
    );
  }
}