import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/network/connectivity_service.dart';

class FakeConnectivity implements Connectivity {
  final _controller = StreamController<List<ConnectivityResult>>.broadcast();
  List<ConnectivityResult> current = [ConnectivityResult.wifi];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged => _controller.stream;

  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => current;

  void emit(List<ConnectivityResult> results) {
    current = results;
    _controller.add(results);
  }

  void dispose() {
    _controller.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ConnectivityService', () {
    late FakeConnectivity fakeConnectivity;
    late ConnectivityService service;

    setUp(() {
      fakeConnectivity = FakeConnectivity();
      service = ConnectivityService(fakeConnectivity);
    });

    tearDown(() {
      service.dispose();
      fakeConnectivity.dispose();
    });

    test('initial state defaults to online and updates from checkConnectivity', () async {
      expect(service.isOnline, isTrue);
      await pumpEventQueue();
      expect(service.isOnline, isTrue);
    });

    test('transitions to offline when connectivity drops to none', () async {
      final events = <bool>[];
      final sub = service.onConnectivityChanged.listen(events.add);

      fakeConnectivity.emit([ConnectivityResult.none]);
      await pumpEventQueue();

      expect(service.isOnline, isFalse);
      expect(events, [false]);

      // Going back online
      fakeConnectivity.emit([ConnectivityResult.mobile]);
      await pumpEventQueue();

      expect(service.isOnline, isTrue);
      expect(events, [false, true]);

      // Emitting same state does not fire redundant duplicate event
      fakeConnectivity.emit([ConnectivityResult.wifi]);
      await pumpEventQueue();

      expect(events, [false, true]); // Still 2 events

      await sub.cancel();
    });
  });
}
