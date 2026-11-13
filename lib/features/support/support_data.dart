// Static help content for the Support Center. Contact channels are the
// live actions; category FAQs and deep links are curated and kept in sync
// with the actual feature set.
import 'package:flutter/material.dart';

import '../../core/router/app_router.dart';
import '../legal/legal_content.dart' show supportEmail, supportPhoneDial;

class SupportFaq {
  const SupportFaq({required this.question, required this.answer});

  final String question;
  final String answer;
}

class SupportAction {
  const SupportAction({
    required this.label,
    required this.icon,
    required this.route,
  });

  final String label;
  final IconData icon;

  /// A go_router location pushed on tap (e.g. `AppRoutes.history`).
  final String route;
}

class SupportCategory {
  const SupportCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.faqs,
    this.actions = const [],
  });

  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final List<SupportFaq> faqs;

  /// "Try this first" deep links shown above the contact card on the
  /// category page — solves the issue inside the app when possible.
  final List<SupportAction> actions;
}

const supportCategories = <SupportCategory>[
  SupportCategory(
    id: 'payments',
    title: 'Payments & wallet',
    subtitle: 'Top-ups, pending payments, MoMo & wallet balance',
    icon: Icons.payments_rounded,
    gradient: [Color(0xFF4A3AFF), Color(0xFF2B1BC9)],
    actions: [
      SupportAction(
        label: 'Check a transaction status',
        icon: Icons.receipt_long_rounded,
        route: AppRoutes.history,
      ),
      SupportAction(
        label: 'Review payments & refunds policy',
        icon: Icons.policy_rounded,
        route: '${AppRoutes.legal}/payments',
      ),
    ],
    faqs: [
      SupportFaq(
        question: 'I paid but my wallet or top-up shows pending — what now?',
        answer:
            'Payments confirm inside a short verification window after '
            'checkout. Keep the app open on the confirmation screen, or '
            'return later and pull-to-refresh your activity — a verified '
            'payment always settles. If it stays pending past 10 minutes, '
            'note the reference in Activity and contact us.',
      ),
      SupportFaq(
        question: 'My payment was charged but the service was not delivered',
        answer:
            'Failed deliveries stay visible in Activity with their status '
            'and reason. Share the transaction reference with support — the '
            'amount is redelivered or refunded to the funding source.',
      ),
      SupportFaq(
        question: 'Why did the checkout page open in my browser?',
        answer:
            'Lidapay uses AdvansisPay secure checkout for card and mobile '
            'money payments. After paying, the browser hands you back to '
            'the app automatically — if it does not, return to the app and '
            'tap “I’ve paid, check status”.',
      ),
      SupportFaq(
        question: 'How do I add money to my Lidapay wallet?',
        answer:
            'Wallet funding runs through the same secure checkout as '
            'airtime purchases. Your wallet balance appears on the '
            'dashboard and Profile once the payment verifies.',
      ),
    ],
  ),
  SupportCategory(
    id: 'airtime',
    title: 'Airtime & data',
    subtitle: 'Delivery times, networks, international top-ups',
    icon: Icons.network_cell_rounded,
    gradient: [Color(0xFF1FA97A), Color(0xFF059669)],
    actions: [
      SupportAction(
        label: 'Start a new airtime purchase',
        icon: Icons.phone_android_rounded,
        route: AppRoutes.airtime,
      ),
      SupportAction(
        label: 'Start a new data purchase',
        icon: Icons.wifi_rounded,
        route: AppRoutes.data,
      ),
    ],
    faqs: [
      SupportFaq(
        question: 'How long does airtime or data take to arrive?',
        answer:
            'Ghana networks (via One4All/Prymo) usually deliver in under a '
            'minute after payment verifies. International top-ups through '
            'Reloadly can take a few minutes depending on the operator.',
      ),
      SupportFaq(
        question: 'The recipient got a choice notification — what is that?',
        answer:
            'When you send to a number registered on Lidapay, the '
            'recipient picks direct airtime/data or saving it as Lida '
            'Value. If they don’t respond in about 5 minutes, it settles '
            'into their Lida Value automatically.',
      ),
      SupportFaq(
        question: 'I sent to the wrong number — can it be reversed?',
        answer:
            'Airtime delivered to a valid number can’t be recalled by the '
            'network. If the destination was a registered Lidapay user, '
            'contact support immediately — unclaimed decisions can still '
            'be intercepted before they resolve.',
      ),
      SupportFaq(
        question: 'Which networks and countries are supported?',
        answer:
            'All Ghana networks (MTN, Telecel, AirtelTigo) plus a wide '
            'international operator list. Pick the country first and the '
            'app auto-detects the operator from the phone number.',
      ),
    ],
  ),
  SupportCategory(
    id: 'lidavalue',
    title: 'Lida Value & Points',
    subtitle: 'LV balance, use/send/sell/convert, reward points',
    icon: Icons.diamond_rounded,
    gradient: [Color(0xFF9327F0), Color(0xFF5D0CF5)],
    actions: [
      SupportAction(
        label: 'Open my Lida Value wallet',
        icon: Icons.diamond_outlined,
        route: AppRoutes.lidaValue,
      ),
      SupportAction(
        label: 'View my Lida Points',
        icon: Icons.stars_rounded,
        route: AppRoutes.lidaPoints,
      ),
    ],
    faqs: [
      SupportFaq(
        question: 'What’s the difference between Lida Value and Lida Points?',
        answer:
            'Lida Value (LV) is a spendable balance — use it for airtime '
            'and data, send it, sell it, or convert it. Lida Points are '
            'loyalty rewards you earn on activity; they track separately '
            'and redeem through the Points page.',
      ),
      SupportFaq(
        question: 'How do I spend Lida Value on airtime or data?',
        answer:
            'Open Lida Value and tap USE for yourself or SEND for someone '
            'else — both walk the same airtime/data flow but debit your LV '
            'balance directly instead of charging a payment method.',
      ),
      SupportFaq(
        question: 'My LV debit succeeded but delivery failed',
        answer:
            'Your LV is safe — a failed delivery after debit keeps its '
            'reference for reconciliation and the units are restored or '
            'redelivered. Check the entry in Lida Value history, then '
            'contact support if it isn’t resolved within a few minutes.',
      ),
      SupportFaq(
        question: 'How do I earn more Lida Points?',
        answer:
            'Points accrue on qualifying transactions and promotions. The '
            'Invite & Earn page also rewards referrals once the invited '
            'friend completes their first transaction.',
      ),
    ],
  ),
  SupportCategory(
    id: 'shop',
    title: 'Shop & orders',
    subtitle: 'Checkout, delivery, tracking & returns',
    icon: Icons.storefront_rounded,
    gradient: [Color(0xFFF6C453), Color(0xFFF59E0B)],
    actions: [
      SupportAction(
        label: 'Browse the shop',
        icon: Icons.shopping_bag_rounded,
        route: AppRoutes.shop,
      ),
      SupportAction(
        label: 'Review orders in Activity',
        icon: Icons.local_shipping_rounded,
        route: AppRoutes.history,
      ),
    ],
    faqs: [
      SupportFaq(
        question: 'Where is my order?',
        answer:
            'Order status appears in Activity next to your transactions. '
            'Physical deliveries are handled by our partner couriers — '
            'share the order reference with support for live tracking.',
      ),
      SupportFaq(
        question: 'Can I cancel an order?',
        answer:
            'Orders can be cancelled before dispatch. Once dispatched, '
            'returns follow the inspection policy — refunds go back to '
            'the original payment method after the item is received.',
      ),
      SupportFaq(
        question: 'Do you deliver outside Accra?',
        answer:
            'Yes — delivery partners cover major regions. Enter your '
            'delivery address at checkout and the estimate shown reflects '
            'your location.',
      ),
    ],
  ),
  SupportCategory(
    id: 'account',
    title: 'Account & verification',
    subtitle: 'Sign-in, OTP, profile and KYC',
    icon: Icons.verified_user_rounded,
    gradient: [Color(0xFF33295E), Color(0xFF1B163E)],
    actions: [
      SupportAction(
        label: 'Update my profile',
        icon: Icons.badge_rounded,
        route: AppRoutes.editProfile,
      ),
      SupportAction(
        label: 'Review the privacy policy',
        icon: Icons.privacy_tip_rounded,
        route: '${AppRoutes.legal}/privacy',
      ),
    ],
    faqs: [
      SupportFaq(
        question: 'I’m not receiving the sign-in code',
        answer:
            'OTP codes go to your registered email. Check spam/promotions, '
            'wait for the resend cooldown, then request again. Signing in '
            'with your password also works without a code.',
      ),
      SupportFaq(
        question: 'How do I verify my account (KYC)?',
        answer:
            'Complete your profile details under Profile & KYC. The '
            'verified badge appears once your information is confirmed — '
            'verification unlocks higher transaction limits.',
      ),
      SupportFaq(
        question: 'How do I change my phone number?',
        answer:
            'Phone is your account identity, so it can’t be edited '
            'directly. Contact support with proof of ownership for the '
            'old and new numbers and we’ll migrate the account.',
      ),
      SupportFaq(
        question: 'Can I delete my account and data?',
        answer:
            'Yes. Sign in, open Profile and select Delete Account. If you '
            'cannot sign in, email support from your registered address. '
            'Withdraw or spend remaining balances first; some records may '
            'be retained where the law requires.',
      ),
    ],
  ),
  SupportCategory(
    id: 'technical',
    title: 'App & technical',
    subtitle: 'Crashes, notifications, connectivity',
    icon: Icons.build_circle_rounded,
    gradient: [Color(0xFF0EA5E9), Color(0xFF0369A1)],
    actions: [
      SupportAction(
        label: 'Check my notifications',
        icon: Icons.notifications_rounded,
        route: AppRoutes.notifications,
      ),
    ],
    faqs: [
      SupportFaq(
        question: 'The app feels stuck or a page won’t load',
        answer:
            'Pull-to-refresh first — most pages refetch on gesture. If it '
            'persists, sign out and back in to refresh the session, and '
            'make sure you’re on the latest app version.',
      ),
      SupportFaq(
        question: 'I’m not getting push notifications',
        answer:
            'Check the notification permission in your device settings '
            'for Lidapay, then confirm the app’s notification bell shows '
            'recent events. If in-app events arrive but pushes don’t, '
            'contact support with your device model.',
      ),
      SupportFaq(
        question: 'Which devices does Lidapay support?',
        answer:
            'Lidapay runs on modern Android and iOS devices. For the best '
            'experience keep your OS and the app updated — security '
            'features rely on current system components.',
      ),
    ],
  ),
];

/// Flattens every FAQ with its category for the support search.
List<({SupportCategory category, SupportFaq faq})> allFaqs() {
  return [
    for (final category in supportCategories)
      for (final faq in category.faqs) (category: category, faq: faq),
  ];
}

/// Prefilled support e-mail with device/account context the user can edit.
Uri supportEmailUri({String? categoryTitle}) {
  final subject = categoryTitle == null
      ? 'Lidapay support request'
      : 'Lidapay support — $categoryTitle';
  return Uri(
    scheme: 'mailto',
    path: supportEmail,
    query:
        'subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent('Hi Lidapay team,\n\n'
        'I need help with:\n\n'
        '(transaction or order reference, if any):\n\n'
        '— sent from the Lidapay app')}',
  );
}

Uri get supportPhoneUri => Uri(scheme: 'tel', path: supportPhoneDial);

SupportCategory? supportCategoryById(String id) {
  for (final category in supportCategories) {
    if (category.id == id) return category;
  }
  return null;
}
