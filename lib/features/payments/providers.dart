import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/network/api_client.dart';
import '../../core/network/api_exception.dart';
import '../../core/network/token_store.dart';
import '../../core/utils/formatters.dart';
import '../auth/data/auth_models.dart';
import '../auth/providers.dart';
import '../services/data/service_models.dart';
import '../services/data/services_repository.dart';
import '../services/providers.dart';
import 'data/payment_models.dart';
import 'data/payments_repository.dart';
import 'data/pending_payment.dart';
import 'data/pending_payment_store.dart';
import 'data/remote_payments_repository.dart';

final paymentsRepositoryProvider = Provider<PaymentsRepository>(
  (ref) => RemotePaymentsRepository(ref.watch(apiClientProvider)),
);

final pendingPaymentStoreProvider = Provider<PendingPaymentStore>(
  (ref) => PendingPaymentStore(ref.watch(sharedPrefsProvider)),
);

/// Checkout-launch seam so tests can intercept `launchUrl`.
typedef CheckoutLauncher = Future<bool> Function(Uri url);

final checkoutLauncherProvider = Provider<CheckoutLauncher>(
  (ref) =>
      (uri) => launchUrl(uri, mode: LaunchMode.externalApplication),
);

enum PaymentPhase {
  idle,
  initiating,
  awaitingCallback,
  verifying,
  crediting,
  completed,
  failed,
}

class PaymentSessionState {
  const PaymentSessionState({
    this.phase = PaymentPhase.idle,
    this.pending,
    this.receipt,
    this.shopOrderNumber,
    this.message,
    this.providerStatus,
  });

  final PaymentPhase phase;
  final PendingPayment? pending;

  /// Set for service purchases once the backend confirms delivery.
  final ServiceReceipt? receipt;

  /// Set for shop payments once the gateway confirms payment; the screen
  /// re-fetches the order for its final payment status.
  final String? shopOrderNumber;

  /// User-facing status line for each phase.
  final String? message;

  /// Last raw status the payment rail reported (`PENDING` / `FAILED` …) —
  /// lets the awaiting panel distinguish "still waiting" from "the network
  /// says it didn't go through" without declaring the purchase dead.
  final String? providerStatus;

  bool get isBusy =>
      phase == PaymentPhase.initiating ||
      phase == PaymentPhase.verifying ||
      phase == PaymentPhase.crediting;
}

/// Client-generated payTransRef, mirroring the released app's `LDP-` format.
String newPaymentReference() {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final tail = timestamp.toRadixString(36).toUpperCase();
  return 'LDP-$timestamp-$tail';
}

/// GTPay `PartnerTransId`: numeric, at most 20 characters, unique per
/// payment attempt (epoch millis + 3 random digits = 16 digits).
String newPartnerTransId() {
  final suffix = Random.secure().nextInt(900) + 100;
  return '${DateTime.now().millisecondsSinceEpoch}$suffix';
}

/// Normalises a Ghana MoMo number to the local 10-digit `0XXXXXXXXX` form
/// GTPay expects in `ServiceNumber`.
String normalizeMomoNumber(String raw) {
  var digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.startsWith('233') && digits.length == 12) {
    digits = '0${digits.substring(3)}';
  } else if (digits.length == 9) {
    digits = '0$digits';
  }
  return digits;
}

bool isValidMomoNumber(String raw) =>
    RegExp(r'^0[235]\d{8}$').hasMatch(normalizeMomoNumber(raw));

/// Orchestrates pay → verify → credit for Advansis Pay checkout. The deep
/// link and the manual "I've paid" recheck both funnel into the same
/// [_verifyThenCredit] — a single-flight future so a duplicated
/// `lidapay://` delivery or a tap during a query can never double-credit.
final paymentSessionProvider =
    StateNotifierProvider<PaymentSessionNotifier, PaymentSessionState>((ref) {
      return PaymentSessionNotifier(
        ref.watch(paymentsRepositoryProvider),
        ref.watch(pendingPaymentStoreProvider),
        ref.watch(servicesRepositoryProvider),
        ref.watch(checkoutLauncherProvider),
        () => ref.read(authSessionProvider)?.user,
      );
    });

