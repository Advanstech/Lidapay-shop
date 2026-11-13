import 'package:flutter/material.dart';

/// Fixed-height `SliverPersistentHeaderDelegate` that pins a top bar or
/// filter strip to the top of a `CustomScrollView` and adds a subtle shadow
/// once content scrolls underneath it (`shrinkOffset > 0`).
class StickySliverHeaderDelegate extends SliverPersistentHeaderDelegate {
  StickySliverHeaderDelegate({required this.height, required this.builder});

  final double height;
  final Widget Function(BuildContext context, bool isStuck) builder;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isStuck = shrinkOffset > 0 || overlapsContent;
    return SizedBox.expand(child: builder(context, isStuck));
  }

  @override
  bool shouldRebuild(covariant StickySliverHeaderDelegate oldDelegate) {
    return true;
  }
}
