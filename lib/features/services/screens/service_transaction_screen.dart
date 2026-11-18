import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/providers.dart';
import '../../dashboard/providers.dart';
import '../../history/providers.dart';
import '../../lida_value/providers.dart';
import '../../payments/data/pending_payment.dart';
import '../../payments/providers.dart';
import '../../payments/widgets/payment_awaiting_panel.dart';
import '../../payments/widgets/payment_method_selector.dart';
import '../../recipient_choice/providers.dart';
import '../../recipient_choice/screens/pending_topup_screen.dart';
import '../data/service_models.dart';
import '../providers.dart';
import '../widgets/country_flag_badge.dart';
import '../widgets/lida_value_checkout_switch.dart';
import '../widgets/phone_number_formatter.dart';
import '../widgets/amount_preset_chip.dart';
import '../widgets/service_receipt_screen.dart';
import '../widgets/service_wizard_widgets.dart';
import '../widgets/topup_review_card.dart';

enum ServiceFlow { airtime, data, globalAirtime, qrPay, gtPay }

class ServiceTransactionScreen extends ConsumerStatefulWidget {
  const ServiceTransactionScreen({
    super.key,
    required this.flow,
    this.funding = ServiceFunding.momo,
  });

  final ServiceFlow flow;

  /// Lida Value USE/SEND debit the wallet instead of opening the Advansis
  /// checkout — only meaningful for the `data` flow today.
  final ServiceFunding funding;

  @override
  ConsumerState<ServiceTransactionScreen> createState() =>
      _ServiceTransactionScreenState();
}

class _ServiceTransactionScreenState
    extends ConsumerState<ServiceTransactionScreen> {
  static const _globalPresets = <double>[5, 10, 20, 50];
  final _formKey = GlobalKey<FormState>();
  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _description = TextEditingController();
  String? _network;
  String? _country;
  String? _serviceName;
  String? _bankCode;
  DataBundle? _bundle;
  bool _submitting = false;
  ServiceReceipt? _receipt;

  @override
  void dispose() {
    _phone.dispose();
    _amount.dispose();
    _description.dispose();
    super.dispose();
  }

  String get _title => switch (widget.flow) {
    ServiceFlow.airtime => 'Buy Airtime',
    ServiceFlow.data => 'Buy Data',
    ServiceFlow.globalAirtime => 'Global Airtime',
    ServiceFlow.qrPay => 'QR Pay',
    ServiceFlow.gtPay => 'GTPay Bills',
  };

  IconData get _icon => switch (widget.flow) {
    ServiceFlow.airtime => Icons.call_rounded,
    ServiceFlow.data => Icons.wifi_tethering_rounded,
    ServiceFlow.globalAirtime => Icons.public_rounded,
    ServiceFlow.qrPay => Icons.qr_code_scanner_rounded,
    ServiceFlow.gtPay => Icons.account_balance_rounded,
  };

  bool get _needsNetwork =>
      widget.flow == ServiceFlow.airtime || widget.flow == ServiceFlow.data;
  bool get _needsCountry => widget.flow == ServiceFlow.globalAirtime;
  bool get _needsService => widget.flow == ServiceFlow.gtPay;

  /// The GTBank service picked from POST /gtpay/services; bank transfers
  /// additionally need the receiving bank's GIP code.
  ServiceOption? get _selectedService {
    if (!_needsService || _serviceName == null) return null;
    final options =
        ref.read(gtPayServicesProvider).valueOrNull ?? const <ServiceOption>[];
    for (final option in options) {
      if (option.id == _serviceName) return option;
    }
    return null;
  }

  bool get _needsBank =>
      (_selectedService?.id.toLowerCase().contains('bank') ?? false) ||
      (_selectedService?.name.toLowerCase().contains('bank') ?? false);

  String get _numberLabel => switch (widget.flow) {
    ServiceFlow.qrPay => 'Merchant code',
    ServiceFlow.gtPay => 'Account / meter number',
    _ => 'Recipient number',
  };

  String get _numberHint => switch (widget.flow) {
    ServiceFlow.qrPay => 'Enter merchant code',
    ServiceFlow.gtPay => 'Number the service bills against',
    _ => '024 000 0000',
  };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_needsNetwork && _network == null) {
      _message('Choose a network first.');
      return;
    }
    if (_needsCountry && _country == null) {
      _message('Choose a recipient country first.');
      return;
    }
    if (widget.flow == ServiceFlow.data && _bundle == null) {
      _message('Choose a data bundle first.');
      return;
    }
    if (_needsService && _serviceName == null) {
      _message('Choose a service first.');
      return;
    }
    setState(() => _submitting = true);
    final clientReference = newClientReference();
    final repo = ref.read(servicesRepositoryProvider);
    final amount = double.tryParse(_amount.text.trim()) ?? _bundle?.price ?? 0;
    try {
      final receipt = switch (widget.flow) {
        ServiceFlow.airtime => await repo.buyLocalAirtime(
          recipientNumber: _phone.text.trim(),
          amount: amount,
          networkId: _network!,
          saveToLidaValue: false,
          clientReference: clientReference,
        ),
        ServiceFlow.data => await repo.buyDataBundle(
          recipientNumber: _phone.text.trim(),
          networkId: _network!,
          bundle: _bundle!,
          saveToLidaValue: false,
          clientReference: clientReference,
        ),
        ServiceFlow.globalAirtime => await repo.buyGlobalAirtime(
          recipientNumber: _phone.text.trim(),
          amount: amount,
          countryCode: _country!,
          clientReference: clientReference,
        ),
        ServiceFlow.qrPay => await repo.payQr(
          merchantCode: _phone.text.trim(),
          amount: amount,
        ),
        ServiceFlow.gtPay => await repo.payGtPayService(
          serviceName: _serviceName!,
          serviceNumber: _phone.text.trim(),
          secondaryServiceNumber: _needsBank ? _bankCode : null,
          amount: amount,
          remarks: _description.text.trim().isEmpty
              ? 'Lidapay $_serviceName payment'
              : _description.text.trim(),
        ),
      };
      if (mounted) setState(() => _receipt = receipt);
    } on ApiException catch (error) {
      _message(error.message);
    } catch (_) {
      _message('Unable to complete this request. Please try again.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  void _message(String value) =>
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(value)));

  @override
  Widget build(BuildContext context) {
    if (widget.flow == ServiceFlow.data) {
      return _EnhancedInternetDataWizard(funding: widget.funding);
    }
    if (_receipt case final receipt?)
      return ServiceReceiptScreen(
        receipt: receipt,
        icon: _icon,
        onDone: () => Navigator.of(context).pop(),
      );
    final networks = ref.watch(ghanaNetworksProvider);
    // Each provider only fires for the flow that needs it — GTPay
    // service/bank catalogues are not fetched inside the airtime/data
    // wizards (and a GTPay outage can't gate those flows).
    const emptyOptions = AsyncData<List<ServiceOption>>(<ServiceOption>[]);
    final countries = _needsCountry
        ? ref.watch(countriesProvider)
        : emptyOptions;
    final services = _needsService
        ? ref.watch(gtPayServicesProvider)
        : emptyOptions;
    final banks = _needsService ? ref.watch(gtPayBanksProvider) : emptyOptions;
    final bundles = (_network == null || widget.flow != ServiceFlow.data)
        ? null
        : ref.watch(dataBundlesProvider(_network!));
    final pending =
        (_needsNetwork && networks.isLoading) ||
        (_needsCountry && countries.isLoading) ||
        (_needsService && services.isLoading) ||
        (widget.flow == ServiceFlow.data && bundles?.isLoading == true);
    if (pending)
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Padding(
          padding: EdgeInsets.all(20),
          child: AppSkeletonScreen(),
        ),
      );
    final error =
        (_needsNetwork ? networks.error : null) ??
        (_needsCountry ? countries.error : null) ??
        (_needsService ? services.error : null) ??
        bundles?.error;
    if (error != null)
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: ErrorView(
          message: error.toString(),
          onRetry: () {
            ref.invalidate(ghanaNetworksProvider);
            ref.invalidate(countriesProvider);
            ref.invalidate(gtPayServicesProvider);
            ref.invalidate(gtPayBanksProvider);
            if (_network != null)
              ref.invalidate(dataBundlesProvider(_network!));
          },
        ),
      );

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: AppColors.heroGradient,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .16),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(_icon, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    _flowDescription,
                    style: const TextStyle(color: Colors.white, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_needsService) ...[
                  Text(
                    'Service',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _serviceName,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.account_balance_rounded),
                    ),
                    hint: const Text(
                      'Choose a GTBank service',
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: services.valueOrNull
                        ?.map(
                          (s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(
                              s.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      _serviceName = value;
                      _bankCode = null;
                    }),
                  ),
                  const SizedBox(height: 18),
                ],
                Text(
                  _numberLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    prefixIcon: Icon(
                      widget.flow == ServiceFlow.qrPay
                          ? Icons.storefront_rounded
                          : widget.flow == ServiceFlow.gtPay
                          ? Icons.numbers_rounded
                          : Icons.phone_rounded,
                    ),
                    hintText: _numberHint,
                  ),
                  validator: (v) => v == null || v.trim().length < 4
                      ? 'Enter a valid value.'
                      : null,
                ),
                if (_needsBank) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Receiving bank',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _bankCode,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.account_balance_rounded),
                    ),
                    hint: const Text(
                      'Choose bank',
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: banks.valueOrNull
                        ?.map(
                          (b) => DropdownMenuItem(
                            value: b.id,
                            child: Text(
                              b.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _bankCode = value),
                  ),
                ],
                if (_needsNetwork) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Network',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _network,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.cell_tower_rounded),
                    ),
                    hint: const Text(
                      'Choose network',
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: networks.valueOrNull
                        ?.map(
                          (n) => DropdownMenuItem(
                            value: n.id,
                            child: Text(
                              n.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() {
                      _network = value;
                      _bundle = null;
                    }),
                  ),
                ],
                if (_needsCountry) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Recipient country',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _country,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.public_rounded),
                    ),
                    hint: const Text(
                      'Choose country',
                      overflow: TextOverflow.ellipsis,
                    ),
                    items: countries.valueOrNull
                        ?.map(
                          (n) => DropdownMenuItem(
                            value: n.id,
                            child: Text(
                              n.name,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => setState(() => _country = value),
                  ),
                ],
                if (widget.flow == ServiceFlow.data && _network != null) ...[
                  const SizedBox(height: 18),
                  Text(
                    'Data bundle',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 10),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 10,
                          crossAxisSpacing: 10,
                          childAspectRatio: 1.55,
                        ),
                    itemCount: bundles?.valueOrNull?.length ?? 0,
                    itemBuilder: (context, index) {
                      final bundle = bundles!.valueOrNull![index];
                      return _BundleCard(
                        bundle: bundle,
                        selected: _bundle == bundle,
                        onTap: () => setState(() => _bundle = bundle),
                      );
                    },
                  ),
                ],
                if (widget.flow != ServiceFlow.data) ...[
                  const SizedBox(height: 18),
                  Text('Amount', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 10),
                  if (widget.flow == ServiceFlow.globalAirtime) ...[
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _globalPresets
                          .map(
                            (value) => AmountPresetChip(
                              value: value,
                              selected:
                                  double.tryParse(_amount.text.trim()) == value,
                              onTap: () => setState(
                                () => _amount.text = value.toStringAsFixed(0),
                              ),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: 12),
                  ],
                  TextFormField(
                    controller: _amount,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.currency_exchange_rounded),
                      hintText: '0.00',
                    ),
                    validator: (v) =>
                        (double.tryParse(v?.trim() ?? '') ?? 0) > 0
                        ? null
                        : 'Enter an amount.',
                  ),
                ],
                if (widget.flow == ServiceFlow.gtPay) ...[
                  const SizedBox(height: 18),
                  Text(
                    widget.flow == ServiceFlow.gtPay
                        ? 'Remarks'
                        : 'Description',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _description,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.notes_rounded),
                      hintText: 'What is this for?',
                    ),
                  ),
                ],
                const SizedBox(height: 28),
                AppButton(
                  label: _submitLabel,
                  loading: _submitting,
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                  ),
                  onPressed: _submitting ? null : _submit,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String get _submitLabel => switch (widget.flow) {
    ServiceFlow.airtime => 'Send airtime',
    ServiceFlow.data => 'Buy data bundle',
    ServiceFlow.globalAirtime => 'Send global airtime',
    ServiceFlow.qrPay => 'Pay merchant',
    ServiceFlow.gtPay => 'Pay with GTPay',
  };
  String get _flowDescription => switch (widget.flow) {
    ServiceFlow.airtime => 'Instant Ghana top-ups through Prymo.',
    ServiceFlow.data => 'Choose a bundle for any Ghanaian network.',
    ServiceFlow.globalAirtime => 'International top-ups powered by Reloadly.',
    ServiceFlow.qrPay => 'Enter a merchant code to pay from your wallet.',
    ServiceFlow.gtPay => 'Pay GTBank bills and services. The recipient is verified before the payment goes out.',
  };
}