class PaymentSessionNotifier extends StateNotifier<PaymentSessionState> {
  PaymentSessionNotifier(
    this._payments,
    this._store,
    this._services,
    this._launchCheckout,
    this._currentUser, {
    int queryAttempts = 8,
    Duration queryDelay = const Duration(seconds: 4),
    int gtPayPollAttempts = 4,
    Duration gtPayPollDelay = const Duration(seconds: 2),
    Duration gtPayExpireAfter = const Duration(minutes: 5),
  }) : _queryAttempts = queryAttempts,
       _queryDelay = queryDelay,
       _gtPayPollAttempts = gtPayPollAttempts,
       _gtPayPollDelay = gtPayPollDelay,
       _gtPayExpireAfter = gtPayExpireAfter,
       super(const PaymentSessionState()) {
    _pending = _store.load();
    if (_pending != null) {
      state = PaymentSessionState(
        phase: PaymentPhase.awaitingCallback,
        pending: _pending,
        message:
            'A payment is still in progress. Finish it in the browser, '
            'then check again.',
      );
    }
  }

  final PaymentsRepository _payments;
  final PendingPaymentStore _store;
  final ServicesRepository _services;
  final CheckoutLauncher _launchCheckout;
  final UserProfile? Function() _currentUser;

  PendingPayment? _pending;
  Future<void>? _verifying;

  /// Persisted in-flight purchase (survives process death).
  PendingPayment? get pendingPayment => _pending;

  /// Step 1 — start the payment on the chosen rail. Returns true once the
  /// payment is in flight (checkout opened, or MoMo prompt sent); on any
  /// failure the state drops to `failed` and the purchase stays uncharged.
  Future<bool> beginPayment(
    PendingPayment draft, {
    PaymentMethod method = PaymentMethod.card,
    String? momoNumber,
  }) async {
    final user = _currentUser();
    if (user == null) {
      state = const PaymentSessionState(
        phase: PaymentPhase.failed,
        message: 'Your session expired. Please sign in again.',
      );
      return false;
    }
    _verifying = null;
    if (method == PaymentMethod.mobileMoney) {
      return _beginGtPay(draft, user, momoNumber ?? user.phoneNumber);
    }
    state = PaymentSessionState(
      phase: PaymentPhase.initiating,
      pending: draft,
      message: 'Preparing secure checkout…',
    );
    try {
      final initiation = await _payments.initiatePayment(
        userId: user.id,
        firstName: user.firstName,
        lastName: user.lastName,
        email: user.email,
        phoneNumber: user.phoneNumber,
        username: user.username.isEmpty ? user.phoneNumber : user.username,
        amount: draft.payAmount,
        orderDesc: draft.orderDesc,
        payTransRef: draft.reference,
        transType: 'MOMO',
        shopOrderNumber: draft.kind == PendingPaymentKind.shopOrder
            ? draft.params['orderNumber']?.toString()
            : null,
        redirectUrl: draft.kind == PendingPaymentKind.shopOrder
            ? AppConstants.shopCheckoutRedirectUrl
            : null,
      );

      _pending = draft.copyWith(
        token: initiation.token,
        advansisOrderId: initiation.orderId,
        checkoutUrl: initiation.checkoutUrl,
      );
      await _store.save(_pending!);

      final launched = await _launchCheckout(Uri.parse(initiation.checkoutUrl));
      if (!launched) {
        state = PaymentSessionState(
          phase: PaymentPhase.failed,
          pending: _pending,
          message: 'Could not open the payment page. Please try again.',
        );
        return false;
      }
      state = PaymentSessionState(
        phase: PaymentPhase.awaitingCallback,
        pending: _pending,
        message: 'Complete the payment in your browser, then return here.',
      );
      return true;
    } on ApiException catch (error) {
      state = PaymentSessionState(
        phase: PaymentPhase.failed,
        pending: _pending,
        message: error.message,
      );
      return false;
    } catch (_) {
      state = PaymentSessionState(
        phase: PaymentPhase.failed,
        pending: _pending,
        message: 'Payment could not be started. Please try again.',
      );
      return false;
    }
  }

