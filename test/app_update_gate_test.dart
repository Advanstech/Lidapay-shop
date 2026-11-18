import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_update/in_app_update.dart' show InstallStatus;
import 'package:lidapay_app/core/device/device_identity.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/core/update/app_update_models.dart';
import 'package:lidapay_app/core/update/app_update_repository.dart';
import 'package:lidapay_app/core/update/play_update_service.dart';
import 'package:lidapay_app/core/update/providers.dart';
import 'package:lidapay_app/core/update/widgets/app_update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _identity = DeviceIdentity(
  deviceId: 'test-device',
  platform: 'ANDROID',
  appVersion: '1.1.2',
  buildNumber: '33',
  locale: 'en_GH',
  model: 'Pixel',
  osVersion: 'Android 15 (SDK 35)',
  manufacturer: 'google',
);

class _FakeUpdateRepository implements AppUpdateRepository {
  _FakeUpdateRepository(this.policy);

  AppVersionPolicy policy;
  int calls = 0;

  @override
  Future<AppVersionPolicy> fetchPolicy({
    required String platform,
    required String appVersion,
    required int buildNumber,
  }) async {
    calls++;
    return policy;
  }
}

class _FakePlayService extends PlayUpdateService {
  _FakePlayService({
    this.supported = true,
    this.attempt = PlayUpdateAttempt.started,
  });

  final bool supported;
  final PlayUpdateAttempt attempt;

  final openedListings = <String>[];
  final installEvents = StreamController<InstallStatus>.broadcast();
  int immediateCalls = 0;
  int flexibleCalls = 0;
  int completeCalls = 0;

  @override
  bool get isSupported => supported;

  @override
  Future<PlayUpdateAttempt> startImmediateUpdate() async {
    immediateCalls++;
    return attempt;
  }

  @override
  Future<PlayUpdateAttempt> startFlexibleUpdate() async {
    flexibleCalls++;
    return attempt;
  }

  @override
  Future<bool> completeFlexibleUpdate() async {
    completeCalls++;
    return true;
  }

  @override
  Stream<InstallStatus> get installStatus => installEvents.stream;

  @override
  Future<bool> openStoreListing(String url) async {
    openedListings.add(url);
    return true;
  }

  Future<void> close() => installEvents.close();
}

