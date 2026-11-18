import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../payments/data/pending_payment.dart';
import '../payments/providers.dart';
import '../services/data/service_models.dart';
import '../services/data/services_repository.dart';
import '../services/providers.dart';
import 'data/lv_attempt_store.dart';

/// How an airtime/data purchase is funded.
enum ServiceFunding {
  /// Advansis Pay mobile-money checkout (the default wizard path).
  momo,

  /// Lida Value USE — self top-up, direct debit from the Lida Value wallet.
  lidaValueUse,

  /// Lida Value SEND — top-up for another number, debited from the Lida
  /// Value wallet rather than mobile money or a card. Registered recipients
  /// still get the direct-vs-Lida-Value choice server-side.
  lidaValueSend;

  bool get isLidaValue => this != ServiceFunding.momo;

  static ServiceFunding parse(String? value) => switch (value) {
    'lv-use' => ServiceFunding.lidaValueUse,
    'lv-send' => ServiceFunding.lidaValueSend,
    _ => ServiceFunding.momo,
  };
}

enum LidaTopupPhase { idle, debiting, delivering, completed, failed }

class LidaTopupState {
  const LidaTopupState({
    this.phase = LidaTopupPhase.idle,
    this.receipt,
    this.debitReference,
    this.message,
    this.clientReference,
    this.outcomeUnknown = false,
  });

  final LidaTopupPhase phase;
  final ServiceReceipt? receipt;

  /// The Lida Value ledger reference — surfaced when delivery fails after a
  /// successful debit so the charge can be reconciled.
  final String? debitReference;
  final String? message;

  /// The idempotency reference used for this attempt. Retrying the same
  /// purchase reuses it so the backend cannot debit the wallet twice.
  final String? clientReference;

  /// True when the wallet debit could not be confirmed (timeout, offline or
  /// a 5xx from the provider). The wallet may or may not have been debited,
  /// so the app must never silently send the debit again.
  final bool outcomeUnknown;

  bool get isBusy =>
      phase == LidaTopupPhase.debiting || phase == LidaTopupPhase.delivering;
}

/// Orchestrates a Lida-Value-funded top-up.
///
/// * **USE** (self): exactly one `POST /lida-value/use`. Per the handoff
///   contract (§4, §9-D) the backend debits the wallet AND purchases the
///   airtime/data itself, so the app must never follow it with a provider
///   call — doing so would deliver (and charge) twice.
/// * **SEND** (another number): SEND is one of the Lida Value menu actions,
///   not a standalone service, so the purchase is debited from the Lida Value
///   wallet — never mobile money, a debit card or a credit card — and that
///   wallet debit *is* the payment. `/lida-value/send` only moves the value,
///   so delivery still runs through the domestic/Reloadly purchase route with
///   `isSelfTopup: false`; the recipient gets airtime/data, not wallet value.
///   A parked recipient decision surfaces as `receipt.pendingTopup`.
final lidaValueTopupProvider =
    StateNotifierProvider.autoDispose<LidaValueTopupNotifier, LidaTopupState>(
      (ref) {
        final notifier = LidaValueTopupNotifier(
          ref.watch(servicesRepositoryProvider),
          ref.watch(lvAttemptStoreProvider),
        );
        // A wallet debit that was confirmed but never delivered is finished
        // on the next app start instead of leaving the customer short.
        notifier.resumePendingDelivery();
        return notifier;
      },
    );

class LidaValueTopupNotifier extends StateNotifier<LidaTopupState> {
  LidaValueTopupNotifier(this._services, this._store)
    : super(const LidaTopupState());

  final ServicesRepository _services;
  final LvAttemptStore _store;

  bool _running = false;
  LvAttempt? _attempt;

  /// True while a debit or delivery is in flight.
  bool get isRunning => _running;

  void _emit(LidaTopupState next) {
    if (!mounted) return;
    state = next;
  }