  /// GTPay `debitwallet`: the PartnerTransId is persisted with the pending
  /// purchase *before* the pay call, so a timeout or app kill is always
  /// reconciled through `/gtpay/status` with the same ID — never a second
  /// debit.
  Future<bool> _beginGtPay(
    PendingPayment draft,
    UserProfile user,
    String rawMomo,
  ) async {
    final momo = normalizeMomoNumber(rawMomo);
    if (!isValidMomoNumber(momo)) {
      state = const PaymentSessionState(
        phase: PaymentPhase.failed,
        message: 'Enter a valid 10-digit Ghana Mobile Money number.',
      );
      return false;
    }
    final pending = draft.copyWith(
      method: PaymentMethod.mobileMoney,
      partnerTransId: newPartnerTransId(),
      momoNumber: momo,
    );
    _pending = pending;
    await _store.save(pending);
    state = PaymentSessionState(
      phase: PaymentPhase.initiating,
      pending: pending,
      message: 'Sending a payment prompt to $momo…',
    );

    final fullName = '${user.firstName} ${user.lastName}'.trim();
    try {
      final result = await _payments.gtPayDebit(
        partnerTransId: pending.partnerTransId!,
        userId: user.id,
        userName: user.username.isEmpty ? user.phoneNumber : user.username,
        momoNumber: momo,
        amount: pending.payAmount,
        remarks: pending.orderDesc,
        paidBy: fullName.isEmpty ? momo : fullName,
        shopOrderNumber: pending.kind == PendingPaymentKind.shopOrder
            ? pending.params['orderNumber']?.toString()
            : null,
      );
      switch (result.outcome) {
        case PaymentOutcome.success:
          unawaited(_credit(pending));
          return true;
        case PaymentOutcome.failed:
          // A FAILED report is not the end — the telco may still confirm
          // late, and the user may simply need a fresh prompt.
          state = PaymentSessionState(
            phase: PaymentPhase.awaitingCallback,
            pending: pending,
            providerStatus: result.status,
            message: result.message ??
                'The network reported the payment did not go through. If '
                    'you already approved the prompt, check again — or '
                    'send a new prompt.',
          );
          return true;
        case PaymentOutcome.pending:
          unawaited(_verifyThenCredit(pending));
          return true;
      }
    } on ApiException catch (error) {
      final status = error.statusCode;
      // A timeout / gateway error is an unknown outcome: GTBank may still
      // be talking to the telco, so reconcile with the same PartnerTransId.
      if (status == null || status >= 500) {
        unawaited(_verifyThenCredit(pending));
        return true;
      }
      await _store.clear();
      _pending = null;
      state = PaymentSessionState(
        phase: PaymentPhase.failed,
        message: error.message,
      );
      return false;
    } catch (_) {
      unawaited(_verifyThenCredit(pending));
      return true;
    }
  }

  /// Step 2 — the `lidapay://` return. Callback params are hints only; the
  /// saved token drives verification, and an `orderId` that doesn't match
  /// the pending record is ignored rather than queried.
  Future<void> handleReturn({
    String? status,
    String? token,
    String? orderId,
  }) async {
    final pending = _pending ?? _store.load();
    if (pending == null) {
      state = const PaymentSessionState(
        phase: PaymentPhase.failed,
        message:
            'No payment is in progress. If you were charged, check your '
            'history or contact support.',
      );
      return;
    }
    _pending = pending;

    final savedOrderId = pending.advansisOrderId;
    if (orderId != null &&
        orderId.isNotEmpty &&
        savedOrderId != null &&
        savedOrderId.isNotEmpty &&
        orderId != savedOrderId) {
      state = PaymentSessionState(
        phase: PaymentPhase.awaitingCallback,
        pending: pending,
        message:
            'That payment return does not match the purchase in progress. '
            'Check your status again in a moment.',
      );
      return;
    }

    final lowered = status?.toLowerCase() ?? '';
    if ((lowered == 'cancelled' || lowered == 'canceled') &&
        (token == null || token.isEmpty)) {
      await _store.clear();
      _pending = null;
      state = const PaymentSessionState(
        phase: PaymentPhase.failed,
        message: 'Payment was cancelled. No charge was made.',
      );
      return;
    }

    await _verifyThenCredit(pending);
  }

