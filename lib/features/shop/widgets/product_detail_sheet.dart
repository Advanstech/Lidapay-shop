import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/product_image.dart';
import '../data/shop_models.dart';
import '../providers.dart';

/// Product detail presented as a full-height sheet from the browse grid.
/// If the user picks a product from "You Might Also Like", the active sheet
/// smoothly collapses first and the newly selected product sheet slides in.
Future<void> showProductDetailSheet(
  BuildContext context,
  ShopProduct product,
) async {
  ShopProduct? current = product;
  while (current != null) {
    if (!context.mounted) break;
    final chosen = current;
    final next = await showModalBottomSheet<ShopProduct>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => FractionallySizedBox(
        heightFactor: 0.94,
        child: ProductDetailSheet(
          key: ValueKey('product-detail-${chosen.id}'),
          product: chosen,
        ),
      ),
    );
    if (next == null) break;
    // Brief pause so the user sees the previous sheet finish collapsing
    // before the newly selected product sheet rises into view.
    await Future<void>.delayed(const Duration(milliseconds: 140));
    current = next;
  }
}

class ProductDetailSheet extends ConsumerStatefulWidget {
  const ProductDetailSheet({super.key, required this.product});

  final ShopProduct product;

  @override
  ConsumerState<ProductDetailSheet> createState() => _ProductDetailSheetState();
}

class _ProductDetailSheetState extends ConsumerState<ProductDetailSheet> {
  late ShopProduct _activeProduct = widget.product;
  final _imagePager = PageController();
  int _imagePage = 0;
  int _quantity = 1;
  bool _showSpecs = false;
  bool _expandedDescription = false;

  ShopProduct get product => _activeProduct;

  @override
  void initState() {
    super.initState();
    _hydrate();
  }

  @override
  void dispose() {
    _imagePager.dispose();
    super.dispose();
  }

  /// The browse list payload can be leaner than `/shop/products/{id}` — the
  /// detail call brings the full description, gallery and attributes.
  Future<void> _hydrate() async {
    try {
      final fresh = await ref
          .read(shopRepositoryProvider)
          .getProduct(_activeProduct.id);
      if (fresh != null && mounted) {
        setState(() => _activeProduct = fresh);
      }
    } catch (_) {
      // The row data still renders — hydration is best-effort.
    }
  }

  void _step(int delta) {
    setState(
      () => _quantity = (_quantity + delta).clamp(1, product.stock).toInt(),
    );
  }

  void _selectRelatedProduct(ShopProduct next) {
    HapticFeedback.selectionClick();
    // Pop with [next] so showProductDetailSheet smoothly collapses this sheet
    // and slides up a fresh sheet for the newly chosen item.
    Navigator.of(context).pop(next);
  }

