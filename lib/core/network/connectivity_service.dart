import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final connectivityServiceProvider = Provider<ConnectivityService>((ref) {
  final service = ConnectivityService();
  ref.onDispose(service.dispose);
  return service;
});

final isOnlineProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(connectivityServiceProvider);
  return service.onConnectivityChanged;
});

class ConnectivityService {
  ConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity() {
    _subscription = _connectivity.onConnectivityChanged.listen(_handleResults);
    // Initial check
    _connectivity.checkConnectivity().then(_handleResults).catchError((_) {});
  }

  final Connectivity _connectivity;
  StreamSubscription<List<ConnectivityResult>>? _subscription;
  final _controller = StreamController<bool>.broadcast();

  bool _isOnline = true;
  bool get isOnline => _isOnline;

  Stream<bool> get onConnectivityChanged => _controller.stream;

  void _handleResults(List<ConnectivityResult> results) {
    final online = results.any((r) => r != ConnectivityResult.none);
    if (_isOnline != online) {
      _isOnline = online;
      _controller.add(online);
    }
  }

  void dispose() {
    _subscription?.cancel();
    _controller.close();
  }
}
