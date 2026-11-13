import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/location/location_service.dart';

void main() {
  group('UserGeoLocation', () {
    test('UserGeoLocation fallback has standard Ghana Accra coordinates and details', () {
      const fallback = UserGeoLocation.fallback;
      expect(fallback.country, 'Ghana');
      expect(fallback.countryIsoCode, 'GH');
      expect(fallback.city, 'Accra');
      expect(fallback.latitude, 5.6037);
      expect(fallback.longitude, -0.1870);
    });

    test('UserGeoLocation fields construct properly', () {
      const custom = UserGeoLocation(
        latitude: 6.6885,
        longitude: -1.6244,
        country: 'Ghana',
        countryIsoCode: 'GH',
        city: 'Kumasi',
        region: 'Ashanti',
        addressLine: 'Adum, Kumasi',
      );
      expect(custom.city, 'Kumasi');
      expect(custom.region, 'Ashanti');
      expect(custom.addressLine, 'Adum, Kumasi');
    });
  });
}
