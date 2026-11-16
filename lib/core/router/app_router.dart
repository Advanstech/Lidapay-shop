import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../deep_links.dart';
import '../../features/auth/providers.dart';
import '../../features/auth/screens/change_password_screen.dart';
import '../../features/auth/screens/forgot_password_screen.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/reset_password_screen.dart';
import '../../features/auth/screens/verify_password_change_screen.dart';
import '../../features/dashboard/screens/dashboard_screen.dart';
import '../../features/history/screens/analytics_screen.dart';
import '../../features/history/screens/history_screen.dart';
import '../../features/legal/legal_content.dart';
import '../../features/legal/screens/legal_document_screen.dart';
import '../../features/legal/screens/legal_hub_screen.dart';
import '../../features/lida_value/providers.dart';
import '../../features/lida_value/screens/lida_value_screen.dart';
import '../../features/notifications/screens/notifications_screen.dart';
import '../../features/onboarding/screens/onboarding_screen.dart';
import '../../features/payments/screens/payment_return_screen.dart';
import '../../features/recipient_choice/screens/recipient_decision_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/profile_screen.dart';
import '../../features/services/screens/airtime_screen.dart';
import '../../features/services/screens/rewards_screen.dart';
import '../../features/services/screens/service_transaction_screen.dart';
import '../../features/services/screens/services_screen.dart';
import '../../features/support/screens/support_category_screen.dart';
import '../../features/support/screens/support_screen.dart';
import '../../features/shop/screens/cart_screen.dart';
import '../../features/shop/screens/orders_screen.dart';
import '../../features/shop/screens/shop_screen.dart';
import '../../features/shell/main_shell.dart';
import '../../features/splash/screens/splash_screen.dart';

abstract final class AppRoutes {
  static const splash = '/splash';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const register = '/register';
  static const forgotPassword = '/forgot-password';

  /// Emailed password links — reachable with or without a session because
  /// the token in the query string is the authority.
  static const resetPassword = '/reset-password';
  static const verifyPasswordChange = '/verify-password-change';
  static const home = '/home';
  static const notifications = '/home/notifications';
  static const shop = '/shop';
  static const cart = '/shop/cart';
  static const orders = '/shop/orders';
  static const services = '/services';
  static const airtime = '/services/airtime';
  static const data = '/services/data';
  static const globalAirtime = '/services/global-airtime';
  static const qrPay = '/services/qr-pay';
  static const gtPay = '/services/gt-pay';
  static const lidaPoints = '/services/lida-points';
  static const inviteEarn = '/services/invite-earn';
  static const support = '/services/support';

  /// Pushed from the Services hub; lives on the Services branch so the shell stays visible.
  static const lidaValue = '/services/lida-value';
  static const legal = '/legal';
  static const history = '/history';
  static const historyAnalytics = '/history/analytics';
  static const profile = '/profile';
  static const editProfile = '/profile/edit';
  static const changePassword = '/profile/change-password';

  /// Root-level landing for `lidapay://` payment returns — never inside the
  /// shell branches so a cold start can reach it directly.
  static const paymentCallback = '/payment/callback';

  /// Recipient-choice surfaces: the recipient answers a parked top-up, and
  /// the sender watches a parked top-up settle. Root navigator so a push or
  /// notification tap can reach them from anywhere.
  static String recipientDecision(String decisionId) =>
      '/recipient-decision/$decisionId';

  static String orderDetail(String orderId) => '/shop/orders/$orderId';
}

const _onboardingKey = 'onboarding_seen_v1';

