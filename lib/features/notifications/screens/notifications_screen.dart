import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../data/notification_models.dart';
import '../providers.dart';

/// Notification Center — every push/email/SMS/in-app notification for the
/// signed-in user, with local read state, swipe-to-delete and a detail view.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  Future<void> _refresh(WidgetRef ref) async {
    ref.invalidate(rawNotificationsProvider);
    try {
      await ref.read(rawNotificationsProvider.future);
    } catch (_) {
      // The error state surfaces inline.
    }
  }

  Future<void> _markAllRead(WidgetRef ref) async {
    final items = ref.read(notificationsProvider).valueOrNull ?? const [];
    final allKeys = <String>{};
    for (final n in items) {
      allKeys.add(n.id);
      allKeys.addAll(n.mergedIds);
      allKeys.add('${n.kind}|${n.displayMessage}');
    }
    await ref.read(readNotificationsProvider.notifier).markAll(allKeys);
  }

  Future<void> _open(
    BuildContext context,
    WidgetRef ref,
    AppNotification n,
  ) async {
    final decisionId = n.data['decisionId']?.toString().trim();
    await ref.read(readNotificationsProvider.notifier).markRead(
      n.id,
      relatedKeys: [
        ...n.mergedIds,
        if (decisionId != null && decisionId.isNotEmpty) ...[
          'decision_$decisionId',
          'decision|$decisionId',
        ],
      ],
    );
    if (!context.mounted) return;
    final targetRoute = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationDetailSheet(
        notification: n.copyWith(isRead: true),
      ),
    );
    if (targetRoute == null || !context.mounted) return;
    if (targetRoute.startsWith('/shop/orders') ||
        targetRoute == AppRoutes.lidaValue ||
        targetRoute.startsWith('/recipient-decision/')) {
      context.push(targetRoute);
    } else {
      context.go(targetRoute);
    }
  }

  Future<void> _dismiss(
    BuildContext context,
    WidgetRef ref,
    AppNotification n,
  ) async {
    final idsToDismiss = {n.id, ...n.mergedIds};
    final dismissed = ref.read(dismissedNotificationsProvider);
    ref.read(dismissedNotificationsProvider.notifier).state = {
      ...dismissed,
      ...idsToDismiss,
    };
    ref.read(readNotificationsProvider.notifier).markAll(idsToDismiss);
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('Notification removed')));
    try {
      await ref.read(notificationsRepositoryProvider).deleteNotification(n.id);
    } on ApiException {
      // Bring it back if the delete failed server-side.
      final current = ref.read(dismissedNotificationsProvider);
      ref.read(dismissedNotificationsProvider.notifier).state = current
          .difference(idsToDismiss);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not delete. Try again.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifications = ref.watch(notificationsProvider);
    final unread = ref.watch(unreadNotificationsProvider);

    return Scaffold(
      body: Column(
        children: [
          _NotificationsHeader(
            unread: unread,
            onBack: () => context.pop(),
            onMarkAll: unread == 0 ? null : () => _markAllRead(ref),
          ),
          Expanded(
            child: notifications.when(
              loading: () => ListView(
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.all(20),
                children: const [
                  AppSkeleton(height: 86, borderRadius: 20),
                  SizedBox(height: 12),
                  AppSkeleton(height: 86, borderRadius: 20),
                  SizedBox(height: 12),
                  AppSkeleton(height: 86, borderRadius: 20),
                  SizedBox(height: 12),
                  AppSkeleton(height: 86, borderRadius: 20),
                ],
              ),
              error: (error, _) => ErrorView(
                message: error.toString(),
                onRetry: () => _refresh(ref),
              ),
              data: (items) => items.isEmpty
                  ? const EmptyView(
                      title: 'All caught up',
                      subtitle: 'Order updates, transaction alerts and offers will show up here.',
                    )
                  : RefreshIndicator(
                      onRefresh: () => _refresh(ref),
                      child: ListView.separated(
                        physics: const BouncingScrollPhysics(
                          parent: AlwaysScrollableScrollPhysics(),
                        ),
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                        itemCount: items.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final n = items[index];
                          return _NotificationCard(
                            notification: n,
                            onTap: () => _open(context, ref, n),
                            onDismissed: () => _dismiss(context, ref, n),
                          );
                        },
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationsHeader extends StatelessWidget {
  const _NotificationsHeader({
    required this.unread,
    required this.onBack,
    required this.onMarkAll,
  });

  final int unread;
  final VoidCallback onBack;
  final VoidCallback? onMarkAll;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 14,
        20,
        20,
      ),
      decoration: const BoxDecoration(
        gradient: AppColors.heroGradient,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: onBack,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Notifications',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  unread == 0 ? 'You\'re all caught up' : '$unread unread',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.75),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          if (onMarkAll != null)
            TextButton(
              onPressed: onMarkAll,
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.white.withValues(alpha: 0.14),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Mark all read',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
              ),
            ),
        ],
      ),
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({
    required this.notification,
    required this.onTap,
    required this.onDismissed,
  });

  final AppNotification notification;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final unread = !notification.isRead;

    return Dismissible(
      key: ValueKey('notification_${notification.id}'),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        decoration: BoxDecoration(
          color: const Color(0xFFE5484D),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.white,
          size: 26,
        ),
      ),
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: unread
                    ? AppColors.primary.withValues(alpha: 0.35)
                    : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: unread ? AppColors.brandGradient : null,
                    color: unread
                        ? null
                        : (isDark ? Colors.white12 : const Color(0xFFF1EFF5)),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    _iconFor(notification),
                    size: 22,
                    color: unread ? Colors.white : scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        notification.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: unread
                              ? FontWeight.w800
                              : FontWeight.w600,
                          color: scheme.onSurface,
                        ),
                      ),
                      if (notification.displayMessage.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          notification.displayMessage,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            height: 1.35,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Text(
                            Formatters.timeAgo(notification.createdAt),
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (notification.needsAction)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withValues(
                                  alpha: 0.12,
                                ),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                'Action needed',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primary,
                                ),
                              ),
                            )
                          else
                            _ChannelChip(channel: notification.channel),
                        ],
                      ),
                    ],
                  ),
                ),
                if (unread)
                  Container(
                    width: 9,
                    height: 9,
                    margin: const EdgeInsets.only(top: 4, left: 8),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static IconData _iconFor(AppNotification n) {
    return switch (n.kind) {
      'decision' => Icons.reply_rounded,
      'resolved' => Icons.check_circle_outline_rounded,
      'airtime' => Icons.phone_iphone_rounded,
      'data' => Icons.wifi_rounded,
      'order' => Icons.shopping_bag_outlined,
      'wallet' => Icons.diamond_outlined,
      'security' => Icons.shield_outlined,
      'promo' => Icons.local_offer_outlined,
      _ when n.channel == 'email' => Icons.mail_outline_rounded,
      _ when n.channel == 'sms' => Icons.sms_outlined,
      _ => Icons.notifications_outlined,
    };
  }
}

