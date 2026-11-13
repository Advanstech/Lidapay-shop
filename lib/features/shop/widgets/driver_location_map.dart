import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/app_theme.dart';
import '../data/shop_models.dart';

/// Live courier driver pin for the order tracking card.
///
/// Renders a Google Map centered on `lastDriverLocation` while the order is
/// in transit. When no Maps key is configured (or on web, where the native
/// plugin isn't wired) it degrades to a coordinates card so the tracking
/// screen still shows the freshest fix the partner has sent.
class DriverLocationMap extends StatefulWidget {
  const DriverLocationMap({super.key, required this.location});

  final DriverLocation location;

  @override
  State<DriverLocationMap> createState() => _DriverLocationMapState();
}

class _DriverLocationMapState extends State<DriverLocationMap> {
  GoogleMapController? _controller;
  LatLng? _shownAt;

  LatLng get _target =>
      LatLng(widget.location.latitude, widget.location.longitude);

  @override
  void initState() {
    super.initState();
    _shownAt = _target;
  }

  @override
  void didUpdateWidget(DriverLocationMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _target;
    final moved = _shownAt == null ||
        (_shownAt!.latitude - next.latitude).abs() > 0.00001 ||
        (_shownAt!.longitude - next.longitude).abs() > 0.00001;
    if (!moved) return;
    _shownAt = next;
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(next, 15));
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final loc = widget.location;
    final freshness = loc.freshnessLabel();

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 180,
            width: double.infinity,
            child: _mapBody(scheme),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Row(
              children: [
                Icon(
                  Icons.local_shipping_outlined,
                  size: 15,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Driver is en route',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                if (freshness.isNotEmpty)
                  Text(
                    freshness,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapBody(ColorScheme scheme) {
    final target = _target;
    if (!AppConstants.googleMapsConfigured || kIsWeb) {
      return _coordsFallback(scheme, target);
    }
    return GoogleMap(
      initialCameraPosition: CameraPosition(target: target, zoom: 15),
      markers: {
        Marker(
          markerId: const MarkerId('driver'),
          position: target,
          icon: BitmapDescriptor.defaultMarkerWithHue(
            BitmapDescriptor.hueAzure,
          ),
          infoWindow: const InfoWindow(title: 'Courier driver'),
        ),
      },
      myLocationButtonEnabled: false,
      myLocationEnabled: false,
      zoomControlsEnabled: false,
      mapToolbarEnabled: false,
      compassEnabled: false,
      onMapCreated: (controller) => _controller = controller,
    );
  }

  Widget _coordsFallback(ColorScheme scheme, LatLng target) {
    return Container(
      color: scheme.surface,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.map_outlined, size: 28, color: scheme.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            '${target.latitude.toStringAsFixed(5)}, '
            '${target.longitude.toStringAsFixed(5)}',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Live driver position',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
