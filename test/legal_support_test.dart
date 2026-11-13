import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lidapay_app/core/network/token_store.dart';
import 'package:lidapay_app/features/legal/legal_content.dart';
import 'package:lidapay_app/features/legal/policy_acceptance.dart';
import 'package:lidapay_app/features/legal/screens/legal_document_screen.dart';
import 'package:lidapay_app/features/legal/screens/legal_hub_screen.dart';
import 'package:lidapay_app/features/support/screens/support_category_screen.dart';
import 'package:lidapay_app/features/support/screens/support_screen.dart';
import 'package:lidapay_app/features/support/support_data.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<SharedPreferences> _prefs([Map<String, Object> values = const {}]) {
  SharedPreferences.setMockInitialValues(values);
  return SharedPreferences.getInstance();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PolicyAcceptance', () {
    test('starts unaccepted and persists a versioned acceptance', () async {
      final prefs = await _prefs();
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      expect(await container.read(policyStatusProvider.future), isNull);
      expect(policyAcceptedSync(prefs), isFalse);

      await container.read(policyStatusProvider.notifier).accept();

      final status = await container.read(policyStatusProvider.future);
      expect(status, isNotNull);
      expect(status!.version, kCurrentPolicyVersion);
      expect(status.isCurrent, isTrue);
      expect(policyAcceptedSync(prefs), isTrue);
      // Acceptance survives a cold start.
      expect(prefs.getInt('policy_accepted_version'), kCurrentPolicyVersion);
    });

    test('a stale stored version reports not-current', () async {
      final prefs = await _prefs({
        'policy_accepted_version': kCurrentPolicyVersion - 1,
        'policy_accepted_at': 1700000000000,
      });
      final container = ProviderContainer(
        overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
      );
      addTearDown(container.dispose);

      final status = await container.read(policyStatusProvider.future);
      expect(status, isNotNull);
      expect(status!.isCurrent, isFalse);
      expect(policyAcceptedSync(prefs), isFalse);
    });
  });

  group('policy documents', () {
    test('all ids resolve and every section has content', () {
      for (final doc in allPolicyDocuments) {
        expect(policyDocumentById(doc.id), same(doc));
        expect(doc.sections, isNotEmpty);
        for (final section in doc.sections) {
          expect(section.heading.trim(), isNotEmpty);
          expect(section.body.trim(), isNotEmpty);
        }
      }
      expect(policyDocumentById('nope'), isNull);
    });

    testWidgets('document screen renders title and every section', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: LegalDocumentScreen(document: termsOfService)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Terms of Service'), findsOneWidget);
      // Sections lazy-build — scroll each into view before asserting.
      for (final section in termsOfService.sections) {
        await tester.scrollUntilVisible(
          find.text(section.heading),
          200,
          scrollable: find.byType(Scrollable).first,
        );
        expect(find.text(section.heading), findsOneWidget);
      }
    });
  });

  group('LegalHubScreen', () {
    testWidgets('prompts review when policies are not accepted', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final prefs = await _prefs();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: LegalHubScreen()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Legal & Policies'), findsOneWidget);
      expect(find.text('Review our policies'), findsOneWidget);
      for (final doc in allPolicyDocuments) {
        expect(find.text(doc.title), findsWidgets);
      }
    });

    testWidgets('accepting flips the review card to the accepted banner', (
      tester,
    ) async {
      final prefs = await _prefs();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [sharedPrefsProvider.overrideWithValue(prefs)],
          child: const MaterialApp(home: LegalHubScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('I’ve read them — accept & continue'));
      await tester.pumpAndSettle();

      expect(find.text('Review our policies'), findsNothing);
      expect(find.textContaining('You accepted version'), findsOneWidget);
      expect(policyAcceptedSync(prefs), isTrue);
    });
  });

  group('support data', () {
    test('categories resolve, have FAQs and valid routes', () {
      for (final category in supportCategories) {
        expect(supportCategoryById(category.id), same(category));
        expect(category.faqs, isNotEmpty);
        for (final action in category.actions) {
          expect(action.route, startsWith('/'));
        }
      }
      expect(supportCategoryById('unknown'), isNull);
      expect(allFaqs().length, greaterThanOrEqualTo(20));
    });

    test('support e-mail deep link is prefilled with the topic', () {
      final uri = supportEmailUri(categoryTitle: 'Payments & wallet');
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'info@advansistechnologies.com');
      expect(uri.query, contains('Payments'));
    });

    test(
      'account deletion email identifies the account without credentials',
      () {
        final uri = accountDeletionRequestUri(
          email: 'user@example.com',
          phoneNumber: '+233240000000',
        );
        final body = uri.queryParameters['body']!;
        expect(uri.path, 'info@advansistechnologies.com');
        expect(uri.queryParameters['subject'], contains('deletion'));
        expect(body, contains('user@example.com'));
        expect(body, contains('+233240000000'));
        expect(body, isNot(contains('password:')));
        expect(body, isNot(contains('PIN:')));
        expect(body, isNot(contains('code:')));
      },
    );
  });

  group('SupportScreen', () {
    testWidgets('renders search, categories, popular picks and contact', (
      tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Support Center'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.text('Browse by topic'), findsOneWidget);
      for (final category in supportCategories) {
        expect(find.text(category.title), findsWidgets);
      }
      await tester.scrollUntilVisible(
        find.text('Still need a human?'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Still need a human?'), findsOneWidget);
    });

    testWidgets('search filters to matching FAQs', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SupportScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'otp');
      await tester.pumpAndSettle();

      expect(find.text('Browse by topic'), findsNothing);
      expect(find.textContaining('answer'), findsWidgets);
      expect(find.text('I’m not receiving the sign-in code'), findsOneWidget);
    });
  });

  group('SupportCategoryScreen', () {
    testWidgets('renders actions and expandable answers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: SupportCategoryScreen(categoryId: 'lidavalue')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lida Value & Points'), findsOneWidget);
      expect(find.text('Try this first'), findsOneWidget);
      expect(find.text('Open my Lida Value wallet'), findsOneWidget);

      // Answers expand on tap.
      final question = find.text(
        'What’s the difference between Lida Value and Lida Points?',
      );
      await tester.tap(question);
      await tester.pumpAndSettle();
      expect(find.textContaining('spendable balance'), findsOneWidget);
    });
  });
}
