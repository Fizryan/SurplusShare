import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/core/auth/dummy/dummy_auth_repository.dart';
import 'package:surplus_share/core/auth/models/auth_failure.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/repository/auth_repository.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/shared/service/snackbar_service.dart';
import 'package:surplus_share/core/theme/green/green_theme.dart';
import 'package:surplus_share/features/auth/presentation/screens/login_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository;

Widget _buildTestApp({
  required AuthRepository repository,
  required SnackbarService snackbarService,
  ThemeMode themeMode = ThemeMode.light,
}) {
  final green = GreenTheme(ThemeData.light().textTheme);
  return ProviderScope(
    overrides: [
      authRepositoryProvider.overrideWithValue(repository),
      snackbarServiceProvider.overrideWithValue(snackbarService),
    ],
    child: MaterialApp(
      scaffoldMessengerKey: snackbarService.scaffoldKey,
      themeMode: themeMode,
      theme: green.light(),
      darkTheme: green.dark(),
      home: const LoginScreen(),
    ),
  );
}

void main() {
  late _MockAuthRepository repository;
  late SnackbarService snackbarService;

  setUp(() {
    repository = _MockAuthRepository();
    snackbarService = SnackbarService();
  });

  group('LoginScreen (Google Auth SOTA)', () {
    testWidgets(
      'triggers Google sign-in with selected debug role and shows loading',
      (tester) async {
        final completer = Completer<Either<AuthFailure, AuthTokens>>();
        when(
          () => repository.signInWithGoogle(
            debugAccountId: DummyAuthAccounts.donorPartner.id,
          ),
        ).thenAnswer((_) => completer.future);

        await tester.pumpWidget(
          _buildTestApp(
            repository: repository,
            snackbarService: snackbarService,
          ),
        );

        final roleChip = find.byKey(const Key('debug_role_donorPartner'));
        await tester.ensureVisible(roleChip);
        await tester.tap(roleChip);
        await tester.pump();

        final signInBtn = find.byKey(const Key('google_sign_in_button'));
        await tester.ensureVisible(signInBtn);
        await tester.tap(signInBtn);
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        final button = tester.widget<FilledButton>(
          find.byKey(const Key('google_sign_in_button')),
        );
        expect(button.onPressed, isNull);

        completer.complete(right(const AuthTokens(accessToken: 'a')));
        await tester.pumpAndSettle();

        verify(
          () => repository.signInWithGoogle(
            debugAccountId: DummyAuthAccounts.donorPartner.id,
          ),
        ).called(1);
      },
    );

    testWidgets('shows snackbar error on failure but stays silent on cancel', (
      tester,
    ) async {
      when(
        () => repository.signInWithGoogle(
          debugAccountId: any(named: 'debugAccountId'),
        ),
      ).thenAnswer((_) async => left(const AuthCancelledFailure()));

      await tester.pumpWidget(
        _buildTestApp(repository: repository, snackbarService: snackbarService),
      );

      await tester.tap(find.byKey(const Key('google_sign_in_button')));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsNothing);

      when(
        () => repository.signInWithGoogle(
          debugAccountId: any(named: 'debugAccountId'),
        ),
      ).thenAnswer((_) async => left(const NetworkFailure('Tidak ada sinyal')));

      await tester.tap(find.byKey(const Key('google_sign_in_button')));
      await tester.pumpAndSettle();
      expect(find.text('Tidak ada sinyal'), findsOneWidget);
    });

    testWidgets(
      'renders cleanly across multi-resolution viewports and 1.4x text scale',
      (tester) async {
        final viewports = <Size>[
          const Size(320, 568),
          const Size(393, 830),
          const Size(834, 1194),
          const Size(1280, 800),
        ];

        for (final size in viewports) {
          tester.view.physicalSize = size;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);

          await tester.pumpWidget(
            MediaQuery(
              data: MediaQueryData(
                size: size,
                textScaler: const TextScaler.linear(1.4),
              ),
              child: _buildTestApp(
                repository: repository,
                snackbarService: snackbarService,
              ),
            ),
          );
          await tester.pumpAndSettle();

          expect(tester.takeException(), isNull);
          expect(
            find.byKey(const Key('google_sign_in_button')),
            findsOneWidget,
          );
        }
      },
    );
  });
}
