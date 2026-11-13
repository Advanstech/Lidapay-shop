import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

@immutable
class UserGeoLocation {
  const UserGeoLocation({
    required this.latitude,
    required this.longitude,
    this.country,
    this.countryIsoCode,
    this.city,
    this.region,
    this.addressLine,
  });

  final double latitude;
  final double longitude;
  final String? country;
  final String? countryIsoCode;
  final String? city;
  final String? region;
  final String? addressLine;

  static const fallback = UserGeoLocation(
    latitude: 5.6037,
    longitude: -0.1870,
    country: 'Ghana',
    countryIsoCode: 'GH',
    city: 'Accra',
    region: 'Greater Accra',
    addressLine: 'Accra, Ghana',
  );
}

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

class LocationService {
  /// Requests location with best-effort reverse geocoding.
  /// Never throws: returns null if permission is denied, GPS is disabled, or offline.
  Future<UserGeoLocation?> getCurrentLocation({bool promptPermission = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return null;

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && promptPermission) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 10),
        ),
      );

      String? country;
      String? countryIsoCode;
      String? city;
      String? region;
      String? addressLine;

      try {
        final placemarks = await Geocoding().placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );
        if (placemarks.isNotEmpty) {
          final place = placemarks.first;
          country = place.country;
          countryIsoCode = place.isoCountryCode?.toUpperCase();
          city = place.locality?.isNotEmpty == true
              ? place.locality
              : place.subAdministrativeArea;
          region = place.administrativeArea;
          final streetParts = [
            place.street,
            place.subLocality,
          ].where((s) => s != null && s.trim().isNotEmpty).toList();
          addressLine = streetParts.isNotEmpty ? streetParts.join(', ') : city;
        }
      } catch (e) {
        debugPrint('Reverse geocoding error (non-fatal): $e');
      }

      return UserGeoLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        country: country,
        countryIsoCode: countryIsoCode,
        city: city,
        region: region,
        addressLine: addressLine,
      );
    } catch (e) {
      debugPrint('Location lookup failed (non-fatal): $e');
      return null;
    }
  }
}
