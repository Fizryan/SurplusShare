import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fpdart/fpdart.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mocktail/mocktail.dart';
import 'package:surplus_share/app/router/app_router.dart';
import 'package:surplus_share/app/router/router_enum.dart';
import 'package:surplus_share/core/auth/models/auth_tokens.dart';
import 'package:surplus_share/core/auth/provider/auth_provider.dart';
import 'package:surplus_share/core/auth/repository/auth_repository.dart';
import 'package:surplus_share/core/di/global_provider.dart';
import 'package:surplus_share/core/theme/green/green_theme.dart';
import 'package:surplus_share/features/auth/presentation/screens/login_screen.dart';
import 'package:surplus_share/features/auth/presentation/screens/unauthorized_screen.dart';
import 'package:surplus_share/features/listing/presentation/screens/feed_screen.dart';

class _MockAuthRepository extends Mock implements AuthRepository;

String _jwt(Map<String, dynamic> payload) {
  final header = base64Url.encode(utf8.encode(jsonEncode({'alg': 'HS256'})));
  final body = base64Url.encode(utf8.encode(jsonEncode(payload)));
  return '$header.$body.sig';
}

class _RouterHost extends ConsumerWidget {
  const new();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    final snackbarService = ref.watch(snackbarServiceProvider);
    final green = GreenTheme(ThemeData.light().textTheme);

    return MaterialApp.router(
      routerConfig: router,
      scaffoldMessengerKey: snackbarService.scaffoldKey,
      theme: green.light(),
      darkTheme: green.dark(),
    );
  }
}

void main() {
  late _MockAuthRepository repository;

  setUp(() {
    repository = _MockAuthRepository();
  });

  group('appRouterProvider', () {
    testWidgets(
      'stays on Google LoginScreen when unauthenticated and blocks protected '
      'routes',
      (tester) async {
        when(() => repository.restoreSession())
            .thenAnswer((_) async => right(null));

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _RouterHost(),
          ),
        );
        await container.read(authNotifierProvider.notifier).restoreSession();
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);

        // Attempt to visit protected /feed -> redirected back to /login.
        container.read(appRouterProvider).go(RouteEnum.feed.path);
        await tester.pumpAndSettle();
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets(
      'redirects authenticated user with feed permission from /login to /feed',
      (tester) async {
        final jwt = _jwt({'sub': 'u1', 'role': 'consumer'});
        when(() => repository.signInWithGoogle())
            .thenAnswer((_) async => right(AuthTokens(accessToken: jwt)));

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _RouterHost(),
          ),
        );
        await tester.pumpAndSettle();

        await container.read(authNotifierProvider.notifier).signInWithGoogle();
        await tester.pumpAndSettle();

        expect(find.byType(FeedScreen), findsOneWidget);
      },
    );

    testWidgets(
      'redirects authenticated user missing feed permission to /unauthorized '
      'and allows logout back to /login',
      (tester) async {
        final jwt = _jwt({
          'sub': 'u2',
          'role': 'consumer',
          'revoked_permissions': ['browse_discount_listings'],
        });
        when(() => repository.signInWithGoogle())
            .thenAnswer((_) async => right(AuthTokens(accessToken: jwt)));
        when(() => repository.logout()).thenAnswer((_) async => right(unit));

        final container = ProviderContainer(
          overrides: [authRepositoryProvider.overrideWithValue(repository)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const _RouterHost(),
          ),
        );
        await tester.pumpAndSettle();

        await container.read(authNotifierProvider.notifier).signInWithGoogle();
        await tester.pumpAndSettle();

        expect(find.byType(UnauthorizedScreen), findsOneWidget);

        await tester.tap(find.text('Keluar'));
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );
  });
}
