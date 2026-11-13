import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../payments/data/pending_payment.dart';
import '../payments/providers.dart';
import '../services/data/service_models.dart';
import '../services/data/services_repository.dart';
import '../services/providers.dart';

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
  });

  final LidaTopupPhase phase;
  final ServiceReceipt? receipt;

  /// The Lida Value ledger reference — surfaced when delivery fails after a
  /// successful debit so the charge can be reconciled.
  final String? debitReference;
  final String? message;

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
      (ref) => LidaValueTopupNotifier(ref.watch(servicesRepositoryProvider)),
    );

class LidaValueTopupNotifier extends StateNotifier<LidaTopupState> {
  LidaValueTopupNotifier(this._services) : super(const LidaTopupState());

  final ServicesRepository _services;
  bool _running = false;

  Future<void> execute({
    required PendingPayment draft,
    required ServiceFunding funding,
    required String serviceType,
  }) async {
    if (_running || !funding.isLidaValue) return;
    _running = true;
    final recipient = draft.params['recipientNumber']?.toString() ?? '';
    state = const LidaTopupState(
      phase: LidaTopupPhase.debiting,
      message: 'Debiting your Lida Value…',
    );
    try {
      if (funding == ServiceFunding.lidaValueUse) {
        final bundle = draft.params['bundle'];
        final receipt = await _services.useLidaValue(
          amount: draft.deliverAmount,
          destination: recipient,
          serviceType: serviceType,
          network: int.tryParse(draft.params['networkId']?.toString() ?? ''),
          dataCode: bundle is Map ? bundle['id']?.toString() : null,
        );
        if (mounted) {
          state = LidaTopupState(
            phase: LidaTopupPhase.completed,
            receipt: receipt,
            debitReference: receipt.reference,
          );
        }
        return;
      }
      final debit = await _services.sendLidaValue(
        amount: draft.deliverAmount,
        destination: recipient,
        serviceType: serviceType,
      );
      state = LidaTopupState(
        phase: LidaTopupPhase.delivering,
        debitReference: debit.reference,
        message: 'Lida Value charged — delivering your $serviceType…',
      );
      final receipt = await deliverPendingPayment(_services, draft);
      state = LidaTopupState(
        phase: LidaTopupPhase.completed,
        receipt: receipt,
        debitReference: debit.reference,
      );
    } on UnsupportedError {
      state = const LidaTopupState(
        phase: LidaTopupPhase.failed,
        message: 'This purchase cannot be paid from Lida Value.',
      );
    } on ApiException catch (error) {
      state = LidaTopupState(
        phase: LidaTopupPhase.failed,
        debitReference: state.debitReference,
        message: error.message,
      );
    } catch (_) {
      state = LidaTopupState(
        phase: LidaTopupPhase.failed,
        debitReference: state.debitReference,
        message:
            'The top-up did not complete. If Lida Value was debited, keep '
            'the debit reference for support.',
      );
    } finally {
      _running = false;
    }
  }
}