ProviderContainer _container({
  AppUpdateRepository? repository,
  PlayUpdateService? service,
  SharedPreferences? prefs,
}) {
  final container = ProviderContainer(
    overrides: [
      deviceIdentityProvider.overrideWithValue(_identity),
      appUpdateRepositoryProvider.overrideWithValue(
        repository ?? _FakeUpdateRepository(AppVersionPolicy.none),
      ),
      playUpdateServiceProvider.overrideWithValue(
        service ?? _FakePlayService(),
      ),
      if (prefs != null) sharedPrefsProvider.overrideWithValue(prefs),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

Widget _gateHost(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(
      home: AppUpdateGate(child: Scaffold(body: Text('app content'))),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('AppVersionPolicy parsing', () {
    test('reads a flat camelCase payload', () {
      final policy = AppVersionPolicy.fromApiJson({
        'minimumBuild': 36,
        'latestBuild': 38,
        'latestVersion': '1.2.0',
        'storeUrl': 'https://play.google.com/store/apps/details?id=x',
        'message': 'Faster top-ups',
      });

      expect(policy.minimumBuild, 36);
      expect(policy.latestBuild, 38);
      expect(policy.latestVersion, '1.2.0');
      expect(policy.message, 'Faster top-ups');
      expect(policy.isEmpty, isFalse);
    });

    test('accepts snake_case aliases', () {
      final policy = AppVersionPolicy.fromApiJson({
        'minimum_build': '36',
        'latest_version_code': 38,
        'play_store_url': 'https://play.google.com/store/apps/details?id=x',
        'release_notes': 'New rewards',
      });

      expect(policy.minimumBuild, 36);
      expect(policy.latestBuild, 38);
      expect(policy.storeUrl, contains('play.google.com'));
      expect(policy.message, 'New rewards');
    });

    test('unwraps a data envelope and the android node', () {
      final policy = AppVersionPolicy.fromApiJson({
        'data': {
          'android': {'minimumBuild': 34, 'latestBuild': 35},
          'ios': {'minimumBuild': 1, 'latestBuild': 999},
        },
      });

      expect(policy.minimumBuild, 34);
      expect(policy.latestBuild, 35);
    });

    test('an empty payload enforces nothing', () {
      final policy = AppVersionPolicy.fromApiJson({'status': 'ok'});

      expect(policy.isEmpty, isTrue);
      expect(
        policy.urgencyFor(currentBuild: 1, currentVersion: '0.0.1'),
        UpdateUrgency.none,
      );
    });

    // Captured from production on 2026-11-18: the shape the backend actually
    // serves, including the mirrored `android` node our parser descends into.
    test('parses the live production payload', () {
      final policy = AppVersionPolicy.fromApiJson({
        'minimumBuild': 33,
        'latestBuild': 34,
        'latestVersion': '1.1.3',
        'storeUrl': 'https://play.google.com/store/apps/details?id=com.advansistechnologies.lidapay',
        'message': 'Faster top-ups, new rewards and smoother checkout.',
        'android': {
          'minimumBuild': 33,
          'latestBuild': 34,
          'latestVersion': '1.1.3',
        },
        'ios': <String, dynamic>{},
      });

      expect(policy.minimumBuild, 33);
      expect(policy.latestBuild, 34);

      // 1.1.3 itself: nothing to show.
      expect(
        policy.urgencyFor(currentBuild: 34, currentVersion: '1.1.3'),
        UpdateUrgency.none,
      );
      // 1.1.2 (live today): optional prompt, not blocked.
      expect(
        policy.urgencyFor(currentBuild: 33, currentVersion: '1.1.2'),
        UpdateUrgency.optional,
      );
      // 1.1.1 and older: below the supported minimum.
      expect(
        policy.urgencyFor(currentBuild: 32, currentVersion: '1.1.1'),
        UpdateUrgency.required,
      );
    });
  });

  group('AppVersionPolicy urgency', () {
    test('blocks builds below the supported minimum', () {
      const policy = AppVersionPolicy(minimumBuild: 36, latestBuild: 38);

      expect(
        policy.urgencyFor(currentBuild: 33, currentVersion: '1.1.2'),
        UpdateUrgency.required,
      );
    });

    test('offers an optional update between minimum and latest', () {
      const policy = AppVersionPolicy(minimumBuild: 30, latestBuild: 38);

      expect(
        policy.urgencyFor(currentBuild: 33, currentVersion: '1.1.2'),
        UpdateUrgency.optional,
      );
    });

    test('stays quiet on the newest build', () {
      const policy = AppVersionPolicy(minimumBuild: 30, latestBuild: 34);

      expect(
        policy.urgencyFor(currentBuild: 34, currentVersion: '1.1.3'),
        UpdateUrgency.none,
      );
    });

    test('never gates an unknown local build', () {
      const policy = AppVersionPolicy(minimumBuild: 99, latestBuild: 100);

      expect(
        policy.urgencyFor(currentBuild: 0, currentVersion: '1.1.3'),
        UpdateUrgency.none,
      );
    });

    test('falls back to version names when no build is published', () {
      const policy = AppVersionPolicy(
        minimumVersion: '1.2.0',
        latestVersion: '1.2.1',
      );

      expect(
        policy.urgencyFor(currentBuild: 10, currentVersion: '1.1.9'),
        UpdateUrgency.required,
      );

      const optionalPolicy = AppVersionPolicy(latestVersion: '1.3.0');
      expect(
        optionalPolicy.urgencyFor(currentBuild: 10, currentVersion: '1.2.1'),
        UpdateUrgency.optional,
      );
    });
  });

  group('compareVersionNames', () {
    test('compares numerically, not lexically', () {
      expect(compareVersionNames('1.1.10', '1.1.9'), greaterThan(0));
      expect(compareVersionNames('1.1.9', '1.1.10'), lessThan(0));
      expect(compareVersionNames('1.2', '1.2.0'), 0);
      expect(compareVersionNames('1.10.0', '1.9.9'), greaterThan(0));
    });

    test('ignores build and pre-release suffixes', () {
      expect(compareVersionNames('1.2.0+34', '1.2.0'), 0);
      expect(compareVersionNames('1.2.0-beta.1', '1.2.0'), 0);
    });
  });

  group('AppUpdateController', () {
    test('marks a build below the minimum as blocking', () async {
      final container = _container(
        repository: _FakeUpdateRepository(
          const AppVersionPolicy(minimumBuild: 36, latestBuild: 38),
        ),
      );
      final controller = container.read(appUpdateControllerProvider.notifier);

      await controller.check();

      final state = container.read(appUpdateControllerProvider);
      expect(state.urgency, UpdateUrgency.required);
      expect(state.isBlocking, isTrue);
      expect(state.policy.minimumBuild, 36);
    });

    test('throttles repeat checks until forced', () async {
      final repository = _FakeUpdateRepository(
        const AppVersionPolicy(latestBuild: 38),
      );
      final container = _container(repository: repository);
      final controller = container.read(appUpdateControllerProvider.notifier);

      await controller.check();
      await controller.check();
      expect(repository.calls, 1);

      await controller.check(force: true);
      expect(repository.calls, 2);
    });

    test('does nothing on platforms without Play in-app updates', () async {
      final repository = _FakeUpdateRepository(
        const AppVersionPolicy(minimumBuild: 36),
      );
      final play = _FakePlayService(supported: false);
      addTearDown(play.close);
      final container = _container(repository: repository, service: play);

      await container.read(appUpdateControllerProvider.notifier).check();

      expect(repository.calls, 0);
      expect(
        container.read(appUpdateControllerProvider).urgency,
        UpdateUrgency.none,
      );
    });

    test('"Later" hides an optional prompt and persists the snooze', () async {
      final prefs = await SharedPreferences.getInstance();
      final repository = _FakeUpdateRepository(
        const AppVersionPolicy(minimumBuild: 30, latestBuild: 38),
      );
      final container = _container(repository: repository, prefs: prefs);
      final controller = container.read(appUpdateControllerProvider.notifier);

      await controller.check();
      expect(
        container.read(appUpdateControllerProvider).urgency,
        UpdateUrgency.optional,
      );

      await controller.remindLater();
      expect(
        container.read(appUpdateControllerProvider).urgency,
        UpdateUrgency.none,
      );

      // A fresh controller (next launch) must not re-ask immediately.
      final nextContainer = _container(repository: repository, prefs: prefs);
      await nextContainer.read(appUpdateControllerProvider.notifier).check();
      expect(
        nextContainer.read(appUpdateControllerProvider).urgency,
        UpdateUrgency.none,
      );
    });

    test('an expired snooze lets the prompt through again', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'lidapay.update.snoozed_until.38',
        DateTime.now()
            .subtract(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      );
      final container = _container(
        repository: _FakeUpdateRepository(
          const AppVersionPolicy(minimumBuild: 30, latestBuild: 38),
        ),
        prefs: prefs,
      );

      await container.read(appUpdateControllerProvider.notifier).check();

      expect(
        container.read(appUpdateControllerProvider).urgency,
        UpdateUrgency.optional,
      );
    });

    test('a blocking update ignores the "Later" snooze', () async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(
        'lidapay.update.snoozed_until.38',
        DateTime.now().add(const Duration(days: 3)).millisecondsSinceEpoch,
      );
      final container = _container(
        repository: _FakeUpdateRepository(
          const AppVersionPolicy(minimumBuild: 36, latestBuild: 38),
        ),
        prefs: prefs,
      );

      await container.read(appUpdateControllerProvider.notifier).check();

      expect(
        container.read(appUpdateControllerProvider).urgency,
        UpdateUrgency.required,
      );
    });

    test(
      'falls back to the store listing when Play cannot run the flow',
      () async {
        final play = _FakePlayService(attempt: PlayUpdateAttempt.unsupported);
        addTearDown(play.close);
        final container = _container(
          repository: _FakeUpdateRepository(
            const AppVersionPolicy(minimumBuild: 36),
          ),
          service: play,
        );
        final controller = container.read(appUpdateControllerProvider.notifier);

        await controller.check();
        await controller.startUpdate();

        final state = container.read(appUpdateControllerProvider);
        expect(play.immediateCalls, 1);
        expect(play.openedListings.single, defaultPlayStoreUrl);
        expect(state.playUnavailable, isTrue);
        expect(state.starting, isFalse);
      },
    );

    test('tracks a flexible download through to restart', () async {
      final play = _FakePlayService();
      addTearDown(play.close);
      final container = _container(
        repository: _FakeUpdateRepository(
          const AppVersionPolicy(latestBuild: 38),
        ),
        service: play,
      );
      final controller = container.read(appUpdateControllerProvider.notifier);

      await controller.check();
      await controller.startUpdate();

      expect(play.flexibleCalls, 1);
      expect(play.immediateCalls, 0);
      expect(container.read(appUpdateControllerProvider).downloading, isTrue);

      play.installEvents.add(InstallStatus.downloaded);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(appUpdateControllerProvider);
      expect(state.downloading, isFalse);
      expect(state.readyToInstall, isTrue);

      await controller.restartToInstall();
      expect(play.completeCalls, 1);
    });
  });

  group('AppUpdateGate', () {
    testWidgets('shows a blocking cover with no way out', (tester) async {
      final play = _FakePlayService(attempt: PlayUpdateAttempt.started);
      addTearDown(play.close);
      final container = _container(
        repository: _FakeUpdateRepository(
          const AppVersionPolicy(minimumBuild: 36, latestBuild: 38),
        ),
        service: play,
      );

      await tester.pumpWidget(_gateHost(container));
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Later'), findsNothing);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(play.immediateCalls, 1);
    });

    testWidgets('offers "Later" for an optional update', (tester) async {
      final play = _FakePlayService();
      addTearDown(play.close);
      final container = _container(
        repository: _FakeUpdateRepository(
          const AppVersionPolicy(
            minimumBuild: 30,
            latestBuild: 38,
            message: 'Faster top-ups and new rewards.',
          ),
        ),
        service: play,
      );

      await tester.pumpWidget(_gateHost(container));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsOneWidget);
      expect(find.text('Faster top-ups and new rewards.'), findsOneWidget);

      await tester.tap(find.text('Later'));
      await tester.pumpAndSettle();

      expect(find.text('Update available'), findsNothing);
      expect(find.text('app content'), findsOneWidget);
    });

    testWidgets('stays out of the way when the build is current', (
      tester,
    ) async {
      final container = _container(
        repository: _FakeUpdateRepository(
          const AppVersionPolicy(minimumBuild: 30, latestBuild: 33),
        ),
      );

      await tester.pumpWidget(_gateHost(container));
      await tester.pumpAndSettle();

      expect(find.text('Update required'), findsNothing);
      expect(find.text('Update available'), findsNothing);
      expect(find.text('app content'), findsOneWidget);
    });
  });
}