/// Pushed pages (service wizards, notifications, cart, …) mount on the root
/// navigator so they cover the shell dock instead of sitting above it.
final _rootNavigatorKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // The router is built once — rebuilding it on auth changes recreates the
  // whole Navigator, which double-mounts page subtrees mid-transition and
  // trips duplicate-GlobalKey assertions. `refreshListenable` re-runs
  // `redirect` instead, and the session is read fresh inside it.
  final refresh = ValueNotifier<int>(0);
  ref.onDispose(refresh.dispose);
  ref.listen<bool>(hasSessionProvider, (_, _) => refresh.value++);

  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.splash,
    debugLogDiagnostics: false,
    refreshListenable: refresh,
    redirect: (context, state) async {
      // Android delivers custom-scheme intents (`lidapay://...`) into GoRouter's
      // route parser as well as the AppLinks stream. Never bounce payment
      // callbacks back to `/splash` — doing so tears down the active flow and
      // restarts the app instead of verifying and showing the receipt.
      if (state.uri.scheme.isNotEmpty &&
          state.uri.scheme != 'http' &&
          state.uri.scheme != 'https') {
        if (PaymentDeepLinkHandler.isPasswordLink(state.uri)) {
          return PaymentDeepLinkHandler.passwordRouteFor(state.uri);
        }
        if (PaymentDeepLinkHandler.isPaymentReturn(state.uri)) {
          var hasSession = ref.read(hasSessionProvider);
          if (!hasSession) {
            final auth = ref.read(authSessionProvider.notifier);
            if (!auth.didAttemptRestore) {
              await auth.restore();
            }
            hasSession = ref.read(hasSessionProvider);
          }
          if (hasSession) {
            return PaymentDeepLinkHandler.callbackRouteFor(state.uri);
          }
          final prefs = await SharedPreferences.getInstance();
          final seenOnboarding = prefs.getBool(_onboardingKey) ?? false;
          return seenOnboarding ? AppRoutes.login : AppRoutes.onboarding;
        }
        return AppRoutes.splash;
      }
      if (state.matchedLocation == AppRoutes.splash) return null;

      // Emailed password links must open in either session state — the
      // reset flow is for signed-out users, the change-confirm flow for
      // signed-in ones, and the token is the authority either way.
      if (state.matchedLocation == AppRoutes.resetPassword ||
          state.matchedLocation == AppRoutes.verifyPasswordChange) {
        return null;
      }

      final hasSession = ref.read(hasSessionProvider);

      final onAuthRoute =
          state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.register ||
          state.matchedLocation == AppRoutes.forgotPassword ||
          // Policy docs must be readable before accepting them at
          // registration, so the legal module stays open while logged out.
          state.matchedLocation.startsWith(AppRoutes.legal);

      if (!hasSession && !onAuthRoute) {
        final prefs = await SharedPreferences.getInstance();
        final seenOnboarding = prefs.getBool(_onboardingKey) ?? false;
        return seenOnboarding ? AppRoutes.login : AppRoutes.onboarding;
      }
      if (hasSession && onAuthRoute) return AppRoutes.home;
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => LoginScreen(
          passwordResetComplete:
              state.uri.queryParameters['passwordReset'] == '1',
        ),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),
      GoRoute(
        path: AppRoutes.resetPassword,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => ResetPasswordScreen(
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.verifyPasswordChange,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => VerifyPasswordChangeScreen(
          token: state.uri.queryParameters['token'] ?? '',
        ),
      ),
      GoRoute(
        path: AppRoutes.legal,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => const LegalHubScreen(),
        routes: [
          GoRoute(
            path: ':docId',
            parentNavigatorKey: _rootNavigatorKey,
            builder: (context, state) {
              final doc = policyDocumentById(
                state.pathParameters['docId'] ?? '',
              );
              if (doc == null) return const LegalHubScreen();
              return LegalDocumentScreen(document: doc);
            },
          ),
        ],
      ),
      GoRoute(
        path: AppRoutes.paymentCallback,
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => PaymentReturnScreen(
          status: state.uri.queryParameters['status'],
          orderId: state.uri.queryParameters['orderId'],
          hasCallbackToken: state.uri.queryParameters['hasToken'] == '1',
          errorMessage: state.uri.queryParameters['errorMessage'],
        ),
      ),
      GoRoute(
        path: '/recipient-decision/:decisionId',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state) => RecipientDecisionScreen(
          decisionId: state.pathParameters['decisionId'] ?? '',
        ),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            MainShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.home,
                builder: (context, state) => const DashboardScreen(),
                routes: [
                  GoRoute(
                    path: 'notifications',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const NotificationsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.services,
                builder: (context, state) => const ServicesScreen(),
                routes: [
                  GoRoute(
                    path: 'airtime',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => AirtimeScreen(
                      funding: ServiceFunding.parse(
                        state.uri.queryParameters['funding'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'data',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => ServiceTransactionScreen(
                      flow: ServiceFlow.data,
                      funding: ServiceFunding.parse(
                        state.uri.queryParameters['funding'],
                      ),
                    ),
                  ),
                  GoRoute(
                    path: 'global-airtime',
                    parentNavigatorKey: _rootNavigatorKey,
                    // International top-ups ride the same wizard as domestic
                    // airtime, entering at the country step — the Reloadly
                    // branch is picked automatically once the destination
                    // isn't Ghana.
                    builder: (context, state) => const AirtimeScreen(
                      funding: ServiceFunding.momo,
                      initialStep: 1,
                    ),
                  ),
                  GoRoute(
                    path: 'qr-pay',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) =>
                        const ServiceTransactionScreen(flow: ServiceFlow.qrPay),
                  ),
                  GoRoute(
                    path: 'gt-pay',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) =>
                        const ServiceTransactionScreen(flow: ServiceFlow.gtPay),
                  ),
                  GoRoute(
                    path: 'lida-points',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const LidaPointsScreen(),
                  ),
                  GoRoute(
                    path: 'invite-earn',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const InviteEarnScreen(),
                  ),
                  GoRoute(
                    path: 'support',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const SupportScreen(),
                    routes: [
                      GoRoute(
                        path: ':category',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => SupportCategoryScreen(
                          categoryId: state.pathParameters['category'] ?? '',
                        ),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'lida-value',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const LidaValueScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.shop,
                builder: (context, state) => ShopScreen(
                  initialProductId: state.uri.queryParameters['productId'],
                ),
                routes: [
                  GoRoute(
                    path: 'cart',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const CartScreen(),
                  ),
                  GoRoute(
                    path: 'orders',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => OrdersScreen(
                      initialOrderId: state.uri.queryParameters['orderId'],
                    ),
                    routes: [
                      GoRoute(
                        path: ':orderId',
                        parentNavigatorKey: _rootNavigatorKey,
                        builder: (context, state) => OrdersScreen(
                          initialOrderId: state.pathParameters['orderId'],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.history,
                builder: (context, state) => const HistoryScreen(),
                routes: [
                  GoRoute(
                    path: 'analytics',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const AnalyticsScreen(),
                  ),
                ],
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.profile,
                builder: (context, state) => const ProfileScreen(),
                routes: [
                  GoRoute(
                    path: 'edit',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const EditProfileScreen(),
                  ),
                  GoRoute(
                    path: 'change-password',
                    parentNavigatorKey: _rootNavigatorKey,
                    builder: (context, state) => const ChangePasswordScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
  );
});

/// Called by the onboarding screen once completed.
Future<void> markOnboardingSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_onboardingKey, true);
}

/// Whether the user has already completed onboarding.
Future<bool> hasSeenOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_onboardingKey) ?? false;
}