class _ChannelChip extends StatelessWidget {
  const _ChannelChip({required this.channel});

  final String channel;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = switch (channel) {
      'email' => 'Email',
      'sms' => 'SMS',
      'push' => 'Push',
      _ => 'In-app',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isDark ? Colors.white10 : const Color(0xFFF1EFF5),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _ReadStatusChip extends StatelessWidget {
  const _ReadStatusChip({required this.isRead});

  final bool isRead;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isRead
            ? const Color(0xFFEAF8EE)
            : AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        isRead ? 'READ' : 'UNREAD',
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: isRead ? const Color(0xFF33B457) : AppColors.primary,
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final (bg, fg, label) = switch (status.toLowerCase()) {
      'pending' => (
        const Color(0xFFFFF4E0),
        const Color(0xFFB25E09),
        'PENDING',
      ),
      'failed' => (const Color(0xFFFDECEC), const Color(0xFFE5484D), 'FAILED'),
      _ => (const Color(0xFFEAF8EE), const Color(0xFF33B457), 'DELIVERED'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }
}

class _NotificationDetailSheet extends StatelessWidget {
  const _NotificationDetailSheet({required this.notification});

  final AppNotification notification;

  /// A parked top-up decision carries its `decisionId` in the push payload —
  /// tapping through lands the recipient on the choice screen.
  String? get _decisionId {
    if (!notification.needsAction) return null;
    final raw = notification.data['decisionId'];
    final id = raw?.toString().trim() ?? '';
    return id.isEmpty ? null : id;
  }

  /// Where the notification should take the user next — the destination is
  /// derived from the event kind so every card lands somewhere useful.
  ({String label, IconData icon, String route})? get _cta {
    switch (notification.kind) {
      case 'resolved':
      case 'airtime':
      case 'data':
        return (
          label: 'View in transaction history',
          icon: Icons.receipt_long_rounded,
          route: AppRoutes.history,
        );
      case 'order':
        final orderId =
            (notification.data['orderId'] ?? notification.data['shopOrderId'])
                ?.toString()
                .trim();
        return (
          label: orderId != null && orderId.isNotEmpty
              ? 'Track your order'
              : 'View my orders',
          icon: Icons.shopping_bag_outlined,
          route: orderId != null && orderId.isNotEmpty
              ? AppRoutes.orderDetail(orderId)
              : AppRoutes.orders,
        );
      case 'wallet':
        return (
          label: 'Open Lida Value',
          icon: Icons.diamond_outlined,
          route: AppRoutes.lidaValue,
        );
      case 'security':
        return (
          label: 'Review your profile',
          icon: Icons.shield_outlined,
          route: AppRoutes.profile,
        );
      case 'promo':
        return (
          label: 'Browse the shop',
          icon: Icons.local_offer_outlined,
          route: AppRoutes.shop,
        );
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final local = notification.createdAt.toLocal();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: isDark ? AppColors.darkScaffold : const Color(0xFFF6F6F9),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
                  decoration: const BoxDecoration(
                    gradient: AppColors.heroGradient,
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 44,
                            height: 44,
                            decoration: BoxDecoration(
                              gradient: AppColors.brandGradient,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Icon(
                              _NotificationCard._iconFor(notification),
                              color: Colors.white,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              notification.displayTitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close_rounded,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          DateFormat('EEEE, d MMM yyyy · h:mm a').format(local),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.75),
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: cardBg,
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              _ChannelChip(channel: notification.channel),
                              const SizedBox(width: 8),
                              _StatusChip(status: notification.status),
                              const SizedBox(width: 8),
                              _ReadStatusChip(isRead: notification.isRead),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Text(
                            notification.displayMessage.isEmpty
                                ? 'No details provided.'
                                : notification.displayMessage,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.5,
                              color: scheme.onSurface,
                            ),
                          ),
                          if (_decisionId != null) ...[
                            const SizedBox(height: 18),
                            AppButton(
                              label: 'Choose how to receive it',
                              icon: const Icon(
                                Icons.reply_rounded,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () {
                                Navigator.of(context).pop(
                                  AppRoutes.recipientDecision(_decisionId!),
                                );
                              },
                            ),
                          ] else if (_cta case final cta?) ...[
                            const SizedBox(height: 18),
                            AppButton(
                              label: cta.label,
                              icon: Icon(
                                cta.icon,
                                color: Colors.white,
                                size: 18,
                              ),
                              onPressed: () {
                                Navigator.of(context).pop(cta.route);
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
