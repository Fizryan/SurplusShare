import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:material_ui/material_ui.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/theme/green/green_theme.dart';
import 'package:surplus_share/core/theme/text_theme.dart';

class MainApp extends ConsumerWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeState = ref.watch(themeNotifierProvider);
    final snackbarService = ref.watch(snackbarServiceProvider);

    return ScreenUtilInit(
      designSize: const Size(393, 830),
      minTextAdapt: true,
      splitScreenMode: true,
      builder: (context, child) {
        final textTheme = createTextTheme(context, 'Inter', 'Inter');

        final ThemeData lightTheme;
        final ThemeData darkTheme;

        final green = GreenTheme(textTheme);
        lightTheme = green.light();
        darkTheme = green.dark();

        return MaterialApp.router(
          title: 'Surplus Share',
          scaffoldMessengerKey: snackbarService.scaffoldKey,
          themeMode: themeState.mode,
          theme: lightTheme,
          darkTheme: darkTheme,
        );
      },
    );
  }
}
