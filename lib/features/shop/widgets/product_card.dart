import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/product_image.dart';
import '../data/shop_models.dart';
import '../providers.dart';

/// Catalog deal/product card matching the Lidapay shop design:
/// white image well, top-left red discount pill, top-right wishlist heart,
/// and magenta bottom band with product title and price.
class ProductCard extends ConsumerStatefulWidget {
  const ProductCard({super.key, required this.product, this.onTap});

  final ShopProduct product;
  final VoidCallback? onTap;

  @override
  ConsumerState<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends ConsumerState<ProductCard> {
  bool _pressed = false;

  /// Same selection the detail sheet writes — the heart on the card and the
  /// heart on the sheet are one stored value, never two local flags.
  Future<void> _toggleLoved() async {
    HapticFeedback.selectionClick();
    await ref.read(lovedProductsProvider.notifier).toggle(widget.product.id);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final product = widget.product;
    final discount = product.discountPercent;
    final loved = ref.watch(lovedProductsProvider).contains(product.id);

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 140),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : const Color(0xFFE6DFE5),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.22 : 0.04),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: ProductImage(
                        source: product.imageAsset,
                        fit: BoxFit.contain,
                      ),
                    ),
                    if (discount > 0)
                      Positioned(
                        top: 10,
                        left: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF03E2F),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '$discount% OFF',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: _toggleLoved,
                        child: Padding(
                          padding: const EdgeInsets.all(4),
                          child: Icon(
                            loved
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            size: 20,
                            color: loved
                                ? AppColors.primary
                                : scheme.onSurface.withValues(alpha: 0.75),
                          ),
                        ),
                      ),
                    ),
                    if (!product.inStock)
                      Positioned.fill(
                        child: ColoredBox(
                          color: scheme.scrim.withValues(alpha: 0.6),
                          child: const Center(
                            child: Text(
                              'Out of stock',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                decoration: const BoxDecoration(
                  gradient: AppColors.heroGradient,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'GHS ${product.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                          if (product.oldPrice != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              Formatters.currency(product.oldPrice!),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: Colors.white.withValues(alpha: 0.78),
                                decoration: TextDecoration.lineThrough,
                                decorationColor: Colors.white70,
                              ),
                            ),
                          ],
                        ],
                      ),
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
