import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

/// flagcdn.com serves CORS-friendly PNGs derived from the ISO-2 code — the
/// reliable cross-platform flag source (Reloadly's S3/CDN flag URLs often ship
/// as SVGs or lack CORS headers on web, matching Lidapay-old's CountryFlagWidget).
String countryFlagImageUrl(String isoCode, {String? flagUrl}) {
  final code = isoCode.trim().toLowerCase();
  if (code.length >= 2) {
    return 'https://flagcdn.com/w80/${code.substring(0, 2)}.png';
  }
  final api = flagUrl?.trim();
  if (api != null && api.isNotEmpty && !api.toLowerCase().endsWith('.svg')) {
    return api;
  }
  return 'https://flagcdn.com/w80/gh.png';
}

/// Renders the country flag image with a text ISO badge as the error
/// fallback — flag emojis are unreliable (and some literals shipped
/// corrupted in source, rendering as tofu boxes on web).
class CountryFlagBadge extends StatelessWidget {
  const CountryFlagBadge({
    required this.isoCode,
    this.flagUrl,
    this.size = 26,
    super.key,
  });

  final String isoCode;
  final String? flagUrl;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final url = countryFlagImageUrl(isoCode, flagUrl: flagUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(size * 0.22),
      child: CachedNetworkImage(
        // Keyed by URL so a recycled row never keeps a stale flag image
        // when the country list re-filters.
        key: ValueKey(url),
        imageUrl: url,
        width: size,
        height: size * 0.75,
        fit: BoxFit.cover,
        memCacheWidth: (size * 4).toInt(),
        memCacheHeight: (size * 3).toInt(),
        placeholder: (_, _) => Container(
          width: size,
          height: size * 0.75,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(size * 0.22),
          ),
        ),
        errorWidget: (_, _, _) => Container(
          width: size,
          height: size * 0.75,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(size * 0.22),
          ),
          child: Text(
            isoCode,
            style: TextStyle(
              fontSize: size * 0.42,
              fontWeight: FontWeight.w800,
              color: scheme.primary,
              letterSpacing: 0.5,
            ),
          ),
        ),
      ),
    );
  }
}

/// Mobile-network logo (MTN, Airtel…) shown as a badge. Loads the API
/// [logoUrl] when available and falls back to a branded carrier badge when no
/// logo exists or it fails to load (e.g. CORS on web), so the slot is never
/// empty or reduced to a generic icon.
class OperatorLogoBadge extends StatelessWidget {
  const OperatorLogoBadge({
    required this.name,
    this.logoUrl,
    this.size = 28,
    super.key,
  });

  final String name;
  final String? logoUrl;
  final double size;

  static ({Color bg, Color fg, String tag}) _brand(String name) {
    final upper = name.toUpperCase();
    if (upper.contains('MTN')) {
      return (
        bg: const Color(0xFFFFCC00),
        fg: const Color(0xFF1F1A00),
        tag: 'MTN',
      );
    }
    if (upper.contains('TELECEL') || upper.contains('VODAFONE')) {
      return (bg: const Color(0xFFE60000), fg: Colors.white, tag: 'TC');
    }
    if (upper.contains('AIRTEL') || upper.contains('TIGO')) {
      return (bg: const Color(0xFFE40000), fg: Colors.white, tag: 'AT');
    }
    if (upper.contains('GLO')) {
      return (bg: const Color(0xFF1F9D55), fg: Colors.white, tag: 'GLO');
    }
    if (upper.contains('9MOBILE') || upper.contains('ETISALAT')) {
      return (bg: const Color(0xFF006E51), fg: Colors.white, tag: '9M');
    }
    if (upper.contains('ORANGE')) {
      return (bg: const Color(0xFFFF7900), fg: Colors.white, tag: 'OR');
    }
    if (upper.contains('SAFARICOM')) {
      return (bg: const Color(0xFF2E9E4F), fg: Colors.white, tag: 'SF');
    }
    final words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final tag = words.isEmpty
        ? 'SIM'
        : words.length == 1
        ? words.first.substring(0, words.first.length.clamp(1, 3)).toUpperCase()
        : '${words[0][0]}${words[1][0]}'.toUpperCase();
    return (bg: AppColors.primary, fg: Colors.white, tag: tag);
  }

  @override
  Widget build(BuildContext context) {
    final brand = _brand(name);
    final radius = BorderRadius.circular(size * 0.28);
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: brand.bg,
        borderRadius: radius,
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 3),
          child: Text(
            brand.tag,
            style: TextStyle(
              fontSize: size * 0.36,
              fontWeight: FontWeight.w900,
              color: brand.fg,
            ),
          ),
        ),
      ),
    );
    final url = logoUrl?.trim();
    if (url == null || url.isEmpty || url.toLowerCase().endsWith('.svg')) {
      return fallback;
    }
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        key: ValueKey(url),
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
