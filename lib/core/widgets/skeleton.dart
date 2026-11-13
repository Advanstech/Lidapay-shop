import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

/// Skeleton block used by every API-bound list/detail screen while loading.
class AppSkeleton extends StatelessWidget {
  const AppSkeleton({
    super.key,
    this.width,
    this.height = 16,
    this.borderRadius = 8,
  });

  final double? width;
  final double height;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final base = isDark ? Colors.white12 : const Color(0xFFE9E9F1);
    final highlight = isDark ? Colors.white24 : const Color(0xFFF6F6FA);
    return Shimmer.fromColors(
      baseColor: base,
      highlightColor: highlight,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: base,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }
}

/// Full-screen placeholder used by screens while their first load is in flight.
class AppSkeletonScreen extends StatelessWidget {
  const AppSkeletonScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(20),
      children: const [
        AppSkeleton(height: 180, borderRadius: 24),
        SizedBox(height: 24),
        Row(
          children: [
            Expanded(child: AppSkeleton(height: 84, borderRadius: 16)),
            SizedBox(width: 12),
            Expanded(child: AppSkeleton(height: 84, borderRadius: 16)),
            SizedBox(width: 12),
            Expanded(child: AppSkeleton(height: 84, borderRadius: 16)),
          ],
        ),
        SizedBox(height: 24),
        AppSkeleton(height: 140, borderRadius: 20),
        SizedBox(height: 24),
        AppSkeleton(height: 72),
        SizedBox(height: 12),
        AppSkeleton(height: 72),
        SizedBox(height: 12),
        AppSkeleton(height: 72),
      ],
    );
  }
}