  /// The heart is a selection, not decoration — it is stored per user and
  /// shared with the browse card, so it survives closing this sheet.
  Future<void> _toggleLoved() async {
    HapticFeedback.selectionClick();
    final loved = await ref
        .read(lovedProductsProvider.notifier)
        .toggle(product.id);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 2),
        content: Text(
          loved
              ? '${product.name} saved to loved items'
              : '${product.name} removed from loved items',
        ),
      ),
    );
  }

  Future<void> _addToCart() async {
    await ref.read(cartProvider.notifier).add(product, quantity: _quantity);
    if (!mounted) return;
    if (ref.read(cartProvider).hasError) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not add to cart — check your connection and try again.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${product.name} ×$_quantity added to cart')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final discount = product.discountPercent;
    final adding = ref.watch(cartProvider) is AsyncLoading;
    final cartCount = ref.watch(cartProvider).valueOrNull?.itemCount ?? 0;
    final loved = ref.watch(lovedProductsProvider).contains(product.id);
    final allProducts =
        ref.watch(shopProductsProvider).valueOrNull ?? const <ShopProduct>[];
    final relatedProducts = allProducts
        .where((p) => p.id != product.id)
        .take(8)
        .toList();
    final savings =
        product.oldPrice != null && product.oldPrice! > product.price
        ? product.oldPrice! - product.price
        : 0.0;
    final surfaceBg = isDark ? AppColors.darkScaffold : AppColors.lightScaffold;
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : const Color(0xFFE7E5EC);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: surfaceBg,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DetailHeroHeader(
                      product: product,
                      surfaceBg: surfaceBg,
                      favorited: loved,
                      cartCount: cartCount,
                      imagePager: _imagePager,
                      imagePage: _imagePage,
                      onImagePage: (i) => setState(() => _imagePage = i),
                      onBack: () => Navigator.of(context).pop(),
                      onToggleFavorite: _toggleLoved,
                      onOpenCart: () {
                        Navigator.of(context).pop();
                        context.push(AppRoutes.cart);
                      },
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? AppColors.darkInput
                                      : const Color(0xFFF1F1F4),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Text(
                                  'SKU: ${product.displaySku.toUpperCase()}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: scheme.onSurface,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: product.inStock
                                      ? AppColors.success.withValues(
                                          alpha: 0.12,
                                        )
                                      : scheme.error.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      product.inStock
                                          ? Icons.check_circle_rounded
                                          : Icons.cancel_rounded,
                                      size: 13,
                                      color: product.inStock
                                          ? AppColors.success
                                          : scheme.error,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      product.inStock
                                          ? 'In Stock (${product.stock})'
                                          : 'Out of Stock',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w800,
                                        color: product.inStock
                                            ? AppColors.success
                                            : scheme.error,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Spacer(),
                              if (discount > 0)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFCE8E6),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Text(
                                    '$discount% OFF',
                                    style: const TextStyle(
                                      color: Color(0xFFE8432E),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            product.name,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  height: 1.25,
                                ),
                          ),
                          const SizedBox(height: 18),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 16,
                            ),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: borderColor),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Promo Price',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerLeft,
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'GHS ${product.price.toStringAsFixed(2)}',
                                              style: const TextStyle(
                                                color: AppColors.primary,
                                                fontSize: 22,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            if (product.oldPrice != null) ...[
                                              const SizedBox(width: 10),
                                              Text(
                                                'GHS ${product.oldPrice!.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  color:
                                                      scheme.onSurfaceVariant,
                                                  fontSize: 16,
                                                  decoration: TextDecoration
                                                      .lineThrough,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (savings > 0) ...[
                                  const SizedBox(width: 12),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'You Save',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: scheme.onSurfaceVariant,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'GHS ${savings.toStringAsFixed(2)}',
                                        style: const TextStyle(
                                          color: Color(0xFF33B457),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: cardBg,
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: borderColor),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.storefront_rounded,
                                      color: AppColors.primary,
                                      size: 24,
                                    ),
                                  ),
                                  const SizedBox(width: 14),
                                  Expanded(
                                    child: Text(
                                      product.partnerName.isNotEmpty
                                          ? 'Sold by ${product.partnerName} • Verified partner'
                                          : 'Official Retailer Partner • Tap to view all items',
                                      style: TextStyle(
                                        color: AppColors.primary,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Icon(
                                    Icons.chevron_right_rounded,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              _DetailTabPill(
                                label: 'Description',
                                selected: !_showSpecs,
                                onTap: () => setState(() => _showSpecs = false),
                              ),
                              const SizedBox(width: 12),
                              _DetailTabPill(
                                label: 'Specifications',
                                selected: _showSpecs,
                                onTap: () => setState(() => _showSpecs = true),
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(18),
                            decoration: BoxDecoration(
                              color: cardBg,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: borderColor),
                            ),
                            child: _showSpecs
                                ? Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _SpecRow(
                                        label: 'SKU',
                                        value: product.displaySku.toUpperCase(),
                                      ),
                                      if (product.brand.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        _SpecRow(
                                          label: 'Brand',
                                          value: product.brand,
                                        ),
                                      ],
                                      if (product.partnerName.isNotEmpty) ...[
                                        const SizedBox(height: 10),
                                        _SpecRow(
                                          label: 'Sold by',
                                          value: product.partnerName,
                                        ),
                                      ],
                                      const SizedBox(height: 10),
                                      _SpecRow(
                                        label: 'Rating',
                                        value:
                                            '${product.rating} (${Formatters.compact(product.sold)} sold)',
                                      ),
                                      const SizedBox(height: 10),
                                      _SpecRow(
                                        label: 'Availability',
                                        value: product.inStock
                                            ? '${product.stock} in stock'
                                            : 'Out of stock',
                                      ),
                                      if (product.weightKg != null) ...[
                                        const SizedBox(height: 10),
                                        _SpecRow(
                                          label: 'Weight',
                                          value:
                                              '${product.weightKg!.toStringAsFixed(2)} kg',
                                        ),
                                      ],
                                      for (final attr
                                          in product.attributes.entries) ...[
                                        const SizedBox(height: 10),
                                        _SpecRow(
                                          label: attr.key,
                                          value: attr.value,
                                        ),
                                      ],
                                    ],
                                  )
                                : Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        product.description.isEmpty
                                            ? 'Enjoy premium quality with fast Lidapay store delivery.'
                                            : product.description,
                                        maxLines: _expandedDescription
                                            ? null
                                            : 3,
                                        overflow: _expandedDescription
                                            ? TextOverflow.visible
                                            : TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                              color: scheme.onSurface
                                                  .withValues(alpha: 0.82),
                                              height: 1.55,
                                              fontSize: 15,
                                            ),
                                      ),
                                      const SizedBox(height: 12),
                                      GestureDetector(
                                        onTap: () => setState(
                                          () => _expandedDescription =
                                              !_expandedDescription,
                                        ),
                                        child: Text(
                                          _expandedDescription
                                              ? 'Show Less'
                                              : 'Read More',
                                          style: const TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                          ),
                          if (relatedProducts.isNotEmpty) ...[
                            const SizedBox(height: 26),
                            Text(
                              'You Might Also Like',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                            ),
                            const SizedBox(height: 14),
                            SizedBox(
                              height: 196,
                              child: ListView.separated(
                                scrollDirection: Axis.horizontal,
                                itemCount: relatedProducts.length,
                                separatorBuilder: (_, _) =>
                                    const SizedBox(width: 12),
                                itemBuilder: (context, index) {
                                  final item = relatedProducts[index];
                                  return _RelatedProductTile(
                                    product: item,
                                    cardBg: cardBg,
                                    borderColor: borderColor,
                                    onTap: () => _selectRelatedProduct(item),
                                  );
                                },
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              padding: EdgeInsets.fromLTRB(
                20,
                12,
                20,
                MediaQuery.paddingOf(context).bottom + 14,
              ),
              decoration: BoxDecoration(
                color: cardBg,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
                    blurRadius: 16,
                    offset: const Offset(0, -4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: isDark
                          ? AppColors.darkInput
                          : const Color(0xFFF3F3F6),
                      borderRadius: BorderRadius.circular(26),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: _quantity > 1 ? () => _step(-1) : null,
                          icon: const Icon(Icons.remove_rounded, size: 20),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: Text(
                            '$_quantity',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _quantity < product.stock
                              ? () => _step(1)
                              : null,
                          icon: const Icon(Icons.add_rounded, size: 20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: AppButton(
                      label: product.inStock ? 'Add to Cart' : 'Out of Stock',
                      icon: const Icon(
                        Icons.add_shopping_cart_rounded,
                        color: Colors.white,
                      ),
                      loading: adding,
                      onPressed: product.inStock && !adding ? _addToCart : null,
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

class _DetailHeroHeader extends StatelessWidget {
  const _DetailHeroHeader({
    required this.product,
    required this.surfaceBg,
    required this.favorited,
    required this.cartCount,
    required this.imagePager,
    required this.imagePage,
    required this.onImagePage,
    required this.onBack,
    required this.onToggleFavorite,
    required this.onOpenCart,
  });

  final ShopProduct product;
  final Color surfaceBg;
  final bool favorited;
  final int cartCount;
  final PageController imagePager;
  final int imagePage;
  final ValueChanged<int> onImagePage;
  final VoidCallback onBack;
  final VoidCallback onToggleFavorite;
  final VoidCallback onOpenCart;

  @override
  Widget build(BuildContext context) {
    // The gallery falls back to the primary art when the API only sent one.
    final gallery = product.images.isNotEmpty
        ? product.images
        : [product.imageAsset];

    return SizedBox(
      height: 350,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0.0, 0.72, 1.0],
                colors: [
                  const Color(0xFF33295E),
                  const Color(0xFF1B163E),
                  surfaceBg,
                ],
              ),
            ),
          ),
          // Halo disc — a soft white radial glow so transparent product art
          // blends into the gradient instead of floating on it.
          Center(
            child: Container(
              width: 264,
              height: 264,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    Colors.white.withValues(alpha: 0.30),
                    Colors.white.withValues(alpha: 0.12),
                    Colors.white.withValues(alpha: 0.0),
                  ],
                  stops: const [0.0, 0.6, 1.0],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 56, bottom: 26),
            child: PageView.builder(
              controller: imagePager,
              itemCount: gallery.length,
              onPageChanged: onImagePage,
              itemBuilder: (context, index) {
                final src = gallery[index];
                return Center(
                  child: Container(
                    width: 224,
                    height: 224,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(26),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.22),
                          blurRadius: 28,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: src.isEmpty
                        ? Icon(
                            Icons.shopping_bag_outlined,
                            size: 96,
                            color: AppColors.navy.withValues(alpha: 0.35),
                          )
                        : ProductImage(
                            source: src,
                            fit: BoxFit.contain,
                            memCacheWidth: 640,
                          ),
                  ),
                );
              },
            ),
          ),
          Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                width: 42,
                height: 4.5,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.45),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Positioned(
            top: 18,
            left: 16,
            right: 16,
            child: Row(
              children: [
                _CircleHeaderButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: onBack,
                ),
                const Spacer(),
                _CircleHeaderButton(
                  icon: favorited
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  iconColor: favorited ? AppColors.primary : Colors.black87,
                  onTap: onToggleFavorite,
                ),
                const SizedBox(width: 10),
                _CircleHeaderButton(
                  icon: Icons.shopping_cart_outlined,
                  badgeCount: cartCount,
                  onTap: onOpenCart,
                ),
              ],
            ),
          ),
          if (gallery.length > 1)
            Positioned(
              left: 0,
              right: 0,
              bottom: 12,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < gallery.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == imagePage ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == imagePage
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(3),
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

class _CircleHeaderButton extends StatelessWidget {
  const _CircleHeaderButton({
    required this.icon,
    required this.onTap,
    this.iconColor = Colors.black87,
    this.badgeCount = 0,
  });

  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;
  final int badgeCount;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.9),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Badge(
          isLabelVisible: badgeCount > 0,
          label: Text('$badgeCount'),
          child: Icon(icon, color: iconColor, size: 22),
        ),
      ),
    );
  }
}

class _DetailTabPill extends StatelessWidget {
  const _DetailTabPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primary
              : (isDark ? AppColors.darkInput : const Color(0xFFF1F1F4)),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w700,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}

class _SpecRow extends StatelessWidget {
  const _SpecRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RelatedProductTile extends StatelessWidget {
  const _RelatedProductTile({
    required this.product,
    required this.cardBg,
    required this.borderColor,
    required this.onTap,
  });

  final ShopProduct product;
  final Color cardBg;
  final Color borderColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final discount = product.discountPercent;
    return Material(
      color: cardBg,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 156,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Container(
                      color: scheme.surfaceContainerHighest.withValues(
                        alpha: 0.35,
                      ),
                      padding: const EdgeInsets.all(12),
                      child: ProductImage(
                        source: product.imageAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                    if (discount > 0)
                      Positioned(
                        top: 8,
                        left: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFE8432E),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '-$discount%',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(11, 9, 11, 11),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface.withValues(alpha: 0.88),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'GHS ${product.price.toStringAsFixed(2)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w800,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
