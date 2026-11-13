import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/product_image.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/skeleton.dart';
import '../../../core/widgets/sticky_header.dart';
import '../data/shop_models.dart';
import '../providers.dart';
import '../widgets/product_card.dart';
import '../widgets/product_detail_sheet.dart';

class ShopScreen extends ConsumerStatefulWidget {
  const ShopScreen({super.key, this.initialProductId});

  final String? initialProductId;

  @override
  ConsumerState<ShopScreen> createState() => _ShopScreenState();
}

class _ShopScreenState extends ConsumerState<ShopScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _handledInitialDeepLink = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkPendingProduct();
    });
  }

  void _checkPendingProduct() {
    final pending = ref.read(pendingShopProductProvider);
    if (pending != null && mounted) {
      ref.read(pendingShopProductProvider.notifier).state = null;
      showProductDetailSheet(context, pending);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
      ref.read(shopSearchQueryProvider.notifier).state = value;
    });
  }

  Future<void> _refresh() async {
    ref.invalidate(shopCategoriesProvider);
    ref.invalidate(shopProductsProvider);
    ref.invalidate(shopFeaturedProvider);
    await Future.wait([
      ref.read(shopCategoriesProvider.future),
      ref.read(shopProductsProvider.future),
      ref.read(shopFeaturedProvider.future),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ShopProduct?>(pendingShopProductProvider, (prev, next) {
      if (next != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ref.read(pendingShopProductProvider.notifier).state = null;
            showProductDetailSheet(context, next);
          }
        });
      }
    });

    final categories = ref.watch(shopCategoriesProvider);
    final products = ref.watch(shopProductsProvider);
    final featured = ref.watch(shopFeaturedProvider);
    final selectedCategory = ref.watch(shopCategoryProvider);
    final cart = ref.watch(cartProvider);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.initialProductId != null && !_handledInitialDeepLink) {
      final catalog = products.valueOrNull ?? const <ShopProduct>[];
      final match = catalog
          .where((p) => p.id == widget.initialProductId)
          .firstOrNull;
      if (match != null) {
        _handledInitialDeepLink = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) showProductDetailSheet(context, match);
        });
      }
    }

    final loading =
        categories is AsyncLoading ||
        (products is AsyncLoading && !products.hasValue) ||
        (featured is AsyncLoading && !featured.hasValue);

    final error =
        products.error ?? (categories.hasValue ? null : categories.error);

    if (loading) return const Scaffold(body: _ShopSkeleton());
    if (error != null) {
      return Scaffold(
        body: ErrorView(message: error.toString(), onRetry: _refresh),
      );
    }

    final featuredList = featured.valueOrNull ?? const <ShopProduct>[];
    final productList = products.valueOrNull ?? const <ShopProduct>[];
    final heroProduct = featuredList.isNotEmpty
        ? featuredList.first
        : (productList.isNotEmpty ? productList.first : null);

    final topInset = MediaQuery.paddingOf(context).top;
    final scaffoldBg = isDark
        ? AppColors.darkScaffold
        : AppColors.lightScaffold;
    final cartCount = cart.valueOrNull?.itemCount ?? 0;

    return Scaffold(
      body: RefreshIndicator(
        onRefresh: _refresh,
        edgeOffset: topInset + 72,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(
            parent: AlwaysScrollableScrollPhysics(),
          ),
          slivers: [
            SliverPersistentHeader(
              pinned: true,
              delegate: StickySliverHeaderDelegate(
                height: topInset + 64,
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
                    padding: EdgeInsets.fromLTRB(20, topInset + 8, 20, 8),
                    child: _ShopTopBar(
                      cartItemCount: cartCount,
                      onBack: () => context.go(AppRoutes.home),
                      onOrdersTap: () => context.push('/shop/orders'),
                      onCartTap: () {
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        context.push(AppRoutes.cart);
                      },
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: _ShopHeroCarousel(
                slides: featuredList.isNotEmpty ? featuredList : [?heroProduct],
                onSlideTap: (p) => showProductDetailSheet(context, p),
              ),
            ),
            SliverPersistentHeader(
              pinned: true,
              delegate: StickySliverHeaderDelegate(
                height: 118,
                builder: (context, isStuck) => DecoratedBox(
                  decoration: BoxDecoration(
                    color: scaffoldBg,
                    boxShadow: isStuck
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(
                                alpha: isDark ? 0.28 : 0.07,
                              ),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ]
                        : null,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 6, 20, 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isDark
                                ? AppColors.darkSurface
                                : Colors.white,
                            borderRadius: BorderRadius.circular(26),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(
                                  alpha: isDark ? 0.25 : 0.06,
                                ),
                                blurRadius: 16,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: TextField(
                            controller: _searchController,
                            onChanged: _onSearchChanged,
                            textInputAction: TextInputAction.search,
                            decoration: InputDecoration(
                              hintText: 'Search products, brands...',
                              hintStyle: TextStyle(
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.65,
                                ),
                                fontSize: 15,
                              ),
                              prefixIcon: Icon(
                                Icons.search_rounded,
                                color: scheme.onSurfaceVariant,
                              ),
                              suffixIcon:
                                  products.isLoading && products.hasValue
                                  ? const Padding(
                                      padding: EdgeInsets.all(13),
                                      child: SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    )
                                  : null,
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                      categories.whenData((data) {
                            final chips = <({String? id, String name})>[
                              (id: null, name: 'All'),
                              ...data.map((c) => (id: c.id, name: c.name)),
                            ];
                            return SizedBox(
                              height: 40,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                ),
                                itemCount: chips.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 10),
                                itemBuilder: (context, index) {
                                  final chip = chips[index];
                                  final selected = chip.id == selectedCategory;
                                  return GestureDetector(
                                    onTap: () =>
                                        ref
                                            .read(shopCategoryProvider.notifier)
                                            .state = chip
                                            .id,
                                    child: AnimatedContainer(
                                      duration: const Duration(
                                        milliseconds: 180,
                                      ),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.primary
                                            : (isDark
                                                  ? AppColors.darkSurface
                                                  : Colors.white),
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(
                                          color: selected
                                              ? AppColors.primary
                                              : (isDark
                                                    ? Colors.white30
                                                    : const Color(0xFF2B2B2B)),
                                          width: 1,
                                        ),
                                      ),
                                      alignment: Alignment.center,
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (selected) ...[
                                            const Icon(
                                              Icons.check_rounded,
                                              size: 16,
                                              color: Colors.white,
                                            ),
                                            const SizedBox(width: 6),
                                          ],
                                          Text(
                                            chip.name,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w700,
                                              color: selected
                                                  ? Colors.white
                                                  : scheme.onSurface,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                            );
                          }).value ??
                          SizedBox(
                            height: 40,
                            child: ListView.separated(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              itemCount: 6,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (_, _) => const AppSkeleton(
                                width: 74,
                                height: 32,
                                borderRadius: 10,
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            if (products.isLoading && products.hasValue)
              const SliverToBoxAdapter(
                child: LinearProgressIndicator(
                  minHeight: 2.5,
                  backgroundColor: Colors.transparent,
                ),
              )
            else
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
            SliverToBoxAdapter(
              child:
                  featured
                      .whenData(
                        (deals) => deals.isEmpty
                            ? const SizedBox.shrink()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                    ),
                                    child: Row(
                                      children: [
                                        Text(
                                          'Featured',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleMedium
                                              ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 18,
                                              ),
                                        ),
                                        const Spacer(),
                                        GestureDetector(
                                          onTap: () =>
                                              ref
                                                      .read(
                                                        shopCategoryProvider
                                                            .notifier,
                                                      )
                                                      .state =
                                                  null,
                                          child: const Text(
                                            'See all',
                                            style: TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.w700,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  SizedBox(
                                    height: 204,
                                    child: ListView.separated(
                                      scrollDirection: Axis.horizontal,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 20,
                                      ),
                                      itemCount: deals.length,
                                      separatorBuilder: (_, _) =>
                                          const SizedBox(width: 14),
                                      itemBuilder: (context, index) => SizedBox(
                                        width: 168,
                                        child: ProductCard(
                                          product: deals[index],
                                          onTap: () => showProductDetailSheet(
                                            context,
                                            deals[index],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 22),
                                ],
                              ),
                      )
                      .value ??
                  const SizedBox.shrink(),
            ),
            const SliverToBoxAdapter(
              child: SectionHeader(
                title: 'All Products',
                caption: 'Everything in the Lidapay store',
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            products
                    .whenData(
                      (list) => list.isEmpty
                          ? const SliverToBoxAdapter(
                              child: EmptyView(
                                title: 'No products found',
                                subtitle: 'Try a different search or category.',
                                icon: Icons.search_off_rounded,
                              ),
                            )
                          : SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                              ),
                              sliver: SliverGrid(
                                gridDelegate:
                                    const SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: 2,
                                      mainAxisSpacing: 14,
                                      crossAxisSpacing: 14,
                                      childAspectRatio: 0.72,
                                    ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) => ProductCard(
                                    product: list[index],
                                    onTap: () => showProductDetailSheet(
                                      context,
                                      list[index],
                                    ),
                                  ),
                                  childCount: list.length,
                                ),
                              ),
                            ),
                    )
                    .value ??
                const SliverToBoxAdapter(child: SizedBox.shrink()),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }
}

class _ShopTopBar extends StatelessWidget {
  const _ShopTopBar({
    required this.cartItemCount,
    required this.onBack,
    required this.onCartTap,
    required this.onOrdersTap,
  });

  final int cartItemCount;
  final VoidCallback onBack;
  final VoidCallback onCartTap;
  final VoidCallback onOrdersTap;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: onBack,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          icon: const Icon(
            Icons.arrow_back_rounded,
            color: Colors.white,
            size: 24,
          ),
        ),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            'Lidapay Shop',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontSize: 19,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3,
            ),
          ),
        ),
        IconButton(
          tooltip: 'My Orders',
          onPressed: onOrdersTap,
          icon: const Icon(
            Icons.receipt_long_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 4),
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.88),
            shape: BoxShape.circle,
          ),
          child: IconButton(
            onPressed: onCartTap,
            icon: Badge(
              isLabelVisible: cartItemCount > 0,
              label: Text('$cartItemCount'),
              child: const Icon(
                Icons.shopping_cart_outlined,
                color: Colors.black87,
                size: 20,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Large featured carousel — every slide shows the real product image on a
/// soft halo so transparent artwork blends into the brand gradient, with
/// auto-advance and dot indicators like the legacy app's hero.
class _ShopHeroCarousel extends StatefulWidget {
  const _ShopHeroCarousel({required this.slides, required this.onSlideTap});

  final List<ShopProduct> slides;
  final ValueChanged<ShopProduct> onSlideTap;

  @override
  State<_ShopHeroCarousel> createState() => _ShopHeroCarouselState();
}

class _ShopHeroCarouselState extends State<_ShopHeroCarousel> {
  late final PageController _pager = PageController();
  Timer? _autoAdvance;
  int _page = 0;

  @override
  void initState() {
    super.initState();
    _startAutoAdvance();
  }

  void _startAutoAdvance() {
    if (widget.slides.length < 2) return;
    _autoAdvance = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_pager.hasClients) return;
      final next = (_page + 1) % widget.slides.length;
      _pager.animateToPage(
        next,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _autoAdvance?.cancel();
    _pager.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scaffoldBg = isDark
        ? AppColors.darkScaffold
        : AppColors.lightScaffold;
    final slides = widget.slides;

    return Container(
      height: 312,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomCenter,
          stops: const [0.0, 0.55, 0.85, 1.0],
          colors: [
            const Color(0xFF33295E),
            const Color(0xFF1B163E),
            const Color(0xFF4B3D7A),
            scaffoldBg,
          ],
        ),
      ),
      child: slides.isEmpty
          ? const _GenericHeroSlide()
          : Stack(
              children: [
                PageView.builder(
                  controller: _pager,
                  itemCount: slides.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, index) => _HeroSlide(
                    product: slides[index],
                    onTap: () => widget.onSlideTap(slides[index]),
                  ),
                ),
                if (slides.length > 1)
                  Positioned(
                    left: 20,
                    bottom: 14,
                    child: Row(
                      children: [
                        for (var i = 0; i < slides.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 6),
                            width: i == _page ? 20 : 7,
                            height: 7,
                            decoration: BoxDecoration(
                              color: i == _page
                                  ? Colors.white
                                  : Colors.white.withValues(alpha: 0.35),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _HeroSlide extends StatelessWidget {
  const _HeroSlide({required this.product, required this.onTap});

  final ShopProduct product;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final discount = product.discountPercent;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (discount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF03E2F),
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        '$discount% OFF',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    )
                  else if (product.isFeatured)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: const Text(
                        'FEATURED',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Text(
                    product.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      height: 1.15,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          'GHS ${product.price.toStringAsFixed(2)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (product.oldPrice != null) ...[
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            'GHS ${product.oldPrice!.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                              fontSize: 15,
                              decoration: TextDecoration.lineThrough,
                              decorationColor: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Shop now',
                          style: TextStyle(
                            color: Color(0xFF1B163E),
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 15,
                          color: Color(0xFF1B163E),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Halo disc: a soft white radial glow so transparent product art
            // sits on a complementary backdrop instead of hard gradient.
            SizedBox(
              width: 190,
              height: 240,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 190,
                    height: 190,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          Colors.white.withValues(alpha: 0.28),
                          Colors.white.withValues(alpha: 0.10),
                          Colors.white.withValues(alpha: 0.0),
                        ],
                        stops: const [0.0, 0.62, 1.0],
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 168,
                    height: 224,
                    child: product.imageAsset.isEmpty
                        ? Icon(
                            Icons.shopping_bag_outlined,
                            size: 96,
                            color: Colors.white.withValues(alpha: 0.75),
                          )
                        : ProductImage(
                            source: product.imageAsset,
                            fit: BoxFit.contain,
                            memCacheWidth: 480,
                          ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GenericHeroSlide extends StatelessWidget {
  const _GenericHeroSlide();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 34),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Text(
                    'LIDAPAY SHOP',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.4,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Everyday essentials, delivered',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    height: 1.15,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Groceries, electronics, data vouchers and more — pay straight from your wallet.',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.85),
                    fontSize: 14,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 190,
            height: 240,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.28),
                        Colors.white.withValues(alpha: 0.10),
                        Colors.white.withValues(alpha: 0.0),
                      ],
                      stops: const [0.0, 0.62, 1.0],
                    ),
                  ),
                ),
                Icon(
                  Icons.shopping_bag_outlined,
                  size: 96,
                  color: Colors.white.withValues(alpha: 0.75),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShopSkeleton extends StatelessWidget {
  const _ShopSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: const [
        AppSkeleton(height: 300, borderRadius: 24),
        SizedBox(height: 18),
        Row(
          children: [
            AppSkeleton(width: 64, height: 42, borderRadius: 21),
            SizedBox(width: 8),
            AppSkeleton(width: 108, height: 42, borderRadius: 21),
            SizedBox(width: 8),
            AppSkeleton(width: 96, height: 42, borderRadius: 21),
          ],
        ),
        SizedBox(height: 24),
        AppSkeleton(width: 140, height: 20),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: AppSkeleton(height: 236, borderRadius: 24)),
            SizedBox(width: 12),
            Expanded(child: AppSkeleton(height: 236, borderRadius: 24)),
          ],
        ),
        SizedBox(height: 24),
        AppSkeleton(width: 140, height: 20),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: AppSkeleton(height: 260, borderRadius: 24)),
            SizedBox(width: 12),
            Expanded(child: AppSkeleton(height: 260, borderRadius: 24)),
          ],
        ),
        SizedBox(height: 12),
        Row(
          children: [
            Expanded(child: AppSkeleton(height: 260, borderRadius: 24)),
            SizedBox(width: 12),
            Expanded(child: AppSkeleton(height: 260, borderRadius: 24)),
          ],
        ),
      ],
    );
  }
}
