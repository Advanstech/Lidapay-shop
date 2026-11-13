import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/sticky_header.dart';
import '../legal_content.dart';
import '../policy_acceptance.dart';

/// Legal & Policies hub — every binding document plus the account's
/// acceptance state. When the accepted version is stale, a prominent
/// review card pins to the top and asks the user to re-accept.
class LegalHubScreen extends ConsumerWidget {
  const LegalHubScreen({super.key});

  static const _meta = <String, (IconData, List<Color>)>{
    'privacy': (
      Icons.privacy_tip_rounded,
      [Color(0xFF1FA97A), Color(0xFF059669)],
    ),
    'terms': (Icons.gavel_rounded, [Color(0xFF4A3AFF), Color(0xFF2B1BC9)]),
    'payments': (
      Icons.payments_rounded,
      [Color(0xFFF6C453), Color(0xFFF59E0B)],
    ),
    'kyc': (Icons.fingerprint_rounded, [Color(0xFF9327F0), Color(0xFF5D0CF5)]),
    'account-deletion': (
      Icons.person_remove_rounded,
      [Color(0xFFDC2626), Color(0xFF991B1B)],
    ),
    'about': (Icons.info_rounded, [Color(0xFF0EA5E9), Color(0xFF0369A1)]),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final status = ref.watch(policyStatusProvider).valueOrNull;
    final needsReview = status?.isCurrent != true;
    final topInset = MediaQuery.paddingOf(context).top;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: StickySliverHeaderDelegate(
              height: topInset + 70,
              builder: (context, isStuck) => DecoratedBox(
                decoration: BoxDecoration(
                  gradient: AppColors.heroGradient,
                  boxShadow: isStuck
                      ? [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ]
                      : null,
                ),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, topInset + 10, 20, 10),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => context.pop(),
                        child: Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(13),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.18),
                            ),
                          ),
                          alignment: Alignment.center,
                          child: const Icon(
                            Icons.arrow_back_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Legal & Policies',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              'The terms that protect you',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.78),
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          if (needsReview)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF33295E), Color(0xFF1B163E)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(
                            Icons.fact_check_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                          SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Review our policies',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We updated our terms. Please review the documents '
                        'below and confirm you still agree — it keeps your '
                        'account fully protected.',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.82),
                          fontSize: 13.5,
                          height: 1.5,
                        ),
                      ),
                      const SizedBox(height: 14),
                      AppButton(
                        label: 'I’ve read them — accept & continue',
                        onPressed: () =>
                            ref.read(policyStatusProvider.notifier).accept(),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.success.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.verified_rounded,
                        color: AppColors.success,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          status == null
                              ? 'Policies apply from your first sign-in.'
                              : 'You accepted version ${status.version} of '
                                    'our policies.',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          SliverList.separated(
            itemCount: allPolicyDocuments.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = allPolicyDocuments[index];
              final meta =
                  _meta[doc.id] ??
                  (
                    Icons.description_rounded,
                    const [Color(0xFF33295E), Color(0xFF1B163E)],
                  );
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Material(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(18),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: () => context.push('${AppRoutes.legal}/${doc.id}'),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: meta.$2,
                              ),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Icon(meta.$1, color: Colors.white, size: 22),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.title,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  doc.subtitle,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: scheme.onSurfaceVariant,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}