class _BundleCard extends StatelessWidget {
  const _BundleCard({
    required this.bundle,
    required this.selected,
    required this.onTap,
  });

  final DataBundle bundle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: 0.12)
              : scheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? scheme.primary
                : (isDark ? Colors.white12 : const Color(0xFFECEAF4)),
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Icon(
                  selected
                      ? Icons.check_circle_rounded
                      : Icons.sim_card_outlined,
                  size: 20,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
                Text(
                  Formatters.currency(bundle.price),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const Spacer(),
            Text(
              bundle.dataAmount,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
            Text(
              bundle.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataCountry {
  const _DataCountry({
    required this.name,
    required this.dialCode,
    required this.isoCode,
    this.flagUrl,
    required this.currency,
  });

  final String name;
  final String dialCode;
  final String isoCode;

  /// Flag image URL — from the Reloadly country list or derived from
  /// [isoCode] via flagcdn when absent.
  final String? flagUrl;
  final String currency;

  _DataCountry copyWithDialCode(String dialCode) => _DataCountry(
    name: name,
    dialCode: dialCode,
    isoCode: isoCode,
    flagUrl: flagUrl,
    currency: currency,
  );
}

/// 5-step Enhanced Internet Data wizard (`Country` → `Network` → `Phone` →
/// `Bundle` → `Confirm`) with the `Confirm Operating Network` sheet and
/// `Available Bundles` plan cards.
class _EnhancedInternetDataWizard extends ConsumerStatefulWidget {
  const _EnhancedInternetDataWizard({this.funding = ServiceFunding.momo});

  final ServiceFunding funding;

  @override
  ConsumerState<_EnhancedInternetDataWizard> createState() =>
      _EnhancedInternetDataWizardState();
}

class _EnhancedInternetDataWizardState
    extends ConsumerState<_EnhancedInternetDataWizard>
    with WidgetsBindingObserver {
  static const _countries = <_DataCountry>[
    _DataCountry(
      name: 'Ghana',
      dialCode: '+233',
      isoCode: 'GH',
      currency: 'GHS',
    ),
    _DataCountry(
      name: 'Nigeria',
      dialCode: '+234',
      isoCode: 'NG',
      currency: 'NGN',
    ),
    _DataCountry(
      name: 'Kenya',
      dialCode: '+254',
      isoCode: 'KE',
      currency: 'KES',
    ),
    _DataCountry(
      name: 'South Africa',
      dialCode: '+27',
      isoCode: 'ZA',
      currency: 'ZAR',
    ),
    _DataCountry(
      name: 'Tanzania',
      dialCode: '+255',
      isoCode: 'TZ',
      currency: 'TZS',
    ),
    _DataCountry(
      name: 'Uganda',
      dialCode: '+256',
      isoCode: 'UG',
      currency: 'UGX',
    ),
    _DataCountry(
      name: 'India',
      dialCode: '+91',
      isoCode: 'IN',
      currency: 'INR',
    ),
    _DataCountry(
      name: 'United Kingdom',
      dialCode: '+44',
      isoCode: 'GB',
      currency: 'GBP',
    ),
    _DataCountry(
      name: 'United States',
      dialCode: '+1',
      isoCode: 'US',
      currency: 'USD',
    ),
    _DataCountry(
      name: 'Afghanistan',
      dialCode: '+93',
      isoCode: 'AF',
      currency: 'AFN',
    ),
    _DataCountry(
      name: 'Albania',
      dialCode: '+355',
      isoCode: 'AL',
      currency: 'ALL',
    ),
    _DataCountry(
      name: 'Algeria',
      dialCode: '+213',
      isoCode: 'DZ',
      currency: 'DZD',
    ),
  ];

  static const _prefixBrands = <String, String>{
    '024': 'MTN',
    '025': 'MTN',
    '053': 'MTN',
    '054': 'MTN',
    '055': 'MTN',
    '059': 'MTN',
    '24': 'MTN',
    '25': 'MTN',
    '53': 'MTN',
    '54': 'MTN',
    '55': 'MTN',
    '59': 'MTN',
    '020': 'Telecel',
    '050': 'Telecel',
    '20': 'Telecel',
    '50': 'Telecel',
    '026': 'AirtelTigo',
    '027': 'AirtelTigo',
    '056': 'AirtelTigo',
    '057': 'AirtelTigo',
    '26': 'AirtelTigo',
    '27': 'AirtelTigo',
    '56': 'AirtelTigo',
    '57': 'AirtelTigo',
    '023': 'Glo',
    '23': 'Glo',
  };

  /// Normal purchases begin at country selection; Lida Value USE starts on
  /// the phone step because its destination is locked to the user's Ghana
  /// line. Steps: 1 Country, 2 Network, 3 Phone, 4 Bundle/Amount, 5 Confirm —
  /// the same five the Airtime wizard runs. The Network step is reached only
  /// as an explicit edit: forward navigation answers it by detection like
  /// the legacy wizard.
  late int _step = widget.funding == ServiceFunding.lidaValueUse ? 3 : 1;

  /// Mutable copy of `widget.funding` — an insufficient Lida Value balance
  /// flips the run back to the momo checkout without leaving the wizard.
  late ServiceFunding _funding = widget.funding;
  _DataCountry _selectedCountry = _countries.first;
  String _countryQuery = '';
  bool _didAutoSelectCountry = false;

  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _countrySearch = TextEditingController();
  String? _networkId;

  /// Set when the user names the network on the Network step. A locked pick
  /// survives detection and edits to the number — autodetect may suggest a
  /// correction, never silently overwrite the choice.
  bool _networkLocked = false;
  DataBundle? _selectedBundle;
  bool _showAllBundles = false;
  bool _showAllQuickAmounts = false;
  static const int _initialQuickAmountCount = 6;
  bool _submitting = false;
  ServiceReceipt? _receipt;

  /// Live Reloadly data operator detection (non-Ghana) — `_detectSeq` drops
  /// stale responses when the user keeps typing.
  DetectedOperator? _detectedOperator;
  bool _manualNetwork = false;
  bool _detecting = false;
  String? _detectError;
  Timer? _detectDebounce;
  int _detectSeq = 0;

  /// Ghana ported-number sheet opens only when the user asks for it —
  /// nothing pops up automatically while they type.
  bool _networkSheetShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.funding == ServiceFunding.lidaValueUse) {
      // Lida Value USE is a Ghana self-top-up — lock the country and
      // prefill the user's own number.
      _selectedCountry = _countries.firstWhere(
        (c) => c.isoCode == 'GH',
        orElse: () => _countries.first,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final phone = ref.read(authSessionProvider)?.user.phoneNumber;
        if (phone != null && _phone.text.isEmpty) {
          _phone.text = _localNumberFor(
            _selectedCountry,
            phone.replaceAll(RegExp(r'\D'), ''),
          );
          _detectOperator();
        }
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyUserDefaults());
    }
  }

  List<_DataCountry> _mergedCountries(List<ServiceOption>? live) {
    final merged = List<_DataCountry>.of(_countries);
    final known = {for (final country in _countries) country.isoCode};
    for (final option in live ?? const <ServiceOption>[]) {
      if (option.id.length != 2 || known.contains(option.id)) continue;
      final currency = RegExp(r'^[A-Z]{3}$').hasMatch(option.meta ?? '')
          ? option.meta!
          : 'USD';
      merged.add(
        _DataCountry(
          name: option.name,
          dialCode: option.dialCode ?? '',
          isoCode: option.id,
          flagUrl: option.flagUrl,
          currency: currency,
        ),
      );
    }
    return merged;
  }

  void _applyUserDefaults() {
    if (!mounted) return;
    final user = ref.read(authSessionProvider)?.user;
    if (user == null) return;
    final countries = _mergedCountries(ref.read(countriesProvider).valueOrNull);
    _autoSelectUserCountry(countries);
    // The phone field starts empty — the recipient is typed or filled via
    // "Use My Number", which is what triggers operator detection.
  }

  /// `GET /reloadly/country-list` returns no `callingCodes`, so countries
  /// merged from the API arrive with an empty dial code. Resolve it lazily
  /// through `POST /reloadly/find-country-by-code` on selection.
  Future<void> _resolveCountryDialCode(_DataCountry country) async {
    if (country.dialCode.isNotEmpty) return;
    final detail = await ref
        .read(servicesRepositoryProvider)
        .findCountryByCode(country.isoCode);
    if (!mounted || detail?.dialCode == null) return;
    if (_selectedCountry.isoCode != country.isoCode) return;
    setState(
      () => _selectedCountry = _selectedCountry.copyWithDialCode(
        detail!.dialCode!,
      ),
    );
  }

  void _autoSelectUserCountry(List<_DataCountry> countries) {
    if (_didAutoSelectCountry) return;
    final userCountry =
        ref.read(authSessionProvider)?.user.country.toUpperCase() ?? '';
    if (userCountry.isEmpty) return;
    for (final country in countries) {
      if (country.isoCode == userCountry ||
          country.name.toUpperCase() == userCountry) {
        _didAutoSelectCountry = true;
        if (country.isoCode != _selectedCountry.isoCode) {
          setState(() {
            _selectedCountry = country;
            _resetNetworkForCountry();
            _amount.clear();
          });
        }
        return;
      }
    }
  }

  String _localNumberFor(_DataCountry country, String rawDigits) {
    var digits = rawDigits;
    final dial = country.dialCode.replaceAll(RegExp(r'\D'), '');
    if (dial.isNotEmpty &&
        digits.startsWith(dial) &&
        digits.length > dial.length) {
      digits = digits.substring(dial.length);
    }
    if (country.isoCode == 'GH' && digits.startsWith('0')) {
      digits = digits.substring(1);
    }
    return digits;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detectDebounce?.cancel();
    _phone.dispose();
    _amount.dispose();
    _countrySearch.dispose();
    super.dispose();
  }

  /// Returning from checkout without a deep link still re-queries the saved
  /// payment token — same resume behavior as the airtime wizard.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(paymentSessionProvider).phase ==
            PaymentPhase.awaitingCallback) {
      ref.read(paymentSessionProvider.notifier).recheck();
    }
  }

  bool get _isGhana => _selectedCountry.isoCode == 'GH';

  /// Ghana submits local `0xxxxxxxxx` numbers to Prymo; Reloadly data
  /// destinations pass raw digits so the repository can expand them through
  /// the country's dial code.
  String get _digits {
    final raw = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (!_isGhana) return raw;
    if (raw.startsWith('233') && raw.length > 9) {
      return '0${raw.substring(3)}';
    }
    if (raw.length == 9 && !raw.startsWith('0')) {
      return '0$raw';
    }
    return raw;
  }

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  /// Reloadly data charges in USD (or the operator's sender currency) and
  /// converts to the destination country's currency via `fx`.
  String get _globalAmountCurrency =>
      _selectedBundle?.currency ??
      _detectedOperator?.senderCurrencyCode ??
      'USD';

  /// Ghana-prefix auto-detection is domestic-only; other countries resolve
  /// the operator through `reloadly-data/auto-detect`.
  String? get _detectedBrand {
    if (!_isGhana) return null;
    final raw = _phone.text.replaceAll(RegExp(r'\D'), '');
    if (raw.startsWith('233') && raw.length >= 5) {
      return _prefixBrands[raw.substring(3, 5)];
    }
    if (raw.length >= 3 && raw.startsWith('0')) {
      return _prefixBrands[raw.substring(0, 3)];
    }
    if (raw.length >= 2) {
      return _prefixBrands[raw.substring(0, 2)];
    }
    return null;
  }

  ServiceOption? _detectedNetwork(List<ServiceOption> networks) {
    final brand = _detectedBrand;
    if (brand == null) return null;
    for (final network in networks) {
      if (network.name.toUpperCase().contains(brand.toUpperCase())) {
        return network;
      }
    }
    return null;
  }

  bool get _hasValidPhone {
    if (_isGhana) {
      final local = _digits;
      return local.length == 10 && local.startsWith('0');
    }
    return _phone.text.replaceAll(RegExp(r'\D'), '').length >= 9;
  }

  /// Ghana requires a Prymo bundle; Reloadly data sells by amount, so step 4
  /// is the bundle grid for GH and an amount entry for every other country.
  bool get _amountInRange =>
      _amountValue > 0 && (_detectedOperator?.accepts(_amountValue) ?? true);

  /// A plan picked from the operator grid is already a valid purchase even
  /// when its price falls outside the *detected* operator's min/max — the user
  /// can browse another operator's catalogue, so the range check only guards
  /// free-form amounts.
  bool get _planOrAmountReady => _selectedBundle != null || _amountInRange;

  bool get _canAdvance => switch (_step) {
    1 => true,
    // The Network step is answered as soon as a network is named — including
    // "auto", which is preselected — so it can never dead-end on a catalogue
    // that failed to load.
    2 => _networkId != null,
    3 => _hasValidPhone && !_detecting,
    4 => _isGhana ? _selectedBundle != null : _planOrAmountReady,
    5 =>
      _hasValidPhone &&
          !_submitting &&
          (_isGhana
              ? _networkId != null && _selectedBundle != null
              : _planOrAmountReady),
    _ => false,
  };

  /// A destination switch invalidates the previous operator — Prymo codes and
  /// Reloadly operator ids must never leak across the route switch.
  void _resetNetworkForCountry() {
    _networkId = _isGhana ? null : 'auto';
    _networkLocked = false;
    _manualNetwork = false;
    _selectedBundle = null;
  }

  /// Network-step pick. `'auto'` defers to detection on the phone step.
  /// Ghana submits a Prymo operator code, so there 'auto' resolves to the
  /// catalogue default and the phone step refreshes it from the number.
  void _pickNetwork(String id, List<ServiceOption> networks) {
    final auto = id == 'auto';
    setState(() {
      _networkId = auto && _isGhana ? _ghanaAutoNetworkId(networks) : id;
      _networkLocked = !auto;
      _manualNetwork = !auto;
      // Bundles and quotes belong to the operator, so both reset with it.
      _selectedBundle = null;
      _amount.clear();
    });
  }

  /// Ghana has no 'auto' operator code — use the network the number's prefix
  /// resolves to, else the first one the Prymo catalogue offers. The phone
  /// step keeps refreshing it while the choice stays unlocked.
  String _ghanaAutoNetworkId(List<ServiceOption> networks) =>
      _detectedNetwork(networks)?.id ??
      (networks.isEmpty ? '4' : networks.first.id);

  void _useMyNumber(String userPhone, List<ServiceOption> networks) {
    _phone.text = _localNumberFor(
      _selectedCountry,
      userPhone.replaceAll(RegExp(r'\D'), ''),
    );
    _onPhoneChanged(networks);
  }

  void _onInternationalNumberPasted(String raw, List<ServiceOption> networks) {
    final clean = raw.startsWith('00')
        ? raw.substring(2)
        : (raw.startsWith('+') ? raw.substring(1) : raw);
    final digits = clean.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    _DataCountry? matched;
    String matchedDial = '';
    for (final c in _countries) {
      final dial = c.dialCode.replaceAll(RegExp(r'\D'), '');
      if (dial.isNotEmpty &&
          digits.startsWith(dial) &&
          dial.length > matchedDial.length) {
        matched = c;
        matchedDial = dial;
      }
    }

    if (matched != null && matched.isoCode != _selectedCountry.isoCode) {
      final newCountry = matched;
      final local = _localNumberFor(newCountry, digits);
      setState(() {
        _selectedCountry = newCountry;
        _phone.value = TextEditingValue(
          text: local,
          selection: TextSelection.collapsed(offset: local.length),
        );
      });
      _onPhoneChanged(networks);
    }
  }

  /// Resolve the phone's operator before the bundle and purchase steps.
  void _onPhoneChanged(List<ServiceOption> networks) {
    final det = _detectedNetwork(networks);
    setState(() {
      // The choice made on the Network step survives edits to the number; only
      // the detection-derived suggestion is refreshed. Clearing it here used to
      // un-answer the step and strand the Ghana submit guard.
      if (!_networkLocked) {
        _networkId = _isGhana ? (det?.id ?? _networkId) : 'auto';
        _manualNetwork = false;
      }
      _selectedBundle = null;
      _amount.clear();
      _detectedOperator = null;
      _detectError = null;
      _detecting = false;
      _networkSheetShown = false;
    });
    _detectSeq++;
    _detectDebounce?.cancel();
    if (_hasValidPhone) {
      _detectDebounce = Timer(
        const Duration(milliseconds: 600),
        () => _detectOperator(networks),
      );
    }
  }

  static const _ghanaBrandToPrymo = <String, String>{
    'MTN': '4',
    'AIRTELTIGO': '1',
    'TELECEL': '6',
    'VODAFONE': '6',
    'GLO': '3',
    'BUSY': '8',
    'SURFLINE': '9',
  };

  Future<void> _detectOperator([List<ServiceOption>? networks]) async {
    if (_isGhana) {
      final detected = _ghanaBrandToPrymo[_detectedBrand?.toUpperCase()];
      setState(() {
        // Never blank a named network with an inconclusive prefix lookup.
        if (!_networkLocked && detected != null) _networkId = detected;
        _detectedOperator = null;
        _detecting = false;
        _detectError = null;
      });
      if (mounted &&
          !_networkLocked &&
          !_networkSheetShown &&
          networks != null &&
          networks.isNotEmpty &&
          _step == 3) {
        _networkSheetShown = true;
        await _showConfirmOperatingNetworkSheet(networks);
      }
      return;
    }

    final requestId = ++_detectSeq;
    setState(() {
      _detecting = true;
      _detectError = null;
    });
    try {
      final operator = await ref
          .read(servicesRepositoryProvider)
          .detectDataOperator(
            phone: _digits,
            countryIsoCode: _selectedCountry.isoCode,
            recipientDialCode: _selectedCountry.dialCode,
          );
      if (!mounted || requestId != _detectSeq) return;
      setState(() {
        _detectedOperator = operator;
        // An explicit pick on the Network step outranks the suggestion.
        if (!_networkLocked) {
          _networkId = '${operator.id}';
          _manualNetwork = false;
        }
        _selectedBundle = null;
        _detecting = false;
      });
    } on ApiException catch (error) {
      if (!mounted || requestId != _detectSeq) return;
      setState(() {
        _detectedOperator = null;
        _detectError = error.message;
        _detecting = false;
      });
    } catch (_) {
      if (!mounted || requestId != _detectSeq) return;
      setState(() {
        _detectedOperator = null;
        _detectError =
            'We could not detect the operator for this number. '
            'Check the phone number and try again.';
        _detecting = false;
      });
    }
  }

  Future<void> _showConfirmOperatingNetworkSheet(
    List<ServiceOption> networks,
  ) async {
    final detected = _detectedNetwork(networks) ?? networks.firstOrNull;
    // Match Airtime: omit `isScrollControlled: true` so the sheet opens
    // halfway up (phone input stays visible above) and the user can scroll
    // or drag it instead of it covering the whole screen.
    final autoId = detected?.id ?? _networkId ?? '4';
    final chosen = await showModalBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ConfirmOperatingNetworkSheet(
        networks: networks,
        autoNetworkId: autoId,
      ),
    );
    if (chosen != null && mounted) {
      // "Auto Detect" on the sheet pops the detected id, so an identical pick
      // defers to detection again; naming any other network is an explicit
      // ported-number correction and locks like the Network step does.
      _pickNetwork(chosen == autoId ? 'auto' : chosen, networks);
    }
  }

  Future<void> _nextStep(List<ServiceOption> networks) async {
    if (!_canAdvance) return;
    if (_step == 1) {
      // Country jumps straight to phone — the network answers itself by
      // detection (Ghana prefix → Prymo code, Reloadly → autodetect), so the
      // Network step only remains as an explicit edit.
      setState(() {
        _networkId ??= _isGhana ? _ghanaAutoNetworkId(networks) : 'auto';
        _step = 3;
      });
      return;
    }
    if (_step < ServiceWizardStepBar.stepCount) {
      setState(() => _step += 1);
      return;
    }
    await _submit();
  }

  void _prevStep() {
    // LV USE starts on the phone step with Ghana locked — its floor is 3.
    final first = widget.funding == ServiceFunding.lidaValueUse ? 3 : 1;
    if (_step > first) {
      setState(() => _step = _step == 3 ? 1 : _step - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  bool _isSelfRecipient(String? userPhone) {
    final myDigits = (userPhone ?? '').replaceAll(RegExp(r'\D'), '');
    if (myDigits.isEmpty) return false;
    final recipientDigits = _digits;
    return myDigits == recipientDigits ||
        myDigits == '233$recipientDigits' ||
        (myDigits.startsWith('233') &&
            '0${myDigits.substring(3)}' == recipientDigits);
  }

  void _invalidateActivityFeeds() {
    ref.invalidate(historyProvider);
    ref.invalidate(historyAnalyticsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(walletSummaryProvider);
    ref.invalidate(lidaPointsProvider);
    ref.invalidate(lidaValueProvider);
  }

  /// Payment-first ordering like the airtime wizard: persist the purchase,
  /// open Advansis checkout, and only credit the bundle after the saved
  /// token verifies. Lida Value funding debits the wallet instead — the
  /// same delivery calls then run without a browser round-trip.
  Future<void> _submit() async {
    if (!_hasValidPhone || _submitting) return;
    if (_isGhana && (_networkId == null || _selectedBundle == null)) return;
    if (!_isGhana && _amountValue <= 0) return;
    final user = ref.read(authSessionProvider)?.user;
    final recipientDigits = _digits;
    var funding = _funding;

    if (funding == ServiceFunding.lidaValueUse &&
        !_isSelfRecipient(user?.phoneNumber)) {
      final asSend = await _confirmUseAsSend(recipientDigits);
      if (asSend == true) {
        funding = ServiceFunding.lidaValueSend;
        _funding = funding;
      } else {
        return;
      }
    }

    setState(() => _submitting = true);
    final isSelf =
        funding == ServiceFunding.lidaValueUse ||
        (_isSelfRecipient(user?.phoneNumber) && !funding.isLidaValue);
    final bundle = _selectedBundle;
    final orderDesc = _isGhana
        ? 'Lidapay data bundle ${bundle?.name ?? ''} for $recipientDigits'
        : 'Lidapay data top-up $_globalAmountCurrency '
              '${_amountValue.toStringAsFixed(2)} for $recipientDigits';
    final clientReference = newClientReference();
    final draft = _isGhana
        ? PendingPayment.ghanaData(
            reference: newPaymentReference(),
            clientReference: clientReference,
            amount: bundle?.price ?? 0,
            recipientNumber: recipientDigits,
            networkId: _networkId!,
            bundleId: bundle?.id ?? '',
            bundleName: bundle?.name ?? '',
            bundleDataAmount: bundle?.dataAmount ?? '',
            saveToLidaValue: false,
            isSelfTopup: isSelf,
            orderDesc: orderDesc,
          )
        : PendingPayment.globalData(
            reference: newPaymentReference(),
            clientReference: clientReference,
            // Charged exactly as Reloadly quotes it (sender currency, e.g.
            // USD) — the fx rate only describes what the recipient receives.
            payAmount: _amountValue,
            payCurrency: _globalAmountCurrency,
            deliverAmount: _amountValue,
            deliverCurrency: _globalAmountCurrency,
            recipientNumber: recipientDigits,
            countryCode: _selectedCountry.isoCode,
            operatorId: (_networkId == null || _networkId == 'auto')
                ? null
                : _networkId,
            operatorName: _detectedOperator?.name,
            recipientDialCode: _selectedCountry.dialCode,
            senderNumber: user?.phoneNumber,
            senderCountryCode: (user?.country ?? '').length == 2
                ? user!.country.toUpperCase()
                : 'GH',
            isSelfTopup: isSelf,
            orderDesc: orderDesc,
          );

    if (funding.isLidaValue) {
      await ref
          .read(lidaValueTopupProvider.notifier)
          .execute(draft: draft, funding: funding, serviceType: 'DATA');
      if (mounted) setState(() => _submitting = false);
      return;
    }

    if (!mounted) return;
    final choice = await showPaymentMethodSheet(
      context: context,
      amountLabel: _isGhana
          ? Formatters.currency(bundle?.price ?? 0)
          : '$_globalAmountCurrency ${_amountValue.toStringAsFixed(2)}',
      orderSummary: 'Internet data · $recipientDigits',
      registeredNumber: user?.contactPhone ?? '',
    );
    if (!mounted || choice == null) {
      if (mounted) setState(() => _submitting = false);
      return;
    }
    final session = ref.read(paymentSessionProvider.notifier);
    final launched = await session.beginPayment(
      draft,
      method: choice.method,
      momoNumber: choice.momoNumber,
    );
    if (mounted) setState(() => _submitting = false);
    if (!launched && mounted) {
      final message = ref.read(paymentSessionProvider).message;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message ?? 'Payment could not be started.')),
      );
    }
  }

  Future<bool?> _confirmUseAsSend(String recipientDigits) => showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Send to another number?'),
      content: Text(
        'USE is only for your own number. $recipientDigits belongs to '
        'someone else — continue as a SEND instead? They may still get the '
        'choice between direct data and Lida Value.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Send instead'),
        ),
      ],
    ),
  );

  void _continueAnotherTransaction() {
    _detectDebounce?.cancel();
    setState(() {
      _receipt = null;
      _step = widget.funding == ServiceFunding.lidaValueUse ? 3 : 1;
      _submitting = false;
      _phone.clear();
      _amount.clear();
      _selectedBundle = null;
      _detectedOperator = null;
      _detectError = null;
      _detecting = false;
      _networkSheetShown = false;
      _resetNetworkForCountry();
    });
    ref.read(paymentSessionProvider.notifier).reset();
    ref.invalidate(lidaValueTopupProvider);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<PaymentSessionState>(paymentSessionProvider, (prev, next) {
      if (!mounted) return;
      // Leave session state intact when `PaymentReturnScreen` is presenting
      // the outcome above this route.
      if (!(ModalRoute.of(context)?.isCurrent ?? true)) {
        if (next.phase == PaymentPhase.completed) _invalidateActivityFeeds();
        return;
      }
      if (next.phase == PaymentPhase.completed && next.receipt != null) {
        setState(() => _receipt = next.receipt);
        ref.read(paymentSessionProvider.notifier).reset();
        _invalidateActivityFeeds();
      } else if (next.phase == PaymentPhase.failed &&
          prev?.phase != PaymentPhase.failed &&
          prev?.phase != PaymentPhase.idle &&
          prev != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.message ?? 'Payment could not be completed.'),
          ),
        );
        ref.read(paymentSessionProvider.notifier).reset();
      }
    });

    // Lida-Value-funded purchases resolve through their own session — the
    // wallet debit is the payment, then delivery lands here the same way.
    ref.listen<LidaTopupState>(lidaValueTopupProvider, (prev, next) {
      if (!mounted) return;
      if (next.phase == LidaTopupPhase.completed && next.receipt != null) {
        setState(() => _receipt = next.receipt);
        _invalidateActivityFeeds();
      } else if (next.phase == LidaTopupPhase.failed &&
          prev?.phase != LidaTopupPhase.failed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              next.message ?? 'Lida Value payment could not be completed.',
            ),
          ),
        );
      }
    });

    if (_receipt case final receipt?) {
      // A parked recipient decision is not a delivery — hand off to the
      // waiting screen which polls the top-up status for the real outcome.
      if (receipt.pendingTopup case final pending?) {
        return PendingTopupScreen(
          pending: pending,
          amountLabel: _isGhana
              ? Formatters.currency(_selectedBundle?.price ?? _amountValue)
              : '$_globalAmountCurrency ${_amountValue.toStringAsFixed(2)}',
          recipientLabel: _digits,
          serviceLabel: 'data',
          icon: Icons.wifi_tethering_rounded,
          onDone: () => Navigator.of(context).pop(),
          onNewTransaction: _continueAnotherTransaction,
        );
      }
      return ServiceReceiptScreen(
        receipt: receipt,
        icon: Icons.wifi_tethering_rounded,
        onDone: () => Navigator.of(context).pop(),
      );
    }

    final paymentActive = ref.watch(
      paymentSessionProvider.select(
        (s) => s.phase != PaymentPhase.idle && s.pending != null,
      ),
    );

    // Ghana needs the Prymo network list; Reloadly destinations only load the
    // country data-operator list once the phone is detected or the user is on
    // the Network/Bundle/Confirm step (matching Lidapay-old).
    final networksAsync = _isGhana
        ? ref.watch(ghanaNetworksProvider)
        : (_step == 2 || _step >= 4 || _detectedOperator != null)
        ? ref.watch(
            internationalDataOperatorsProvider(_selectedCountry.isoCode),
          )
        : const AsyncValue.data(<ServiceOption>[]);
    final networks = networksAsync.valueOrNull ?? const <ServiceOption>[];
    final blockedByCatalogue = _isGhana && !networksAsync.hasValue;
    if (_isGhana) {
      if (networks.isNotEmpty) {
        _networkId ??= _detectedNetwork(networks)?.id ?? networks.first.id;
      }
    } else {
      _networkId ??= 'auto';
    }
    final activeNetworkId = _networkId ?? '4';
    // Prymo bundle codes only exist on the Ghana route; Reloadly data sells by
    // amount, so the provider is never watched for non-GH.
    final bundlesAsync = _isGhana
        ? ref.watch(dataBundlesProvider(activeNetworkId))
        : const AsyncValue<List<DataBundle>>.data(<DataBundle>[]);
    final userPhone =
        ref.watch(authSessionProvider)?.user.phoneNumber ?? '0244588584';
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? AppColors.darkSurface : Colors.white;

    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _PinnedDataHeaderDelegate(
              height:
                  MediaQuery.paddingOf(context).top + (_step == 5 ? 78 : 96),
              title: _step == 5 ? 'Buy Data' : 'Enhanced Internet\nData',
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          SliverToBoxAdapter(
            child: ServiceWizardStepBar(
              currentStep: _step,
              purchaseLabel: 'Bundle',
              reviewLabel: 'Confirm',
              onStepTap: (target) {
                if (target < _step) setState(() => _step = target);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
              child: paymentActive
                  ? const PaymentAwaitingPanel()
                  // The country picker only needs `countriesProvider` — it must
                  // stay usable even while the previous destination's operator
                  // lookup is loading or failing, otherwise a bad country
                  // strands the wizard on an error with no way back.
                  : _step == 1
                  ? _buildCountryStep(isDark, cardBg)
                  : blockedByCatalogue
                  ? networksAsync.when(
                      loading: () => const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: AppSkeletonScreen(),
                      ),
                      error: (error, _) => Column(
                        children: [
                          ErrorView(
                            message: error.toString(),
                            onRetry: () =>
                                ref.invalidate(ghanaNetworksProvider),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: _prevStep,
                              icon: const Icon(Icons.arrow_back_rounded),
                              label: const Text('Choose a different country'),
                            ),
                          ),
                        ],
                      ),
                      data: (_) => const SizedBox.shrink(),
                    )
                  : switch (_step) {
                      2 => _buildNetworkStep(networks),
                      3 => _buildPhoneStep(networks, userPhone, isDark, cardBg),
                      4 =>
                        _isGhana
                            ? _buildBundleStep(
                                bundlesAsync,
                                activeNetworkId,
                                isDark,
                                cardBg,
                              )
                            : _buildGlobalPlanStep(networks, isDark, cardBg),
                      _ => _buildConfirmStep(networks, isDark, cardBg),
                    },
            ),
          ),
        ],
      ),
      bottomNavigationBar: () {
        if (blockedByCatalogue || paymentActive) return null;
        final cost = _isGhana ? (_selectedBundle?.price ?? 0) : _amountValue;
        final confirmLabel = cost > 0
            ? (_funding.isLidaValue
                  ? 'Pay ${cost.toStringAsFixed(2)} LV'
                  : _isGhana
                  ? 'Pay ${Formatters.currency(cost)}'
                  : 'Pay $_globalAmountCurrency ${cost.toStringAsFixed(2)}')
            : 'Pay now';
        return ServiceWizardBottomBar(
          isFinalStep: _step == ServiceWizardStepBar.stepCount,
          confirmLabel: confirmLabel,
          canNext: _canAdvance,
          submitting: _submitting,
          onPrevious: _prevStep,
          onNext: () => _nextStep(networks),
        );
      }(),
    );
  }

  Widget _buildCountryStep(bool isDark, Color cardBg) {
    final scheme = Theme.of(context).colorScheme;
    final countries = _mergedCountries(
      ref.watch(countriesProvider).valueOrNull,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _autoSelectUserCountry(countries);
    });
    final filtered = countries.where((c) {
      // Lida Value USE is a Ghana self-top-up — the debit endpoint only
      // accepts Ghana destination numbers.
      if (_funding == ServiceFunding.lidaValueUse && c.isoCode != 'GH') {
        return false;
      }
      final q = _countryQuery.trim().toLowerCase();
      if (q.isEmpty) return true;
      return c.name.toLowerCase().contains(q) ||
          c.dialCode.contains(q) ||
          c.isoCode.toLowerCase().contains(q);
    }).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Select Country',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Choose the country for your data bundle.',
          style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFEAE8F0),
            ),
          ),
          child: TextField(
            controller: _countrySearch,
            onChanged: (v) => setState(() => _countryQuery = v),
            decoration: InputDecoration(
              hintText: 'Search countries...',
              prefixIcon: Icon(
                Icons.search_rounded,
                color: scheme.onSurfaceVariant,
              ),
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 15,
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final country in filtered) ...[
          _DataCountryCard(
            country: country,
            selected: country.isoCode == _selectedCountry.isoCode,
            isDark: isDark,
            onTap: () {
              final changed = country.isoCode != _selectedCountry.isoCode;
              setState(() {
                // An explicit pick wins over the profile-country auto-select
                // for the rest of this run.
                _didAutoSelectCountry = true;
                _selectedCountry = country;
                if (changed) {
                  // Stale Prymo codes / Reloadly operator ids must never leak
                  // across the route switch.
                  _resetNetworkForCountry();
                  _amount.clear();
                  _phone.clear();
                  _detectedOperator = null;
                  _detectError = null;
                  _detecting = false;
                  _detectDebounce?.cancel();
                  _detectSeq++;
                }
                // The Network step is skipped forward — seed the "auto"
                // default and let phone detection refine it, like legacy.
                _networkId ??= _isGhana
                    ? _ghanaAutoNetworkId(
                        ref.read(ghanaNetworksProvider).valueOrNull ??
                            const <ServiceOption>[],
                      )
                    : 'auto';
                _step = 3;
              });
              // Countries merged from `reloadly/country-list` arrive without a
              // dial code — resolve it before the phone step needs it, or the
              // typed number never expands to a valid Reloadly MSISDN.
              _resolveCountryDialCode(country);
              // Switching countries clears the phone (above) — the user
              // re-enters it or taps "Use My Number" for the new country.
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// Step 2 — the destination's networks. Ghana lists Prymo's data operators
  /// with "Auto Detect" first (resolved from the number on the next step);
  /// every Reloadly destination lists the country catalogue with "Auto Detect"
  /// pinned on top, so an operator lookup that fails still leaves a
  /// selectable, non-blocking choice.
  Widget _buildNetworkStep(List<ServiceOption> networks) {
    final scheme = Theme.of(context).colorScheme;
    if (_isGhana) {
      return ServiceNetworkStep(
        intro: 'Select the network this number operates on.',
        options: [
          const NetworkStepOption(
            id: 'auto',
            label: 'Auto Detect',
            icon: Icons.auto_fix_high_rounded,
            subtitle: 'Match it from the number on the next step',
          ),
          for (final network in networks)
            NetworkStepOption(
              id: network.id,
              label: network.name.replaceAll(' Ghana', ''),
              logoName: network.name,
              subtitle: network.meta,
            ),
        ],
        selectedId: _networkLocked ? _networkId : 'auto',
        onSelected: (option) => _pickNetwork(option.id, networks),
        footer: Text(
          'Ghana numbers can be ported between networks — the phone step lets '
          'you correct the detected one.',
          style: TextStyle(
            fontSize: 12,
            height: 1.35,
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }

    return ServiceNetworkStep(
      intro:
          'Choose the operator for ${_selectedCountry.name}, or match it from '
          'the number.',
      detecting: _detecting,
      options: [
        const NetworkStepOption(
          id: 'auto',
          label: 'Auto Detect',
          icon: Icons.auto_fix_high_rounded,
          subtitle: 'Resolve the operator from the number on the next step',
        ),
        for (final network in networks)
          NetworkStepOption(
            id: network.id,
            label: network.name,
            logoName: network.name,
            subtitle: network.bundles.isEmpty
                ? null
                : '${network.bundles.length} plan'
                      '${network.bundles.length == 1 ? '' : 's'}',
          ),
      ],
      selectedId: _networkId ?? 'auto',
      onSelected: (option) => _pickNetwork(option.id, networks),
      footer: networks.isEmpty
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    'Operator list unavailable — the network will still be '
                    'matched from the number.',
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(
                    internationalDataOperatorsProvider(
                      _selectedCountry.isoCode,
                    ),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            )
          : Text(
              '${networks.length} operator${networks.length == 1 ? '' : 's'} '
              'available for ${_selectedCountry.name}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
    );
  }

  /// Inline "Select Operating Network" card on the phone step — the legacy
  /// ported-number corrector with pills and a Change link that reopens the
  /// confirm sheet. Mirrors the airtime wizard's treatment.
  Widget _buildNetworkConfirmCard(
    List<ServiceOption> networks,
    bool isDark,
    Color cardBg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final detected = _detectedNetwork(networks);
    // The number resolves to a different network than the one named on the
    // Network step: say so and let the pills below correct it. The wizard is
    // never blocked on a detection the user has already overridden.
    final mismatch =
        _networkLocked && detected != null && detected.id != _networkId
        ? '${detected.name.replaceAll(' Ghana', '')} detected — pick it below '
              'if this number was ported.'
        : null;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? AppColors.darkInput : const Color(0xFFF6F6F9),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.network_check_rounded,
                color: AppColors.primary,
                size: 18,
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Select Operating Network',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
              ),
              GestureDetector(
                onTap: () => _showConfirmOperatingNetworkSheet(networks),
                child: const Text(
                  'Change',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Some numbers are ported between networks. Select the correct operating network.',
            style: TextStyle(
              fontSize: 11.5,
              height: 1.35,
              color: scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _networkPill(
                key: 'auto',
                label: 'Auto Detect',
                icon: Icons.auto_fix_high_rounded,
                selected: !_networkLocked,
                isDark: isDark,
                cardBg: cardBg,
                scheme: scheme,
                // Releasing the lock hands the choice back to detection, the
                // same way picking "Auto Detect" on the Network step does.
                onTap: () => _pickNetwork('auto', networks),
              ),
              for (final network in networks)
                _networkPill(
                  key: network.id,
                  label: network.name.replaceAll(' Ghana', ''),
                  icon: Icons.cell_tower_rounded,
                  selected: _networkLocked && _networkId == network.id,
                  isDark: isDark,
                  cardBg: cardBg,
                  scheme: scheme,
                  onTap: () => _pickNetwork(network.id, networks),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (mismatch != null) ...[
            _DataDetectBanner(
              isDark: isDark,
              color: AppColors.primary,
              text: mismatch,
            ),
            const SizedBox(height: 10),
          ],
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${networks.length} data operator${networks.length == 1 ? '' : 's'} available',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _networkPill({
    required String key,
    required String label,
    required IconData icon,
    required bool selected,
    required bool isDark,
    required Color cardBg,
    required ColorScheme scheme,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.12) : cardBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white12 : const Color(0xFFE0DEE8)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: selected ? AppColors.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                color: selected ? AppColors.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhoneStep(
    List<ServiceOption> networks,
    String userPhone,
    bool isDark,
    Color cardBg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final detected = _detectedNetwork(networks);
    final rawUserDigits = userPhone.replaceAll(RegExp(r'\D'), '');
    final dialDigits = _selectedCountry.dialCode.replaceAll(RegExp(r'\D'), '');
    final isMyNumberForSelectedCountry =
        rawUserDigits.isNotEmpty &&
        (_isGhana
            ? (rawUserDigits.startsWith('233') ||
                  rawUserDigits.length == 9 ||
                  rawUserDigits.length == 10)
            : (dialDigits.isNotEmpty && rawUserDigits.startsWith(dialDigits)));
    final formattedMyNumber = userPhone.startsWith('0')
        ? '233${userPhone.substring(1)}'
        : userPhone;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the phone number to receive the data bundle, or tap "Use My Number" below to send it to yourself.',
          style: TextStyle(
            fontSize: 14.5,
            color: scheme.onSurfaceVariant,
            height: 1.45,
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Phone Number',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _step = 1),
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkInput
                            : const Color(0xFFF3F3F6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CountryFlagBadge(
                            isoCode: _selectedCountry.isoCode,
                            flagUrl: _selectedCountry.flagUrl,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            // The dial code resolves lazily; show the ISO code
                            // instead of a blank chip while it is still
                            // unknown.
                            _selectedCountry.dialCode.isEmpty
                                ? _selectedCountry.isoCode
                                : _selectedCountry.dialCode,
                            style: TextStyle(
                              fontSize: 15.5,
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Container(
                      height: 54,
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      decoration: BoxDecoration(
                        color: isDark
                            ? AppColors.darkInput
                            : const Color(0xFFF3F3F6),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: TextField(
                        controller: _phone,
                        textAlignVertical: TextAlignVertical.center,
                        scrollPadding: EdgeInsets.zero,
                        onChanged: (_) => _onPhoneChanged(networks),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          PhoneNumberInputFormatter(
                            dialCode: _selectedCountry.dialCode,
                            isoCode: _selectedCountry.isoCode,
                            onInternationalPaste: (raw) =>
                                _onInternationalNumberPasted(raw, networks),
                          ),
                        ],
                        style: TextStyle(
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          height: 1.25,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter phone ...',
                          hintStyle: TextStyle(
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.6,
                            ),
                            fontWeight: FontWeight.w500,
                          ),
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          filled: false,
                          isDense: true,
                          contentPadding: EdgeInsets.zero,
                          suffixIconConstraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                            maxWidth: 36,
                            maxHeight: 36,
                          ),
                          suffixIcon: _phone.text.isNotEmpty
                              ? IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  splashRadius: 18,
                                  onPressed: () {
                                    setState(() => _phone.clear());
                                    _onPhoneChanged(networks);
                                  },
                                  icon: Icon(
                                    Icons.close_rounded,
                                    size: 20,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (isMyNumberForSelectedCountry) ...[
                const SizedBox(height: 16),
                InkWell(
                  onTap: () => _useMyNumber(userPhone, networks),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: AppColors.primary.withValues(alpha: 0.65),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.person_rounded,
                          size: 18,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Use My Number ($formattedMyNumber)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 15,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _isGhana
                          ? 'For Ghana, enter the local number (e.g. 0244123456 or 244123456)'
                          : _selectedCountry.dialCode.isEmpty
                          ? 'For ${_selectedCountry.name}, enter the full international number'
                          : 'For ${_selectedCountry.name}, enter the local number or ${_selectedCountry.dialCode} format',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_detectedBrand != null) ...[
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () => _showConfirmOperatingNetworkSheet(networks),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF33B457).withValues(alpha: 0.14)
                    : const Color(0xFFEAF7EE),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: const Color(0xFF33B457).withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF33B457),
                    size: 22,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${detected?.name ?? '$_detectedBrand Ghana'} detected',
                          style: const TextStyle(
                            color: Color(0xFF2E9E4F),
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Tap to confirm or change ported network',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.swap_horiz_rounded,
                    color: Color(0xFF2E9E4F),
                  ),
                ],
              ),
            ),
          ),
        ],
        // Detection feedback runs for every country (legacy _buildLoadingIndicator,
        // _buildOperatorInfo, _buildError); Ghana adds the ported-number
        // network confirmation below it.
        if (_detecting) ...[
          const SizedBox(height: 14),
          _DataDetectBanner(
            isDark: isDark,
            color: AppColors.primary,
            text: 'Detecting network…',
            showSpinner: true,
          ),
        ] else if (_detectedOperator != null) ...[
          const SizedBox(height: 14),
          _DataDetectBanner(
            isDark: isDark,
            color: const Color(0xFF33B457),
            text:
                '${_detectedOperator!.name} detected · ${_selectedCountry.name}',
            leading: OperatorLogoBadge(
              name: _detectedOperator!.name,
              logoUrl: _detectedOperator!.logoUrl,
              size: 28,
            ),
          ),
        ] else if (_detectError != null) ...[
          const SizedBox(height: 14),
          _DataDetectBanner(
            isDark: isDark,
            color: const Color(0xFFE5484D),
            text: _detectError!,
            error: true,
          ),
        ],
        if (_isGhana && _hasValidPhone) ...[
          const SizedBox(height: 14),
          _buildNetworkConfirmCard(networks, isDark, cardBg),
        ],
      ],
    );
  }

  /// Reloadly data operators carry fixed plans (`fixedAmounts`/
  /// `localFixedAmounts` + descriptions) — render them as bundle cards like
  /// the legacy app. Operators without fixed plans fall back to amount entry.
  Widget _buildGlobalPlanStep(
    List<ServiceOption> networks,
    bool isDark,
    Color cardBg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    // Operators with fixed plans first — those are the purchasable ones.
    // Prefer the operator auto-detected from the recipient number (e.g.
    // MTN Nigeria); a still-'auto' id must not default to the first list
    // entry, which showed the wrong operator's plans.
    final withBundles = networks.where((n) => n.bundles.isNotEmpty).toList();
    final detectedId = _detectedOperator?.id.toString();
    // Detected operator leads the list so the user's own network is the
    // default; others stay available as alternatives.
    if (detectedId != null) {
      withBundles.sort((a, b) {
        final aw = a.id == detectedId ? 0 : 1;
        final bw = b.id == detectedId ? 0 : 1;
        return aw.compareTo(bw);
      });
    }
    final userPicked = withBundles.any((n) => n.id == _networkId);
    final active = withBundles.isEmpty
        ? null
        : withBundles.firstWhere(
            (n) => detectedId != null && !_manualNetwork
                ? n.id == detectedId
                : (userPicked ? n.id == _networkId : n.id == detectedId),
            orElse: () => withBundles.first,
          );
    if (active == null) return _buildGlobalAmountStep(isDark, cardBg);
    final bundles = active.bundles;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Data Bundle',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          active.id == detectedId
              ? '${bundles.length} plans for ${active.name} · matched to your number'
              : '${bundles.length} plans for ${_selectedCountry.name}',
          style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        if (withBundles.length > 1) ...[
          SizedBox(
            height: 42,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: withBundles.length,
              separatorBuilder: (_, _) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final op = withBundles[i];
                final selected = op.id == active.id;
                return GestureDetector(
                  // Same route as the Network step, so the pick locks and the
                  // operator's own plans/bundles reset together.
                  onTap: () => _pickNetwork(op.id, networks),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.primary.withValues(alpha: 0.18)
                          : cardBg,
                      borderRadius: BorderRadius.circular(21),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : (isDark
                                  ? Colors.white12
                                  : const Color(0xFFE5E3EC)),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        OperatorLogoBadge(
                          name: op.name,
                          logoUrl: op.id == detectedId
                              ? _detectedOperator?.logoUrl
                              : null,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          op.name,
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: selected
                                ? AppColors.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
        ],
        for (final bundle in bundles) ...[
          _DataPlanCard(
            bundle: bundle,
            convertedLabel:
                _detectedOperator?.paymentAmount(bundle.price) != null &&
                    _detectedOperator?.fxCurrencyCode != null
                ? '≈ ${_detectedOperator!.fxCurrencyCode} '
                      '${_detectedOperator!.paymentAmount(bundle.price)!.toStringAsFixed(2)}'
                : null,
            selected: _selectedBundle == bundle,
            cardBg: cardBg,
            isDark: isDark,
            onTap: () => setState(() {
              _networkId = active.id;
              _selectedBundle = bundle;
              _amount.text = bundle.price.toStringAsFixed(2);
            }),
          ),
          const SizedBox(height: 14),
        ],
      ],
    );
  }

  /// Reloadly data sells by amount rather than fixed `dataCode` bundles, so
  /// non-Ghana destinations get an amount entry instead of the Prymo grid.
  Widget _buildGlobalAmountStep(bool isDark, Color cardBg) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter Amount',
          style: Theme.of(context).textTheme.titleLarge
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          'Reloadly data for ${_selectedCountry.name} is purchased by amount in $_globalAmountCurrency.',
          style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFECEAF2),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                height: 60,
                decoration: BoxDecoration(
                  color: isDark ? AppColors.darkInput : const Color(0xFFF3F3F6),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isDark ? Colors.white12 : const Color(0xFFE2E0E8),
                  ),
                ),
                alignment: Alignment.center,
                child: TextField(
                  controller: _amount,
                  onChanged: (_) => setState(() {}),
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
                  ],
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                  decoration: InputDecoration(
                    hintText: '0',
                    hintStyle: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                [
                  _detectedOperator?.rangeLabel ??
                      'Charged in $_globalAmountCurrency via Reloadly',
                  if (_detectedOperator?.fxRate != null &&
                      _detectedOperator?.fxCurrencyCode != null)
                    '1 $_globalAmountCurrency ≈ '
                        '${_detectedOperator!.fxRate!.toStringAsFixed(2)} '
                        '${_detectedOperator!.fxCurrencyCode}',
                ].join('  •  '),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (_amountValue > 0) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    _globalPayBanner,
                    style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        _buildGlobalQuickAmountsSection(isDark, cardBg, scheme),
      ],
    );
  }

  /// Amount-step banner: the charge is the quoted Reloadly figure as-is;
  /// the fx rate only describes what lands on the recipient's phone.
  String get _globalPayBanner {
    final fx = _detectedOperator?.paymentAmount(_amountValue);
    final fxCode = _detectedOperator?.fxCurrencyCode;
    return 'You will pay $_globalAmountCurrency '
        '${_amountValue.toStringAsFixed(2)}'
        '${fx == null || fxCode == null ? '' : ' · recipient gets ≈ $fxCode ${fx.toStringAsFixed(2)}'}';
  }

  Widget _buildGlobalQuickAmountsSection(
    bool isDark,
    Color cardBg,
    ColorScheme scheme,
  ) {
    final quickAmounts = _detectedOperator?.quickAmounts() ?? const <double>[];
    if (quickAmounts.isEmpty) return const SizedBox.shrink();

    final hasMore = quickAmounts.length > _initialQuickAmountCount;
    final displayedAmounts = _showAllQuickAmounts || !hasMore
        ? quickAmounts
        : quickAmounts.take(_initialQuickAmountCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 18),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Quick Amounts',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              ),
            ),
            if (hasMore)
              GestureDetector(
                onTap: () => setState(
                  () => _showAllQuickAmounts = !_showAllQuickAmounts,
                ),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                    horizontal: 2,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showAllQuickAmounts
                            ? 'Show less'
                            : 'View all (${quickAmounts.length})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _showAllQuickAmounts
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        size: 18,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossAxisCount = constraints.maxWidth > 500 ? 4 : 3;
            const spacing = 10.0;
            const itemHeight = 48.0;
            final itemWidth =
                (constraints.maxWidth - (crossAxisCount - 1) * spacing) /
                crossAxisCount;
            final aspectRatio = itemWidth / itemHeight;

            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: displayedAmounts.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemBuilder: (context, index) {
                final value = displayedAmounts[index];
                final selected = _amountValue == value;
                return GestureDetector(
                  onTap: () =>
                      setState(() => _amount.text = value.toStringAsFixed(0)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: selected ? AppColors.brandGradient : null,
                      color: selected ? null : cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : (isDark
                                  ? Colors.white12
                                  : const Color(0xFFE5E3EC)),
                        width: selected ? 1.5 : 1,
                      ),
                    ),
                    child: Text(
                      '$_globalAmountCurrency ${value.toStringAsFixed(0)}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: selected ? Colors.white : scheme.onSurface,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        if (hasMore) ...[
          const SizedBox(height: 12),
          GestureDetector(
            onTap: () =>
                setState(() => _showAllQuickAmounts = !_showAllQuickAmounts),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: cardBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDark ? Colors.white12 : const Color(0xFFE5E3EC),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    _showAllQuickAmounts
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _showAllQuickAmounts
                        ? 'Show less'
                        : 'More amounts (${quickAmounts.length - _initialQuickAmountCount} more)',
                    style: const TextStyle(
                      color: AppColors.primary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBundleStep(
    AsyncValue<List<DataBundle>> bundlesAsync,
    String activeNetworkId,
    bool isDark,
    Color cardBg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return bundlesAsync.when(
      loading: () => const Column(
        children: [
          AppSkeleton(height: 120, borderRadius: 20),
          SizedBox(height: 12),
          AppSkeleton(height: 120, borderRadius: 20),
          SizedBox(height: 12),
          AppSkeleton(height: 120, borderRadius: 20),
        ],
      ),
      error: (err, _) => ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(dataBundlesProvider(activeNetworkId)),
      ),
      data: (bundles) {
        const initialLimit = 5;
        final visibleBundles = _showAllBundles || bundles.length <= initialLimit
            ? bundles
            : bundles.take(initialLimit).toList();
        final remainingCount = bundles.length - initialLimit;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose Data Bundle',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'Choose the data plan that suits your needs.',
              style: TextStyle(fontSize: 14.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Text(
                  'Available Bundles',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: scheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${bundles.length} plans',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            for (final bundle in visibleBundles) ...[
              _DataPlanCard(
                bundle: bundle,
                selected: _selectedBundle == bundle,
                cardBg: cardBg,
                isDark: isDark,
                onTap: () => setState(() => _selectedBundle = bundle),
              ),
              const SizedBox(height: 14),
            ],
            if (bundles.length > initialLimit)
              GestureDetector(
                onTap: () => setState(() => _showAllBundles = !_showAllBundles),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: isDark ? Colors.white12 : const Color(0xFFE5E3EC),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _showAllBundles
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: AppColors.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _showAllBundles
                            ? 'Show fewer plans'
                            : 'Show more ($remainingCount more plans)',
                        style: const TextStyle(
                          color: AppColors.primary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildConfirmStep(
    List<ServiceOption> networks,
    bool isDark,
    Color cardBg,
  ) {
    final network = networks.firstWhere(
      (n) => n.id == _networkId,
      orElse: () => ServiceOption(
        id: _isGhana ? '4' : 'auto',
        name:
            _detectedOperator?.name ?? (_isGhana ? 'MTN Ghana' : 'Auto-detect'),
      ),
    );
    final bundle = _selectedBundle;
    final dialDigits = _selectedCountry.dialCode.replaceAll(RegExp(r'\D'), '');
    final localDigits = _digits.startsWith('0')
        ? _digits.substring(1)
        : _digits;
    final intlPhone = _isGhana
        ? (localDigits.startsWith('233') ? localDigits : '233$localDigits')
        // Without a dial code there is nothing to prefix — show the number as
        // typed instead of a bare national number posing as an international
        // MSISDN.
        : dialDigits.isEmpty
        ? _digits
        : (_digits.startsWith(dialDigits)
              ? _digits
              : '$dialDigits$localDigits');
    final cost = _isGhana ? (bundle?.price ?? 0) : _amountValue;
    // The charge is quoted in the operator's sender currency, so label it with
    // the same code the payment draft carries.
    final totalLabel = _funding.isLidaValue
        ? '${cost.toStringAsFixed(2)} LV'
        : _isGhana
        ? Formatters.currency(cost)
        : '$_globalAmountCurrency ${cost.toStringAsFixed(2)}';
    final fxPaid = !_isGhana && _amountValue > 0
        ? _detectedOperator?.paymentAmount(_amountValue)
        : null;
    // The converted figure is denominated in fxCurrencyCode (e.g. NGN) —
    // label it with that code, never the sender's symbol ('$').
    final fxCode = _detectedOperator?.fxCurrencyCode ?? 'GHS';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TopupReviewCard(
          serviceLabel: 'Data',
          // Ghana bundles lead with the size; the price is the only charge
          // line. Global data sells by amount, so the amount is the hero.
          heroValue: _isGhana ? (bundle?.dataAmount ?? 'Data') : totalLabel,
          heroCaption: _isGhana
              ? 'No expiry'
              : (fxPaid != null
                    ? '${bundle != null ? '${bundle.dataAmount} · ' : ''}'
                          '≈ $fxCode ${fxPaid.toStringAsFixed(2)}'
                    : bundle?.dataAmount),
          networkName: network.name,
          countryName: _selectedCountry.name,
          countryFlag: _selectedCountry.isoCode,
          countryFlagUrl: _selectedCountry.flagUrl,
          operatorLogoUrl: _detectedOperator?.logoUrl ?? network.flagUrl,
          recipientPhone: intlPhone,
          isSelf: _isSelfRecipient(
            ref.watch(authSessionProvider)?.user.phoneNumber,
          ),
          deliveryNote:
              _isSelfRecipient(ref.watch(authSessionProvider)?.user.phoneNumber)
              ? 'Delivered instantly to your line once payment is confirmed.'
              : 'Recipient can take the data bundle now or save it as Lida Value.',
          payWith: _funding.isLidaValue ? null : 'MoMo or Card · choose next',
          payAmount: _isGhana
              ? totalLabel
              : (fxPaid == null
                    ? null
                    : '$_globalAmountCurrency ${_amountValue.toStringAsFixed(2)} · '
                          'recipient gets ≈ $fxCode ${fxPaid.toStringAsFixed(2)}'),
          amountRowLabel: _isGhana || bundle != null ? 'Bundle' : 'Amount',
          amountRowValue: _isGhana
              ? '${bundle?.name ?? 'Data bundle'} · ${bundle?.dataAmount ?? ''}'
              : [
                  if (bundle != null) bundle.dataAmount,
                  totalLabel,
                  if (fxPaid != null)
                    '(≈ $fxCode ${fxPaid.toStringAsFixed(2)})',
                ].join(' · '),
          onChangeCountry: _funding == ServiceFunding.lidaValueUse
              ? null
              : () => setState(() => _step = 1),
          onChangeRecipient: () => setState(() => _step = 3),
          onChangeNetwork: () => setState(() => _step = 2),
          onChangeAmount: () => setState(() => _step = 4),
        ),
        const SizedBox(height: 16),
        ..._fundingAndEligibilityCards(),
      ],
    );
  }

  /// SEND/USE are Lida Value menu actions, so the wallet is what pays. The
  /// balance falling short is the only reason to leave that rail, and doing so
  /// changes how the user is charged — so ask first, never flip silently.
  Future<void> _switchToStandardCheckout() async {
    final confirmed = await confirmStandardCheckoutSwitch(
      context,
      serviceLabel: 'data',
    );
    if (!mounted || !confirmed) return;
    setState(() => _funding = ServiceFunding.momo);
  }

  /// The detour is reversible: a run that started on the Lida Value menu can
  /// go back to wallet funding — again only after the user says so.
  Future<void> _restoreLidaValueFunding() async {
    final wallet = ref.read(lidaValueProvider).valueOrNull;
    final confirmed = await confirmLidaValueRestore(
      context,
      serviceLabel: 'data',
      balanceLabel: wallet == null
          ? 'checking balance'
          : '${wallet.balance.toStringAsFixed(2)} LV',
    );
    if (!mounted || !confirmed) return;
    setState(() => _funding = widget.funding);
  }

  /// Confirm-step notices: the Lida Value funding chip (with a balance
  /// shortfall warning + a switch to the standard momo/card checkout) and the
  /// recipient-choice hint when the destination is a registered account.
  List<Widget> _fundingAndEligibilityCards() {
    final cards = <Widget>[];
    final user = ref.watch(authSessionProvider)?.user;

    if (_funding.isLidaValue) {
      final wallet = ref.watch(lidaValueProvider).valueOrNull;
      final cost = _isGhana ? (_selectedBundle?.price ?? 0) : _amountValue;
      final short = wallet != null && cost > wallet.balance;
      cards.add(
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 4),
          decoration: BoxDecoration(
            color: AppColors.violet.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.violet.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              const Icon(Icons.diamond_rounded, color: AppColors.violet),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _funding == ServiceFunding.lidaValueUse
                          ? 'Paying with Lida Value'
                          : 'Sending with Lida Value',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      wallet == null
                          ? 'Balance: checking…'
                          : 'Balance: ${wallet.balance.toStringAsFixed(2)} LV',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: short
                            ? AppColors.error
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: short ? FontWeight.w700 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              if (short)
                TextButton(
                  onPressed: _switchToStandardCheckout,
                  child: const Text('Pay another way'),
                ),
            ],
          ),
        ),
      );
    } else if (widget.funding.isLidaValue) {
      // The run began on the Lida Value menu and detoured to the standard
      // checkout — keep a route back to the wallet.
      cards.add(
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _restoreLidaValueFunding,
            icon: const Icon(
              Icons.diamond_rounded,
              size: 18,
              color: AppColors.violet,
            ),
            label: const Text('Pay from Lida Value instead'),
          ),
        ),
      );
    }

    // Recipient-choice hint — non-blocking preflight, only for other
    // people's numbers.
    if (_hasValidPhone && !_isSelfRecipient(user?.phoneNumber)) {
      final eligibility = ref.watch(
        recipientEligibilityProvider((
          phone: _digits,
          service: 'DATA',
          iso: _selectedCountry.isoCode,
        )),
      );
      if (eligibility.valueOrNull?.willPromptRecipient == true) {
        cards.add(
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.primary.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '$_digits is a Lidapay user — they\'ll be asked to take '
                    'this data now or save it to Lida Value.',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    if (cards.isNotEmpty) cards.add(const SizedBox(height: 12));
    return cards;
  }
}

class _DataWizardHeader extends StatelessWidget {
  const _DataWizardHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 12,
        20,
        18,
      ),
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: IconButton(
              onPressed: onBack,
              tooltip: 'Back',
              padding: EdgeInsets.zero,
              icon: const Icon(
                Icons.arrow_back_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 21,
                fontWeight: FontWeight.w800,
                height: 1.2,
                letterSpacing: -0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedDataHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedDataHeaderDelegate({
    required this.height,
    required this.title,
    required this.onBack,
  });

  final double height;
  final String title;
  final VoidCallback onBack;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final isStuck = shrinkOffset > 0 || overlapsContent;
    return DecoratedBox(
      decoration: BoxDecoration(
        boxShadow: isStuck
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.22),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: SizedBox.expand(
        child: _DataWizardHeader(title: title, onBack: onBack),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedDataHeaderDelegate oldDelegate) {
    return oldDelegate.title != title || oldDelegate.height != height;
  }
}

class _DataCountryCard extends StatelessWidget {
  const _DataCountryCard({
    required this.country,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final _DataCountry country;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: selected
              ? LinearGradient(
                  colors: [
                    AppColors.primary.withValues(alpha: isDark ? 0.25 : 0.16),
                    AppColors.primary.withValues(alpha: isDark ? 0.14 : 0.08),
                  ],
                )
              : null,
          color: selected
              ? null
              : (isDark ? AppColors.darkSurface : Colors.white),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isDark ? AppColors.darkInput : const Color(0xFFF6F5FA),
                borderRadius: BorderRadius.circular(12),
              ),
              alignment: Alignment.center,
              child: CountryFlagBadge(
                isoCode: country.isoCode,
                flagUrl: country.flagUrl,
                size: 34,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    country.name,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: selected ? AppColors.primary : scheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${country.dialCode}  •  ${country.isoCode}',
                    style: TextStyle(
                      fontSize: 13,
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            selected
                ? Container(
                    width: 26,
                    height: 26,
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Icons.chevron_right_rounded,
                    color: scheme.onSurfaceVariant,
                  ),
          ],
        ),
      ),
    );
  }
}

class _NetworkOptionTile extends StatelessWidget {
  const _NetworkOptionTile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.selected,
    required this.cardBg,
    required this.isDark,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String? subtitle;
  final bool selected;
  final Color cardBg;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: iconColor, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontSize: 13,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _ConfirmOperatingNetworkSheet extends StatelessWidget {
  const _ConfirmOperatingNetworkSheet({
    required this.networks,
    required this.autoNetworkId,
  });

  final List<ServiceOption> networks;
  final String autoNetworkId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final scheme = Theme.of(context).colorScheme;
    final sheetBg = isDark ? AppColors.darkScaffold : Colors.white;
    final tileBg = isDark ? AppColors.darkSurface : const Color(0xFFF6F6F9);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: Material(
        color: sheetBg,
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 44,
                  height: 4,
                  decoration: BoxDecoration(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 18),
                const Icon(
                  Icons.network_check_rounded,
                  color: AppColors.primary,
                  size: 34,
                ),
                const SizedBox(height: 12),
                Text(
                  'Confirm Operating Network',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800, fontSize: 18),
                ),
                const SizedBox(height: 8),
                Text(
                  'Ported numbers may use a different network. Select the actual network this number operates on.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                _NetworkOptionTile(
                  icon: Icons.auto_fix_high_rounded,
                  iconColor: AppColors.primary,
                  iconBg: AppColors.primary.withValues(alpha: 0.14),
                  title: 'Auto Detect',
                  subtitle: 'Trust auto-detected network',
                  selected: false,
                  cardBg: tileBg,
                  isDark: isDark,
                  onTap: () => Navigator.of(context).pop(autoNetworkId),
                ),
                const SizedBox(height: 10),
                for (final network in networks.take(4)) ...[
                  _NetworkOptionTile(
                    icon: Icons.cell_tower_rounded,
                    iconColor: scheme.onSurface,
                    iconBg: isDark ? AppColors.darkInput : Colors.white,
                    title: network.name.replaceAll(' Ghana', ''),
                    selected: false,
                    cardBg: tileBg,
                    isDark: isDark,
                    onTap: () => Navigator.of(context).pop(network.id),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DataPlanCard extends StatelessWidget {
  const _DataPlanCard({
    required this.bundle,
    this.convertedLabel,
    required this.selected,
    required this.cardBg,
    required this.isDark,
    required this.onTap,
  });

  final DataBundle bundle;
  final String? convertedLabel;
  final bool selected;
  final Color cardBg;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chipBg = isDark ? AppColors.darkInput : const Color(0xFFF3F3F7);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: selected
                ? AppColors.primary
                : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
            width: selected ? 1.8 : 1,
          ),
          boxShadow: [
            if (!isDark)
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  alignment: Alignment.center,
                  child: const Icon(
                    Icons.wifi_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        bundle.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: scheme.onSurface,
                          height: 1.25,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        bundle.dataAmount,
                        style: TextStyle(
                          fontSize: 13.5,
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${bundle.currency} ${bundle.price.toStringAsFixed(2)}',
                      style: const TextStyle(
                        color: Color(0xFF33B457),
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      convertedLabel ?? 'No expiry',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: convertedLabel != null
                            ? FontWeight.w700
                            : FontWeight.w400,
                        color: convertedLabel != null
                            ? AppColors.primary
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Capacity: ${bundle.dataAmount}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: chipBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Validity: No expiry',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Inline status strip under the phone field — detecting spinner, detected
/// operator, or lookup error for the Reloadly data route.
class _DataDetectBanner extends StatelessWidget {
  const _DataDetectBanner({
    required this.isDark,
    required this.color,
    required this.text,
    this.showSpinner = false,
    this.error = false,
    this.leading,
  });

  final bool isDark;
  final Color color;
  final String text;
  final bool showSpinner;
  final bool error;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (showSpinner)
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
            )
          else if (leading != null)
            leading!
          else
            Icon(
              error ? Icons.error_outline_rounded : Icons.check_circle_rounded,
              color: color,
              size: 22,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
