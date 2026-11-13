import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/location/location_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';

/// Result of the delivery-pin picker: the customer-confirmed drop-off
/// coordinates sent as `shippingAddress.latitude/longitude` at checkout.
typedef DeliveryPin = ({double latitude, double longitude});

/// Full-screen map picker for the customer's delivery destination.
///
/// The backend requires both coordinates at checkout and uses them with the
/// fulfillment branch pickup pin to compute the courier distance, so the pin
/// is mandatory. When no Google Maps key is configured (or on web) the screen
/// falls back to "use my location" plus manual coordinate entry so checkout
/// still works.
///
/// Returns the confirmed [DeliveryPin], or null when dismissed.
Future<DeliveryPin?> showDeliveryPinPicker({
  required BuildContext context,
  double? initialLatitude,
  double? initialLongitude,
}) {
  return Navigator.of(context).push<DeliveryPin>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => DeliveryPinPickerScreen(
        initialLatitude: initialLatitude,
        initialLongitude: initialLongitude,
      ),
    ),
  );
}

class DeliveryPinPickerScreen extends ConsumerStatefulWidget {
  const DeliveryPinPickerScreen({
    super.key,
    this.initialLatitude,
    this.initialLongitude,
  });

  final double? initialLatitude;
  final double? initialLongitude;

  @override
  ConsumerState<DeliveryPinPickerScreen> createState() =>
      _DeliveryPinPickerScreenState();
}

class _DeliveryPinPickerScreenState
    extends ConsumerState<DeliveryPinPickerScreen> {
  GoogleMapController? _controller;
  LatLng? _pin;
  bool _locating = false;

  final _latController = TextEditingController();
  final _lngController = TextEditingController();

  bool get _mapsReady => AppConstants.googleMapsConfigured && !kIsWeb;

  @override
  void initState() {
    super.initState();
    final lat = widget.initialLatitude;
    final lng = widget.initialLongitude;
    if (lat != null && lng != null) {
      _pin = LatLng(lat, lng);
      _latController.text = lat.toStringAsFixed(6);
      _lngController.text = lng.toStringAsFixed(6);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _latController.dispose();
    _lngController.dispose();
    super.dispose();
  }

  LatLng get _fallbackCenter => LatLng(
    UserGeoLocation.fallback.latitude,
    UserGeoLocation.fallback.longitude,
  );

  LatLng get _center => _pin ?? _fallbackCenter;

  void _dropPin(LatLng point) {
    setState(() {
      _pin = point;
      _latController.text = point.latitude.toStringAsFixed(6);
      _lngController.text = point.longitude.toStringAsFixed(6);
    });
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    final geo = await ref
        .read(locationServiceProvider)
        .getCurrentLocation(promptPermission: true);
    if (!mounted) return;
    setState(() => _locating = false);
    if (geo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Location unavailable — drop the pin manually or enter coordinates.',
          ),
        ),
      );
      return;
    }
    final point = LatLng(geo.latitude, geo.longitude);
    _dropPin(point);
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(point, 16));
  }

  void _confirm() {
    final pin = _pin;
    if (pin == null) return;
    Navigator.of(
      context,
    ).pop((latitude: pin.latitude, longitude: pin.longitude));
  }

  void _applyManualCoords() {
    final lat = double.tryParse(_latController.text.trim());
    final lng = double.tryParse(_lngController.text.trim());
    if (lat == null || lng == null) return;
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return;
    _dropPin(LatLng(lat, lng));
    _controller?.animateCamera(CameraUpdate.newLatLngZoom(LatLng(lat, lng), 16));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? AppColors.darkScaffold : AppColors.lightScaffold,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Delivery Pin'),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(child: _mapsReady ? _map(scheme) : _fallback(scheme)),
            _bottomBar(scheme),
          ],
        ),
      ),
    );
  }

  Widget _map(ColorScheme scheme) {
    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _center, zoom: 15),
          onMapCreated: (controller) {
            _controller = controller;
            if (_pin != null) {
              controller.animateCamera(
                CameraUpdate.newLatLngZoom(_pin!, 16),
              );
            }
          },
          onTap: _dropPin,
          markers: {
            if (_pin != null)
              Marker(
                markerId: const MarkerId('delivery'),
                position: _pin!,
                icon: BitmapDescriptor.defaultMarkerWithHue(
                  BitmapDescriptor.hueRed,
                ),
                infoWindow: const InfoWindow(title: 'Delivery destination'),
              ),
          },
          myLocationButtonEnabled: false,
          myLocationEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          compassEnabled: true,
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 16,
          child: _hintCard(scheme),
        ),
      ],
    );
  }

  Widget _hintCard(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(Icons.touch_app_rounded, size: 18, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _pin == null
                  ? 'Tap the map to drop the delivery pin'
                  : 'Pin set — tap again to move it',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _fallback(ColorScheme scheme) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.map_outlined, size: 28, color: scheme.onSurfaceVariant),
              const SizedBox(height: 10),
              Text(
                'Map view unavailable',
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'The delivery pin is required for courier distance. Use your '
                'current location or enter the coordinates manually.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        AppTextField(
          controller: _latController,
          label: 'Latitude',
          hint: '5.603700',
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onFieldSubmitted: (_) => _applyManualCoords(),
        ),
        const SizedBox(height: 14),
        AppTextField(
          controller: _lngController,
          label: 'Longitude',
          hint: '-0.187000',
          keyboardType: const TextInputType.numberWithOptions(
            decimal: true,
            signed: true,
          ),
          onFieldSubmitted: (_) => _applyManualCoords(),
        ),
        const SizedBox(height: 14),
        TextButton.icon(
          onPressed: _applyManualCoords,
          icon: const Icon(Icons.place_outlined, size: 18),
          label: const Text('Use these coordinates'),
        ),
        if (_pin != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Pin set: ${_pin!.latitude.toStringAsFixed(5)}, '
              '${_pin!.longitude.toStringAsFixed(5)}',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: AppColors.success,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  Widget _bottomBar(ColorScheme scheme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4)),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pin != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.location_on_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 6),
                  Text(
                    '${_pin!.latitude.toStringAsFixed(5)}, '
                    '${_pin!.longitude.toStringAsFixed(5)}',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _locating ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.my_location_rounded, size: 18),
                  label: const Text('My location'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: AppButton(
                  label: 'Confirm pin',
                  onPressed: _pin == null ? null : _confirm,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
