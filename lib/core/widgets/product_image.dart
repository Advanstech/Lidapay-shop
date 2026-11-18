import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Product artwork from either the bundled catalog or a live API URL. Remote
/// images can 404 or still be uploading, so a failed load keeps the layout
/// intact with a tinted placeholder instead of a red error box.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.source,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth,
  });

  final String source;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Downscales remote art to the displayed size so carousel/grid images do
  /// not decode at camera resolution.
  final int? memCacheWidth;

  static String _cleanSource(String raw) {
    var trimmed = raw.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      trimmed = trimmed.substring(1, trimmed.length - 1).trim();
    }
    if (trimmed.contains(',')) {
      final first = trimmed.split(',').first.trim();
      if (first.contains('http://') || first.contains('https://')) {
        trimmed = first;
      }
    }
    trimmed = trimmed.replaceAll(RegExp('^[\'"\\[]+|[\'"\\]]+\$'), '').trim();
    return trimmed;
  }

  /// Catalog art is always served over TLS — a plaintext URL would be
  /// blocked on Android and leaks the customer's browsing.
  static String _secureUrl(String url) =>
      url.startsWith('http://') ? 'https://${url.substring(7)}' : url;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final clean = _cleanSource(source);
    final isRemote =
        clean.startsWith('http://') || clean.startsWith('https://');
    final placeholder = _placeholder(scheme);

    final image = isRemote
        ? CachedNetworkImage(
            // The disk cache keeps the catalog readable on a slow or lost
            // connection — the storefront opens instantly offline.
            imageUrl: _secureUrl(clean),
            width: width,
            height: height,
            fit: fit,
            memCacheWidth: memCacheWidth,
            fadeInDuration: const Duration(milliseconds: 180),
            placeholder: (_, _) => placeholder,
            errorWidget: (_, _, _) => placeholder,
          )
        : Image.asset(
            clean,
            width: width,
            height: height,
            fit: fit,
            cacheWidth: memCacheWidth,
            errorBuilder: (_, _, _) => placeholder,
          );
    return clean.isEmpty ? placeholder : image;
  }

  Widget _placeholder(ColorScheme scheme) => Container(
    width: width,
    height: height,
    color: scheme.surface,
    alignment: Alignment.center,
    child: Icon(
      Icons.shopping_bag_outlined,
      size: 40,
      color: scheme.onSurfaceVariant.withValues(alpha: 0.45),
    ),
  );
}
