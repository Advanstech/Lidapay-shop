import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../theme/app_theme.dart';
import '../../widgets/brand_mark.dart';
import '../app_update_models.dart';
import '../providers.dart';

/// Watches the update policy and puts the right prompt on screen:
///
/// * below the backend's minimum supported build — a full-screen, blocking
///   cover that cannot be dismissed;
/// * newer build available — a compact card above the floating dock;
/// * flexible download finished — a "restart to finish" card.
///
/// Mounted through `MaterialApp.builder`, so it sits above every route
/// (including splash and auth) without depending on the router. It renders
/// inline instead of pushing a dialog, which keeps it working from that
/// position and makes it trivially testable.
class AppUpdateGate extends ConsumerStatefulWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends ConsumerState<AppUpdateGate>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Post-frame rather than a delayed timer: no pending timers to leak into
    // tests, and the check still lands after the first real frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(appUpdateControllerProvider.notifier).check());
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Throttled inside the controller (once per few hours).
      unawaited(ref.read(appUpdateControllerProvider.notifier).check());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appUpdateControllerProvider);

    return Stack(
      children: [
        widget.child,
        if (state.isBlocking)
          Positioned.fill(child: _BlockingCover(state: state)),
        if (!state.isBlocking &&
            (state.urgency == UpdateUrgency.optional || state.readyToInstall))
          Positioned(
            left: 16,
            right: 16,
            bottom: 104 + MediaQuery.paddingOf(context).bottom,
            child: Align(
              alignment: Alignment.bottomCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: _UpdateCard(state: state),
              ),
            ),
          ),
      ],
    );
  }
}

/// Non-dismissible cover for builds below the supported minimum.
class _BlockingCover extends StatelessWidget {
  const _BlockingCover({required this.state});

  final AppUpdateState state;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scrim = isDark ? AppColors.darkScaffold : AppColors.lightScaffold;

    return PopScope(
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: scrim.withValues(alpha: 0.98)),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: _UpdateCard(state: state, blocking: true),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The prompt itself. One card serves the blocking cover and the compact
/// bottom notice so copy, status and actions stay identical everywhere.
class _UpdateCard extends ConsumerWidget {
  const _UpdateCard({required this.state, this.blocking = false});

  final AppUpdateState state;
  final bool blocking;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(appUpdateControllerProvider.notifier);
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    final policy = state.policy;

    final ready = state.readyToInstall;
    final downloading = state.downloading && !ready;

    final title = ready
        ? 'Update ready to install'
        : state.playUnavailable
        ? 'Update in the Play Store'
        : blocking
        ? 'Update required'
        : 'Update available';

    final body = ready
        ? 'Restart Lidapay to finish installing the new version.'
        : state.playUnavailable
        ? 'Finish installing the update from the Play Store, then reopen '
              'Lidapay.'
        : policy.message?.trim().isNotEmpty == true
        ? policy.message!.trim()
        : blocking
        ? 'This version of Lidapay is no longer supported. Update now to keep '
              'sending money, topping up and shopping safely.'
        : 'A newer version of Lidapay is ready with the latest fixes and '
              'features.';

    final primaryLabel = ready
        ? 'Restart now'
        : state.playUnavailable
        ? 'Open Play Store'
        : 'Update now';

    final card = Material(
      color: isDark ? AppColors.darkSurface : Colors.white,
      elevation: blocking ? 0 : 12,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(AppRadii.card),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          blocking ? 24 : 18,
          blocking ? 28 : 16,
          blocking ? 24 : 18,
          blocking ? 24 : 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (blocking) ...[
                  const BrandMark(size: 44),
                  const SizedBox(width: 14),
                ] else ...[
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.system_update_rounded,
                      size: 19,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: blocking ? 20 : 14.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        body,
                        style: TextStyle(
                          fontSize: blocking ? 13.5 : 12.5,
                          height: 1.45,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (!blocking)
                  IconButton(
                    tooltip: 'Later',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.close_rounded, size: 18),
                    onPressed: downloading || ready
                        ? controller.dismissReady
                        : controller.remindLater,
                  ),
              ],
            ),
            if (downloading) ...[
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: scheme.primary.withValues(alpha: 0.12),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Downloading update… you can keep using Lidapay.',
                style: TextStyle(
                  fontSize: 11.5,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ] else ...[
              SizedBox(height: blocking ? 22 : 12),
              Row(
                children: [
                  if (blocking)
                    Expanded(
                      child: _PrimaryAction(
                        label: primaryLabel,
                        loading: state.starting,
                        onPressed: ready
                            ? controller.restartToInstall
                            : state.playUnavailable
                            ? controller.openStoreListing
                            : controller.startUpdate,
                      ),
                    )
                  else ...[
                    TextButton(
                      onPressed: ready
                          ? controller.dismissReady
                          : controller.remindLater,
                      child: const Text('Later'),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _PrimaryAction(
                        label: primaryLabel,
                        loading: state.starting,
                        compact: true,
                        onPressed: ready
                            ? controller.restartToInstall
                            : state.playUnavailable
                            ? controller.openStoreListing
                            : controller.startUpdate,
                      ),
                    ),
                  ],
                ],
              ),
              if (blocking && !ready) ...[
                const SizedBox(height: 10),
                Text(
                  'Takes less than a minute. Your wallet and orders stay safe.',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );

    return Semantics(liveRegion: true, container: true, child: card);
  }
}

class _PrimaryAction extends StatelessWidget {
  const _PrimaryAction({
    required this.label,
    required this.onPressed,
    this.loading = false,
    this.compact = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool loading;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final child = loading
        ? const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          )
        : Text(
            label,
            style: TextStyle(
              fontSize: compact ? 12.5 : 14,
              fontWeight: FontWeight.w700,
              color: Colors.white,
            ),
          );

    return SizedBox(
      height: compact ? 40 : 50,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(compact ? 14 : AppRadii.button),
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(compact ? 14 : AppRadii.button),
            onTap: loading ? null : onPressed,
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}
