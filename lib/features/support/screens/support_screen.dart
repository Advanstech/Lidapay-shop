import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/sticky_header.dart';
import '../support_data.dart';
import '../widgets/support_widgets.dart';

/// Support Center — search-first help home. Category cards lead to detail
/// pages; contact channels and legal docs are always one tap away.
class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key});

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<({SupportCategory category, SupportFaq faq})> get _results {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return allFaqs()
        .where(
          (e) =>
              e.faq.question.toLowerCase().contains(q) ||
              e.faq.answer.toLowerCase().contains(q) ||
              e.category.title.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final topInset = MediaQuery.paddingOf(context).top;
    final searching = _query.trim().isNotEmpty;

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
                              'Support Center',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.3,
                              ),
                            ),
                            Text(
                              'We reply fast — usually same day',
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
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 22),
              decoration: const BoxDecoration(
                gradient: AppColors.heroGradient,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(28),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'How can we help?',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.95),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _search,
                    onChanged: (v) => setState(() => _query = v),
                    style: const TextStyle(color: Colors.white, fontSize: 14.5),
                    cursorColor: Colors.white,
                    decoration: InputDecoration(
                      hintText: 'Search “pending payment”, “Lida Value”…',
                      hintStyle: TextStyle(
                        color: Colors.white.withValues(alpha: 0.55),
                        fontSize: 14,
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                      suffixIcon: _query.isEmpty
                          ? null
                          : GestureDetector(
                              onTap: () => setState(() {
                                _search.clear();
                                _query = '';
                              }),
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withValues(alpha: 0.75),
                              ),
                            ),
                      filled: true,
                      fillColor: Colors.white.withValues(alpha: 0.13),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                          color: Colors.white.withValues(alpha: 0.45),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: _ContactChip(
                          icon: Icons.call_rounded,
                          label: 'Call us',
                          onTap: () => launchUrl(supportPhoneUri),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _ContactChip(
                          icon: Icons.email_rounded,
                          label: 'Email us',
                          onTap: () => launchUrl(supportEmailUri()),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (searching) ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
                child: Text(
                  _results.isEmpty
                      ? 'No matches — try different words'
                      : '${_results.length} answer${_results.length == 1 ? '' : 's'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SliverList.separated(
              itemCount: _results.length,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                final entry = _results[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FaqSearchTile(
                    faq: entry.faq,
                    category: entry.category,
                    onTap: () => context.push(
                      '${AppRoutes.support}/${entry.category.id}',
                    ),
                  ),
                );
              },
            ),
          ] else ...[
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 20, 20, 4),
                child: _SectionLabel('Browse by topic'),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(20),
              sliver: SliverGrid.builder(
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 240,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.92,
                ),
                itemCount: supportCategories.length,
                itemBuilder: (context, index) {
                  final category = supportCategories[index];
                  return _CategoryCard(
                    category: category,
                    onTap: () =>
                        context.push('${AppRoutes.support}/${category.id}'),
                  );
                },
              ),
            ),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 4),
                child: _SectionLabel('Popular right now'),
              ),
            ),
            SliverList.separated(
              itemCount: 3,
              separatorBuilder: (_, _) => const SizedBox(height: 10),
              itemBuilder: (context, index) {
                // Curated top-3: the questions support hears most.
                const picks = [
                  (category: 0, faq: 0), // pending payment
                  (category: 2, faq: 0), // LV vs Points
                  (category: 1, faq: 1), // recipient choice
                ];
                final pick = picks[index];
                final category = supportCategories[pick.category];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: FaqSearchTile(
                    faq: category.faqs[pick.faq],
                    category: category,
                    onTap: () =>
                        context.push('${AppRoutes.support}/${category.id}'),
                  ),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: LegalRowTile(onTap: () => context.push(AppRoutes.legal)),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 14)),
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 20),
                child: SupportContactCard(),
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

class _ContactChip extends StatelessWidget {
  const _ContactChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryCard extends StatelessWidget {
  const _CategoryCard({required this.category, required this.onTap});

  final SupportCategory category;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark ? AppColors.darkSurface : Colors.white,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
            ),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: category.gradient,
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(category.icon, color: Colors.white, size: 22),
              ),
              const Spacer(),
              Text(
                category.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '${category.faqs.length} answers',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