  /// Manual "I've completed payment" path — identical verification to the
  /// deep-link return. Also used by the app-resume listener.
  Future<void> recheck() async {
    final pending = _pending ?? _store.load();
    if (pending == null) return;
    _pending = pending;
    await _verifyThenCredit(pending);
  }

  /// Re-open the checkout page when the user returns before finishing the
  /// mobile-money prompt.
  Future<void> reopenCheckout() async {
    final url = _pending?.checkoutUrl;
    if (url == null || url.isEmpty) return;
    try {
      await _launchCheckout(Uri.parse(url));
    } catch (_) {
      // Non-fatal: the pending payment stays in place for verification.
    }
  }

  /// Abandon the in-flight purchase before it settles. Only reachable from
  /// `awaitingCallback` — a payment already past verification is never
  /// cancelled locally.
  Future<void> cancelPending() async {
    if (_pending == null) return;
    await _store.clear();
    _pending = null;
    _verifying = null;
    state = const PaymentSessionState();
  }

  void reset() => state = const PaymentSessionState();

  Future<void> _verifyThenCredit(PendingPayment pending) =>
      _verifying ??= _doVerifyThenCredit(pending)
          .whenComplete(() => _verifying = null);

  final int _queryAttempts;
  final Duration _queryDelay;
  final int _gtPayPollAttempts;
  final Duration _gtPayPollDelay;

  /// Hard deadline anchored to [PendingPayment.createdAt]. Ghana MoMo
  /// approval prompts die in ~1–2 minutes; past ~5 minutes the app stops
  /// active polling and asks the user to check or retry. A late approval
  /// can still reconcile through a single status query.
  final Duration _gtPayExpireAfter;

  Future<void> _doVerifyThenCredit(PendingPayment pending) async {
    if (pending.method == PaymentMethod.mobileMoney) {
      return _doVerifyGtPay(pending);
    }
    final token = pending.token;
    if (token == null || token.isEmpty) {
      state = PaymentSessionState(
        phase: PaymentPhase.failed,
        pending: pending,
        message:
            'This purchase cannot be verified — no payment token was saved.',
      );
      return;
    }

    state = PaymentSessionState(
      phase: PaymentPhase.verifying,
      pending: pending,
      message: 'Verifying your payment…',
    );

    PaymentOutcome? lastOutcome;
    for (var attempt = 0; attempt < _queryAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_queryDelay);
      try {
        final result = await _payments.queryTransaction(token);
        final outcome = result.outcome;
        if (outcome == PaymentOutcome.success) {
          await _credit(pending);
          return;
        }
        lastOutcome = outcome;
        if (outcome == PaymentOutcome.failed) break;
      } on ApiException {
        // A flaky query is unknown, not failure — keep polling like the
        // released app does for USSD approval delays.
        lastOutcome = PaymentOutcome.pending;
      } catch (_) {
        lastOutcome = PaymentOutcome.pending;
      }
    }

    if (lastOutcome == PaymentOutcome.failed) {
      await _store.clear();
      _pending = null;
      state = PaymentSessionState(
        phase: PaymentPhase.failed,
        message:
            'Payment was not completed. No charge was made — you can try '
            'again or use a different payment method.',
      );
      return;
    }