  /// Finishes a purchase whose wallet debit was confirmed but whose
  /// delivery never landed (app killed, navigation away, network drop).
  /// Only the delivery is re-run — the wallet is never debited twice.
  Future<void> resumePendingDelivery() async {
    if (_running) return;
    final attempt = _store.load();
    if (attempt == null || !attempt.isDebited) return;
    _running = true;
    _attempt = attempt;
    _emit(
      LidaTopupState(
        phase: LidaTopupPhase.delivering,
        debitReference: attempt.debitReference,
        clientReference: attempt.draft.clientReference,
        message: 'Finishing your last Lida Value purchase…',
      ),
    );
    try {
      final receipt = await deliverPendingPayment(_services, attempt.draft);
      await _store.clear();
      _attempt = null;
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.completed,
          receipt: receipt,
          debitReference: attempt.debitReference,
          clientReference: attempt.draft.clientReference,
        ),
      );
    } catch (_) {
      // The debit stands — the attempt stays on disk for the next resume.
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.failed,
          debitReference: attempt.debitReference,
          clientReference: attempt.draft.clientReference,
          message:
              'Your Lida Value was charged but the delivery did not finish. '
              'We keep retrying it — reference ${attempt.debitReference}.',
        ),
      );
    } finally {
      _running = false;
    }
  }

  Future<void> execute({
    required PendingPayment draft,
    required ServiceFunding funding,
    required String serviceType,
  }) async {
    if (_running || !funding.isLidaValue) return;
    _running = true;
    final recipient = draft.params['recipientNumber']?.toString() ?? '';
    final amount = draft.deliverAmount;

    // A retry of the same purchase reuses the stored idempotency reference,
    // so the backend returns the first result instead of debiting again.
    final stored = _attempt ?? _store.load();
    final isRetry = stored != null &&
        stored.matches(
          recipient: recipient,
          amount: amount,
          serviceType: serviceType,
        );
    final reference = isRetry ? stored.draft.clientReference : draft.clientReference;
    final attemptDraft = draft.copyWith(clientReference: reference);

    // The wallet was already debited for this purchase — finish the
    // delivery only. A second debit here would take the money twice.
    if (isRetry && stored.isDebited) {
      await _deliverOnly(
        attemptDraft,
        stored.debitReference,
        serviceType,
      );
      _running = false;
      return;
    }

    _attempt = LvAttempt(
      draft: attemptDraft,
      serviceType: serviceType,
      updatedAt: DateTime.now(),
    );
    await _store.save(_attempt!);
    _emit(
      LidaTopupState(
        phase: LidaTopupPhase.debiting,
        clientReference: reference,
        message: 'Debiting your Lida Value…',
      ),
    );
    try {
      if (funding == ServiceFunding.lidaValueUse) {
        final bundle = attemptDraft.params['bundle'];
        final receipt = await _services.useLidaValue(
          amount: amount,
          destination: recipient,
          serviceType: serviceType,
          clientReference: reference,
          network: int.tryParse(
            attemptDraft.params['networkId']?.toString() ?? '',
          ),
          dataCode: bundle is Map ? bundle['id']?.toString() : null,
        );
        await _store.clear();
        _attempt = null;
        _emit(
          LidaTopupState(
            phase: LidaTopupPhase.completed,
            receipt: receipt,
            debitReference: receipt.reference,
            clientReference: reference,
          ),
        );
        return;
      }
      final debit = await _services.sendLidaValue(
        amount: amount,
        destination: recipient,
        serviceType: serviceType,
        clientReference: reference,
      );
      // Record the debit before delivering: from here on the wallet is
      // spent, and the delivery must be finished no matter what happens.
      _attempt = LvAttempt(
        draft: attemptDraft,
        serviceType: serviceType,
        debitReference: debit.reference,
        updatedAt: DateTime.now(),
      );
      await _store.save(_attempt!);
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.delivering,
          debitReference: debit.reference,
          clientReference: reference,
          message: 'Lida Value charged — delivering your $serviceType…',
        ),
      );
      final receipt = await deliverPendingPayment(_services, attemptDraft);
      await _store.clear();
      _attempt = null;
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.completed,
          receipt: receipt,
          debitReference: debit.reference,
          clientReference: reference,
        ),
      );
    } on UnsupportedError {
      await _store.clear();
      _attempt = null;
      _emit(
        const LidaTopupState(
          phase: LidaTopupPhase.failed,
          message: 'This purchase cannot be paid from Lida Value.',
        ),
      );
    } on ApiException catch (error) {
      // The wallet was already debited — this failure is in the delivery,
      // so the attempt survives and only the delivery is retried.
      if (_attempt?.isDebited ?? false) {
        _emit(
          LidaTopupState(
            phase: LidaTopupPhase.failed,
            debitReference: _attempt!.debitReference,
            clientReference: reference,
            outcomeUnknown: true,
            message:
                'Your Lida Value was charged but the delivery did not finish. '
                'We keep retrying it — reference ${_attempt!.debitReference}.',
          ),
        );
        return;
      }
      // A timeout, an offline network or a 5xx leaves the debit outcome
      // unknown — the attempt is kept so a retry reuses its reference
      // instead of sending a second debit.
      final status = error.statusCode;
      final unknown =
          error.outcomeUnknown || (status != null && status >= 500);
      if (!unknown) {
        await _store.clear();
        _attempt = null;
      }
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.failed,
          debitReference: _attempt?.debitReference,
          clientReference: reference,
          outcomeUnknown: unknown,
          message: unknown
              ? 'We could not confirm your Lida Value debit. Your wallet may '
                    'or may not have been charged — check your balance, then '
                    'try again. You will never be charged twice for the same '
                    'purchase.'
              : error.message,
        ),
      );
    } catch (_) {
      final debited = _attempt?.isDebited ?? false;
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.failed,
          debitReference: _attempt?.debitReference,
          clientReference: reference,
          outcomeUnknown: true,
          message: debited
              ? 'Your Lida Value was charged but the delivery did not finish. '
                    'We keep retrying it — reference ${_attempt!.debitReference}.'
              : 'The top-up did not complete. If Lida Value was debited, we '
                    'keep retrying the delivery — reference $reference.',
        ),
      );
    } finally {
      _running = false;
    }
  }

  /// Re-runs only the delivery for an already-debited purchase.
  Future<void> _deliverOnly(
    PendingPayment draft,
    String? debitReference,
    String serviceType,
  ) async {
    _emit(
      LidaTopupState(
        phase: LidaTopupPhase.delivering,
        debitReference: debitReference,
        clientReference: draft.clientReference,
        message: 'Lida Value already charged — delivering your $serviceType…',
      ),
    );
    try {
      final receipt = await deliverPendingPayment(_services, draft);
      await _store.clear();
      _attempt = null;
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.completed,
          receipt: receipt,
          debitReference: debitReference,
          clientReference: draft.clientReference,
        ),
      );
    } catch (error) {
      final status = error is ApiException ? error.statusCode : null;
      final unknown =
          error is ApiException &&
          (error.outcomeUnknown || (status != null && status >= 500));
      _emit(
        LidaTopupState(
          phase: LidaTopupPhase.failed,
          debitReference: debitReference,
          clientReference: draft.clientReference,
          outcomeUnknown: unknown,
          message:
              'Your Lida Value was charged but the delivery did not finish. '
              'We keep retrying it — reference $debitReference.',
        ),
      );
    }
  }
}
