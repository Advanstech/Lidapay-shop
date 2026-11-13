import 'package:flutter/material.dart';

import '../../../../core/widgets/feedback_views.dart';

/// Placeholder for tabs that come online in later milestones.
class FeaturePlaceholder extends StatelessWidget {
  const FeaturePlaceholder({
    super.key,
    required this.title,
    required this.message,
    this.icon = Icons.construction_outlined,
  });

  final String title;
  final String message;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: EmptyView(title: 'Coming soon', subtitle: message, icon: icon),
    );
  }
}