    state = PaymentSessionState(
      phase: PaymentPhase.awaitingCallback,
      pending: pending,
      message:
          'Your payment is still processing. If you already approved the '
          'mobile money prompt, tap “I’ve paid” to check again.',
    );
  }

  /// Polls `/gtpay/status` with the saved PartnerTransId while the customer
  /// approves the MoMo prompt. PENDING is neither success nor failure; when
  /// the window closes the record stays pending and is re-checked on resume
  /// or via "I've approved".
  Future<void> _doVerifyGtPay(PendingPayment pending) async {
    final transId = pending.partnerTransId;
    if (transId == null || transId.isEmpty) {
      state = PaymentSessionState(
        phase: PaymentPhase.failed,
        pending: pending,
        message: 'This payment cannot be verified — no reference was saved.',
      );
      return;
    }
    final approveCopy =
        'Approve the ${Formatters.currency(pending.payAmount)} prompt on '
        '${pending.momoNumber ?? 'your phone'} and enter your MoMo PIN.';
    state = PaymentSessionState(
      phase: PaymentPhase.verifying,
      pending: pending,
      message: approveCopy,
    );

    var sawFailure = false;
    String? lastStatus;
    String? lastMessage;
    // Once the approval window (anchored to when the payment was created)
    // has closed, an entry-level recheck gets exactly one status query —
    // enough to catch a late approval without burning a fresh poll window.
    final expiresAt = pending.createdAt.add(_gtPayExpireAfter);
    var expired = !DateTime.now().isBefore(expiresAt);
    final maxAttempts = expired ? 1 : _gtPayPollAttempts;
    for (var attempt = 0; attempt < maxAttempts; attempt++) {
      if (attempt > 0) await Future<void>.delayed(_gtPayPollDelay);
      if (attempt > 0 && !DateTime.now().isBefore(expiresAt)) {
        expired = true;
        break;
      }
      try {
        final result = await _payments.gtPayStatus(transId);
        lastStatus = result.status;
        if (result.outcome == PaymentOutcome.success) {
          await _credit(pending);
          return;
        }
        // Don't stop on a FAILED report — GTBank's async callback can still
        // flip the record; the user decides below whether to re-check,
        // send a new prompt, or cancel.
        sawFailure = result.outcome == PaymentOutcome.failed;
        lastMessage = result.message;
      } on ApiException catch (e) {
        // A 504 timeout means GTBank is not responding — stop polling and
        // let the user check status manually instead of hanging.
        if (e.statusCode == 504) break;
        // Other transient failures are unknown, not failure — keep going.
      } catch (_) {
        // Non-API failures are unknown, not failure — keep going.
      }
    }
    expired = expired || !DateTime.now().isBefore(expiresAt);

    final timedOut = expired && !sawFailure;
    state = PaymentSessionState(
      phase: PaymentPhase.awaitingCallback,
      pending: pending,
      providerStatus: timedOut
          ? 'TIMED_OUT'
          : (lastStatus ?? (sawFailure ? 'FAILED' : 'PENDING')),
      message: sawFailure
          ? (lastMessage?.isNotEmpty == true
                ? '${Formatters.friendlyFailureReason(lastMessage)} If you '
                      'already approved the prompt, tap “Check status” — '
                      'or send a new prompt.'
                : 'The network reported the payment did not go through. '
                      'If you already approved the prompt, tap “Check '
                      'status” — or send a new prompt.')
          : timedOut
          ? 'No response from the mobile money network — the approval '
                'prompt has probably expired on your phone. If you already '
                'paid, tap “Check status”; otherwise cancel and try again.'
          : 'Still waiting for the network to confirm. If you already '
                'entered your PIN, tap “I’ve approved” to check again.',
    );
  }

  /// Sends a fresh MoMo prompt for the same purchase with a brand-new
  /// PartnerTransId. Only reachable after the network reported a failure
  /// — a payment whose status is outstanding is never debited twice.
  Future<bool> retryMobileMoney({String? momoNumber}) async {
    final pending = _pending ?? _store.load();
    if (pending == null || pending.method != PaymentMethod.mobileMoney) {
      return false;
    }
    final user = _currentUser();
    if (user == null) {
      state = const PaymentSessionState(
        phase: PaymentPhase.failed,
        message: 'Your session expired. Please sign in again.',
      );
      return false;
    }
    _verifying = null;
    return _beginGtPay(
      pending,
      user,
      momoNumber ?? pending.momoNumber ?? user.phoneNumber,
    );
  }

  /// Step 3 — deliver the purchase through the services repository. The
  /// backend is told nothing about the payment here; the same provider
  /// endpoints the old app credits post-payment are reused verbatim.
  Future<void> _credit(PendingPayment pending) async {
    state = PaymentSessionState(
      phase: PaymentPhase.crediting,
      pending: pending,
      message: 'Payment confirmed — completing your order…',
    );
    try {
      if (pending.kind == PendingPaymentKind.shopOrder) {
        await _store.clear();
        _pending = null;
        state = PaymentSessionState(
          phase: PaymentPhase.completed,
          shopOrderNumber: pending.params['orderNumber']?.toString(),
          message: 'Payment confirmed.',
        );
        return;
      }
      await _finishWithReceipt(
        pending,
        deliverPendingPayment(_services, pending),
      );
    } on ApiException catch (error) {
      // Payment succeeded but delivery failed/unknown — keep the pending
      // record so the user can retry crediting without paying again.
      state = PaymentSessionState(
        phase: PaymentPhase.awaitingCallback,
        pending: pending,
        message:
            'Payment was confirmed but the delivery did not complete '
            '(${error.message}). Tap “I’ve paid” to retry — you will not be '
            'charged again.',
      );
    } catch (_) {
      state = PaymentSessionState(
        phase: PaymentPhase.awaitingCallback,
        pending: pending,
        message:
            'Payment was confirmed but the delivery did not complete. Tap '
            '“I’ve paid” to retry — you will not be charged again.',
      );
    }
  }

  Future<void> _finishWithReceipt(
    PendingPayment pending,
    Future<ServiceReceipt> creditCall,
  ) async {
    final receipt = await creditCall;
    await _store.clear();
    _pending = null;
    state = PaymentSessionState(
      phase: PaymentPhase.completed,
      receipt: receipt,
      message: 'Done.',
    );
  }
}

