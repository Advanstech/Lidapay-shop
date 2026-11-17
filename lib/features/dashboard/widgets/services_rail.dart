import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/rail_card.dart';

/// Horizontal rail of highlight services on Home — every card deep-links
/// into a real flow.
class ServicesRail extends StatelessWidget {
  const ServicesRail({super.key});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 128,
      child: ListView(
        scrollDirection: Axis.horizontal,
        clipBehavior: Clip.none,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          RailCard(
            icon: Icons.public_rounded,
            label: 'Global Airtime',
            caption: '150+ countries',
            tint: AppColors.violet,
            onTap: () => context.push(AppRoutes.globalAirtime),
          ),
          const SizedBox(width: 12),
          RailCard(
            icon: Icons.wifi_rounded,
            label: 'Internet Data',
            caption: 'Ghana & worldwide',
            tint: AppColors.success,
            onTap: () => context.push(AppRoutes.data),
          ),
          const SizedBox(width: 12),
          RailCard(
            icon: Icons.phone_android_rounded,
            label: 'Buy Airtime',
            caption: 'Instant top-up',
            tint: AppColors.primary,
            onTap: () => context.push(AppRoutes.airtime),
          ),
          const SizedBox(width: 12),
          RailCard(
            icon: Icons.diamond_outlined,
            label: 'Lida Value',
            caption: 'Use or sell',
            tint: AppColors.gold,
            dark: true,
            onTap: () => context.push(AppRoutes.lidaValue),
          ),
          const SizedBox(width: 12),
          RailCard(
            icon: Icons.stars_rounded,
            label: 'Lida Points',
            caption: 'Redeem rewards',
            tint: AppColors.warning,
            onTap: () => context.push(AppRoutes.lidaPoints),
          ),
          const SizedBox(width: 12),
          RailCard(
            icon: Icons.card_giftcard_rounded,
            label: 'Invite & Earn',
            caption: 'Earn commission',
            tint: AppColors.primaryDark,
            onTap: () => context.push(AppRoutes.inviteEarn),
          ),
        ],
      ),
    );
  }
}
