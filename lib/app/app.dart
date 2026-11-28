import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/app/router/app_router.dart';
import 'package:surplus_share/core/auth/models/auth_state.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/theme/green/green_theme.dart';
import 'package:surplus_share/core/theme/text_theme.dart';

class MainApp extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  ThemeData? _lightTheme;
  ThemeData? _darkTheme;

  @override
  void initState() {
    super.initState();
    unawaited(
      Future.microtask(() {
        if (!mounted) return;
        if (ref.read(authNotifierProvider) is AuthInitial) {
          unawaited(ref.read(authNotifierProvider.notifier).restoreSession());
        }
      }),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_lightTheme == null || _darkTheme == null) {
      final textTheme = createTextTheme(context, 'Inter', 'Inter');
      final green = GreenTheme(textTheme);
      _lightTheme = green.light();
      _darkTheme = green.dark();
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(
      themeNotifierProvider.select((state) => state.mode),
    );
    final snackbarService = ref.watch(snackbarServiceProvider);
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Surplus Share',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      scaffoldMessengerKey: snackbarService.scaffoldKey,
      themeMode: themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
    );
  }
}