/// Maps a [PendingPayment] back into its `ServicesRepository` credit call —
/// the single delivery boundary shared by the Advansis-Pay session and the
/// Lida-Value-funded checkout, so both fund sources deliver through exactly
/// the same provider endpoints and receipt parsing.
Future<ServiceReceipt> deliverPendingPayment(
  ServicesRepository services,
  PendingPayment pending,
) {
  switch (pending.kind) {
    case PendingPaymentKind.ghanaAirtime:
      return services.buyLocalAirtime(
        recipientNumber: pending.params['recipientNumber'] as String,
        amount: (pending.params['amount'] as num).toDouble(),
        networkId: pending.params['networkId'] as String,
        saveToLidaValue: pending.params['saveToLidaValue'] == true,
        isSelfTopup: pending.params['isSelfTopup'] == true,
      );
    case PendingPaymentKind.globalAirtime:
      return services.buyGlobalAirtime(
        recipientNumber: pending.params['recipientNumber'] as String,
        amount: (pending.params['amount'] as num).toDouble(),
        countryCode: pending.params['countryCode'] as String,
        operatorId: pending.params['operatorId']?.toString(),
        recipientDialCode: pending.params['recipientDialCode']?.toString(),
        recipientEmail: pending.params['recipientEmail']?.toString(),
        senderNumber: pending.params['senderNumber']?.toString(),
        senderCountryCode:
            pending.params['senderCountryCode']?.toString() ?? 'GH',
        currency: pending.params['currency']?.toString() ?? 'USD',
        isSelfTopup: pending.params['isSelfTopup'] == true,
      );
    case PendingPaymentKind.ghanaData:
      final bundle = pending.params['bundle'] as Map;
      return services.buyDataBundle(
        recipientNumber: pending.params['recipientNumber'] as String,
        networkId: pending.params['networkId'] as String,
        bundle: DataBundle(
          id: bundle['id'].toString(),
          name: bundle['name'].toString(),
          price: (bundle['price'] as num).toDouble(),
          dataAmount: bundle['dataAmount'].toString(),
        ),
        saveToLidaValue: pending.params['saveToLidaValue'] == true,
        isSelfTopup: pending.params['isSelfTopup'] == true,
      );
    case PendingPaymentKind.globalData:
      return services.buyGlobalDataBundle(
        recipientNumber: pending.params['recipientNumber'] as String,
        amount: (pending.params['amount'] as num).toDouble(),
        countryCode: pending.params['countryCode'] as String,
        operatorId: pending.params['operatorId']?.toString(),
        operatorName: pending.params['operatorName']?.toString(),
        recipientDialCode: pending.params['recipientDialCode']?.toString(),
        recipientEmail: pending.params['recipientEmail']?.toString(),
        senderNumber: pending.params['senderNumber']?.toString(),
        senderCountryCode:
            pending.params['senderCountryCode']?.toString() ?? 'GH',
        currency: pending.params['currency']?.toString() ?? 'USD',
        isSelfTopup: pending.params['isSelfTopup'] == true,
      );
    case PendingPaymentKind.shopOrder:
      throw UnsupportedError(
        'Shop orders are delivered by the payment session, not this helper.',
      );
  }
}
