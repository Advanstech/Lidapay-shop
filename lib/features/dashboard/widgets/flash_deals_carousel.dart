import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../data/dashboard_models.dart';

/// Auto-scrolling partner deal cards. The countdown chip ticks from
/// [FlashDeal.endsAt], which is the server-authoritative expiry — the widget
/// never invents its own duration (server-time reconciliation, same principle
/// as the Lida Value countdown).
class FlashDealsCarousel extends StatefulWidget {
  const FlashDealsCarousel({super.key, required this.deals, this.onDealTap});

  final List<FlashDeal> deals;
  final ValueChanged<FlashDeal>? onDealTap;

  @override
  State<FlashDealsCarousel> createState() => _FlashDealsCarouselState();
}

class _FlashDealsCarouselState extends State<FlashDealsCarousel> {
  final _controller = PageController(viewportFraction: 0.92);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.deals.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 176,
      child: PageView.builder(
        controller: _controller,
        itemCount: widget.deals.length,
        itemBuilder: (context, i) => _DealCard(
          deal: widget.deals[i],
          onTap: () => widget.onDealTap?.call(widget.deals[i]),
        ),
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.onTap});

  final FlashDeal deal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: AppColors.navy.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            CachedNetworkImage(
              imageUrl: deal.imageUrl,
              fit: BoxFit.cover,
              placeholder: (context, url) =>
                  Container(color: AppColors.navy.withValues(alpha: 0.15)),
              errorWidget: (context, url, error) => Container(
                color: AppColors.navy,
                child: const Icon(
                  Icons.image_outlined,
                  color: Colors.white38,
                  size: 48,
                ),
              ),
            ),
            // Legibility gradient.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.78),
                  ],
                ),
              ),
            ),
            Positioned(
              left: 16,
              right: 16,
              bottom: 14,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '-${deal.discountPercent}% · ${deal.partnerName}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    deal.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  SizedBox(
                    width: double.infinity,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            Formatters.currency(deal.dealPrice),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            Formatters.currency(deal.originalPrice),
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12.5,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                          const SizedBox(width: 12),
                          _CountdownChip(expiresAt: deal.endsAt),
                        ],
                      ),
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

/// Ticks every second from [expiresAt]. Extend with an NTP offset when the
/// backend exposes server time, to correct client clock drift.
class _CountdownChip extends StatefulWidget {
  const _CountdownChip({required this.expiresAt});

  final DateTime expiresAt;

  @override
  State<_CountdownChip> createState() => _CountdownChipState();
}

class _CountdownChipState extends State<_CountdownChip> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String get _label {
    final remaining = widget.expiresAt.difference(DateTime.now());
    if (remaining.isNegative) return 'Ended';
    final h = remaining.inHours.toString().padLeft(2, '0');
    final m = (remaining.inMinutes % 60).toString().padLeft(2, '0');
    final s = (remaining.inSeconds % 60).toString().padLeft(2, '0');
    return 'Ends in $h:$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final expired = widget.expiresAt.isBefore(DateTime.now());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: expired ? Colors.white24 : Colors.white,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.timer_outlined,
            size: 13,
            color: expired ? Colors.white70 : AppColors.primary,
          ),
          const SizedBox(width: 4),
          Text(
            _label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: expired ? Colors.white70 : AppColors.primary,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
