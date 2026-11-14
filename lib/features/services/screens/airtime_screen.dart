import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/feedback_views.dart';
import '../../../core/widgets/skeleton.dart';
import '../../auth/providers.dart';
import '../../dashboard/providers.dart';
import '../../history/providers.dart';
import '../widgets/country_flag_badge.dart';
import '../widgets/phone_number_formatter.dart';
import '../../lida_value/providers.dart';
import '../../payments/data/pending_payment.dart';
import '../../payments/providers.dart';
import '../../payments/widgets/payment_awaiting_panel.dart';
import '../../payments/widgets/payment_method_selector.dart';
import '../../recipient_choice/providers.dart';
import '../../recipient_choice/screens/pending_topup_screen.dart';
import '../data/service_models.dart';
import '../providers.dart';
import '../widgets/lida_value_checkout_switch.dart';
import '../widgets/service_receipt_screen.dart';
import '../widgets/service_wizard_widgets.dart';
import '../widgets/topup_review_card.dart';

class AirtimeScreen extends ConsumerStatefulWidget {
  const AirtimeScreen({
    super.key,
    this.funding = ServiceFunding.momo,
    this.initialStep = 1,
  });

  /// How the purchase is funded — the default is the Advansis Pay momo
  /// checkout; Lida Value USE/SEND debit the wallet instead and skip the
  /// browser payment entirely.
  final ServiceFunding funding;

  /// Wizard entry point: 1 = country (default — destination selection comes
  /// first, with the profile country auto-selected at the top like the
  /// legacy app). Lida Value USE skips to 2 since the country is locked to
  /// Ghana.
  final int initialStep;

  @override
  ConsumerState<AirtimeScreen> createState() => _AirtimeScreenState();
}

class _CountryItem {
  const _CountryItem({
    required this.name,
    required this.dialCode,
    required this.isoCode,
    this.flagUrl,
    required this.currency,
  });

  final String name;
  final String dialCode;
  final String isoCode;
  final String? flagUrl;
  final String currency;

  _CountryItem copyWithDialCode(String value) => _CountryItem(
    name: name,
    dialCode: value,
    isoCode: isoCode,
    flagUrl: flagUrl,
    currency: currency,
  );
}

class _AirtimeScreenState extends ConsumerState<AirtimeScreen>
    with WidgetsBindingObserver {
  /// Known destinations carry their dial code + flag for a polished picker.
  /// Any extra country returned by `GET /api/v1/reloadly/country-list` is
  /// merged on top with a generated flag and international-number entry.
  static const _countries = <_CountryItem>[
    _CountryItem(
      name: 'Ghana',
      dialCode: '+233',
      isoCode: 'GH',
      currency: 'GHS',
    ),
    _CountryItem(
      name: 'Nigeria',
      dialCode: '+234',
      isoCode: 'NG',
      currency: 'NGN',
    ),
    _CountryItem(
      name: 'Kenya',
      dialCode: '+254',
      isoCode: 'KE',
      currency: 'KES',
    ),
    _CountryItem(
      name: 'South Africa',
      dialCode: '+27',
      isoCode: 'ZA',
      currency: 'ZAR',
    ),
    _CountryItem(
      name: 'Côte d\'Ivoire',
      dialCode: '+225',
      isoCode: 'CI',
      currency: 'XOF',
    ),
    _CountryItem(
      name: 'Senegal',
      dialCode: '+221',
      isoCode: 'SN',
      currency: 'XOF',
    ),
    _CountryItem(
      name: 'Tanzania',
      dialCode: '+255',
      isoCode: 'TZ',
      currency: 'TZS',
    ),
    _CountryItem(
      name: 'Uganda',
      dialCode: '+256',
      isoCode: 'UG',
      currency: 'UGX',
    ),
    _CountryItem(
      name: 'Rwanda',
      dialCode: '+250',
      isoCode: 'RW',
      currency: 'RWF',
    ),
    _CountryItem(
      name: 'Egypt',
      dialCode: '+20',
      isoCode: 'EG',
      currency: 'EGP',
    ),
    _CountryItem(
      name: 'India',
      dialCode: '+91',
      isoCode: 'IN',
      currency: 'INR',
    ),
    _CountryItem(
      name: 'United Kingdom',
      dialCode: '+44',
      isoCode: 'GB',
      currency: 'GBP',
    ),
    _CountryItem(
      name: 'United States',
      dialCode: '+1',
      isoCode: 'US',
      currency: 'USD',
    ),
    _CountryItem(
      name: 'Canada',
      dialCode: '+1',
      isoCode: 'CA',
      currency: 'CAD',
    ),
    _CountryItem(
      name: 'United Arab Emirates',
      dialCode: '+971',
      isoCode: 'AE',
      currency: 'AED',
    ),
    _CountryItem(
      name: 'Afghanistan',
      dialCode: '+93',
      isoCode: 'AF',
      currency: 'AFN',
    ),
    _CountryItem(
      name: 'Albania',
      dialCode: '+355',
      isoCode: 'AL',
      currency: 'ALL',
    ),
    _CountryItem(
      name: 'Algeria',
      dialCode: '+213',
      isoCode: 'DZ',
      currency: 'DZD',
    ),
  ];

  /// Regional-indicator flag for countries that only exist in the live
  /// Reloadly catalogue and have no static entry.

  /// Live catalogue entries only carry an ISO code + name; the currency
  /// arrives in `meta` when the API exposes `currencyCode`.
  List<_CountryItem> _mergedCountries(List<ServiceOption>? live) {
    final merged = List<_CountryItem>.of(_countries);
    final known = {for (final c in _countries) c.isoCode};
    for (final option in live ?? const <ServiceOption>[]) {
      if (option.id.length != 2 || known.contains(option.id)) continue;
      final currency = RegExp(r'^[A-Z]{3}$').hasMatch(option.meta ?? '')
          ? option.meta!
          : 'USD';
      merged.add(
        _CountryItem(
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

  /// Mirrors the old app: once the country catalogue resolves, pre-select the
  /// signed-in user's own country so a diaspora user doesn't have to search.
  void _autoSelectUserCountry(List<_CountryItem> countries) {
    if (_didAutoSelectCountry) return;
    _didAutoSelectCountry = true;
    final userCountry =
        ref.read(authSessionProvider)?.user.country.toUpperCase() ?? '';
    if (userCountry.isEmpty) return;
    for (final country in countries) {
      if (country.isoCode == userCountry ||
          country.name.toUpperCase() == userCountry) {
        if (country.isoCode == _selectedCountry.isoCode) return;
        setState(() {
          _selectedCountry = country;
          _resetNetworkForCountry();
        });
        _resolveCountryDialCode(country);
        return;
      }
    }
  }

  /// `GET /reloadly/country-list` returns no `callingCodes`, so countries
  /// merged from the API arrive with an empty dial code. Resolve it lazily
  /// through `POST /reloadly/find-country-by-code` on selection.
  Future<void> _resolveCountryDialCode(_CountryItem country) async {
    if (country.dialCode.isNotEmpty) return;
    final detail = await ref
        .read(servicesRepositoryProvider)
        .findCountryByCode(country.isoCode);
    if (!mounted || detail?.dialCode == null) return;
    if (_selectedCountry.isoCode != country.isoCode) return;
    setState(
      () => _selectedCountry =
          _selectedCountry.copyWithDialCode(detail!.dialCode!),
    );
  }

  static const _presets = <double>[1, 5, 10, 15, 20, 25, 50, 100];

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

  /// Wizard screens: 1 = Country, 2 = Network, 3 = Phone, 4 = Amount,
  /// 5 = Review — the same five steps the legacy progress indicator named.
  /// The network is picked from the destination's operator list (Ghana's
  /// fixed Prymo networks, Reloadly's catalogue) and may be left on "Auto
  /// detect", in which case `/reloadly/operator/autodetect` resolves it from
  /// the number on the phone step, exactly like the legacy app did inline.
  late int _step = widget.initialStep;

  /// Mutable copy of `widget.funding` — an insufficient Lida Value balance
  /// can flip the run back to the momo checkout without leaving the wizard.
  late ServiceFunding _funding = widget.funding;
  _CountryItem _selectedCountry = _countries.first;
  String _countryQuery = '';
  bool _didAutoSelectCountry = false;

  final _phone = TextEditingController();
  final _amount = TextEditingController();
  final _countrySearch = TextEditingController();
  String? _networkId;

  /// Set when the user names the network explicitly on the Network step.
  /// A locked pick survives operator detection and edits to the number —
  /// detection may only *suggest* a correction, never overwrite a choice.
  bool _networkLocked = false;
  bool _submitting = false;
  ServiceReceipt? _receipt;
  bool _showAllPresets = false;
  static const int _initialPresetCount = 6;

  /// Live Reloadly operator detection. `_detectedOperator` carries suggested
  /// amounts, min/max and the fx rate for the amount step; `_detectSeq`
  /// drops stale responses when the user keeps typing.
  DetectedOperator? _detectedOperator;
  bool _detecting = false;
  String? _detectError;
  Timer? _detectDebounce;
  int _detectSeq = 0;

  /// Ghana operating-network confirmation (ported numbers). `_autoGhanaCode`
  /// is the Prymo code mapped from the detected Reloadly operator; the user
  /// confirms or overrides it through the popup/pills — `_ghanaChoice` is
  /// only set by an explicit pick, which is what unlocks the NEXT button.
  String? _autoGhanaCode;
  String? _ghanaChoice;
  int _popupForSeq = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.funding == ServiceFunding.lidaValueUse) {
      // USE is self-only — the Lida Value debit endpoint only takes Ghana
      // numbers, so the country is locked and the country step is skipped.
      _selectedCountry = _countries.firstWhere(
        (c) => c.isoCode == 'GH',
        orElse: () => _countries.first,
      );
      _didAutoSelectCountry = true;
      _ghanaChoice = 'auto';
      _networkId = _autoGhanaCode ?? '0';
      _step = 3;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyUserDefaults());
  }

  /// A self top-up is the common case: the signed-in user's registered
  /// country and phone number fill the wizard so they only need to pick an
  /// amount — both stay editable for sending to another recipient.
  void _applyUserDefaults() {
    if (!mounted) return;
    final user = ref.read(authSessionProvider)?.user;
    if (user == null) return;

    if (!_didAutoSelectCountry &&
        widget.funding != ServiceFunding.lidaValueUse) {
      final userCountry = user.country.toUpperCase();
      if (userCountry.isNotEmpty) {
        final countries = _mergedCountries(
          ref.read(countriesProvider).valueOrNull,
        );
        for (final country in countries) {
          if (country.isoCode == userCountry ||
              country.name.toUpperCase() == userCountry) {
            _didAutoSelectCountry = true;
            if (country.isoCode != _selectedCountry.isoCode) {
              setState(() {
                _selectedCountry = country;
                _networkId = null;
              });
            }
            break;
          }
        }
      }
    }

    // The phone field deliberately starts empty — the user either types a
    // recipient or taps "Use My Number", which also triggers detection.
    if (mounted) setState(() {});
  }

  /// Strips the country's dial code from a full international number so the
  /// phone field shows local digits — `233244588584` → `244588584` for GH,
  /// `234801…` → `801…` for NG. Ghana's `_digits` re-adds the leading 0.
  String _localNumberFor(_CountryItem country, String rawDigits) {
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

  /// Returning from the checkout browser doesn't always deliver a deep link
  /// (cancelled prompts, manual task-switching) — a resume re-queries the
  /// saved payment token so nothing stalls on the awaiting panel.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        ref.read(paymentSessionProvider).phase ==
            PaymentPhase.awaitingCallback) {
      ref.read(paymentSessionProvider.notifier).recheck();
    }
  }

  bool get _isGhana => _selectedCountry.isoCode == 'GH';

  /// Ghana submits the local `0xxxxxxxxx` format to Prymo; every other
  /// destination hands its digits to the repository, which expands them
  /// through the country's dial code for Reloadly.
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

  /// Ghana-prefix auto-detection only applies to the domestic route; other
  /// countries resolve their operator through the Reloadly lookup.
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

  double get _amountValue => double.tryParse(_amount.text.trim()) ?? 0;

  /// Ghana tops up in cedis; Reloadly destinations quote in USD (or the
  /// operator's sender currency) and convert to the destination country's
  /// currency via `fx`.
  String get _amountCurrency => _isGhana
      ? 'GHS'
      : (_detectedOperator?.senderCurrencyCode ?? 'USD');

  String _priceLabel(double value) => _isGhana
      ? Formatters.currency(value)
      : '$_amountCurrency ${value.toStringAsFixed(2)}';

  String _presetLabel(double value) => _isGhana
      ? 'GH₵ ${value.toStringAsFixed(0)}'
      : '$_amountCurrency ${value.toStringAsFixed(0)}';

  bool get _hasValidPhone =>
      _phone.text.replaceAll(RegExp(r'\D'), '').length >= 9;

  /// Ghana requires an explicitly confirmed Prymo network (autodetect
  /// preselects, the user confirms — ported numbers may differ). Reloadly
  /// destinations may leave the operator unset — `buyGlobalAirtime` resolves
  /// it through the phone-lookup endpoint (`_networkId == null` or `'auto'`).
  bool get _canSubmit =>
      _hasValidPhone &&
      _amountInRange &&
      (_isGhana ? _ghanaChoice != null : true);

  void _onPhoneChanged(List<ServiceOption> networks) {
    setState(() {
      // Only the detection-derived suggestion is dropped when the number
      // changes. The choice made on the Network step survives, so editing a
      // digit can never silently un-answer that step and strand the submit
      // guard (a cleared `_ghanaChoice` used to leave Ghana runs unable to
      // pay after a failed lookup).
      if (!_networkLocked) {
        _autoGhanaCode = null;
        _networkId = _isGhana ? '0' : 'auto';
      }
      _detectedOperator = null;
      _detectError = null;
      _detecting = false;
    });
    // The API autodetect runs for every destination — Ghana numbers come
    // back with an operatorId that maps onto the Prymo network codes,
    // exactly like the legacy app.
    _detectDebounce?.cancel();
    if (_hasValidPhone) {
      _detectDebounce = Timer(
        const Duration(milliseconds: 600),
        _detectOperator,
      );
    }
  }

  /// Reloadly operator ids → Prymo One4All network codes (the same table the
  /// legacy app's `GhanaNetworkCodes` used for its autodetect popup).
  static const _ghanaOperatorToPrymo = <int, String>{
    150: '4', 643: '4', // MTN Ghana
    151: '1', 642: '1', // AirtelTigo
    157: '1', 648: '1', // TiGO → merged into AirtelTigo
    152: '6', 770: '6', // Telecel (ex-Vodafone)
    153: '3', 644: '3', // Glo
    155: '8', 646: '8', // Busy
    156: '9', 647: '9', // Surfline
  };

  /// Resolve the Reloadly operator as the user types, like the old app's
  /// autodetect screen — the amount step then uses the operator's suggested
  /// amounts, min/max and fx rate instead of static presets. For Ghana the
  /// detected operator is translated into the Prymo network code that the
  /// One4All top-up endpoint expects.
  Future<void> _detectOperator() async {
    final requestId = ++_detectSeq;
    setState(() {
      _detecting = true;
      _detectError = null;
    });
    try {
      final operator = await ref
          .read(servicesRepositoryProvider)
          .detectAirtimeOperator(
            phone: _digits,
            countryIsoCode: _selectedCountry.isoCode,
            recipientDialCode: _selectedCountry.dialCode,
          );
      if (!mounted || requestId != _detectSeq) return;
      setState(() {
        _detectedOperator = operator;
        if (_isGhana) {
          // Map the operator onto the Prymo code and preselect it — the user
          // still confirms the operating network explicitly (ported numbers
          // can differ), exactly like the legacy Ghana popup.
          _autoGhanaCode =
              _ghanaOperatorToPrymo[operator.id] ??
              _networkIdFromName(operator.name);
          // A network named on the Network step wins over the suggestion;
          // the mismatch is surfaced as a one-tap correction instead.
          if (!_networkLocked) _networkId = _autoGhanaCode;
        } else if (!_networkLocked) {
          _networkId = '${operator.id}';
        }
        _detecting = false;
      });
      _maybeShowGhanaPopup();
    } on ApiException catch (error) {
      if (!mounted || requestId != _detectSeq) return;
      setState(() {
        _detectedOperator = null;
        _detectError = error.message;
        _detecting = false;
        _fallbackToLocalGhanaNetwork();
      });
      _maybeShowGhanaPopup();
    } catch (_) {
      if (!mounted || requestId != _detectSeq) return;
      setState(() {
        _detectedOperator = null;
        _detectError =
            'We could not detect the operator for this number. '
            'Check the phone number and try again.';
        _detecting = false;
        _fallbackToLocalGhanaNetwork();
      });
      _maybeShowGhanaPopup();
    }
  }

  /// Offline network resolution for Ghana: the live autodetect route can
  /// be unavailable while the local prefix table still identifies MTN,
  /// Telecel, AirtelTigo or Glo — preselect the Prymo code so the user
  /// only has to confirm it.
  void _fallbackToLocalGhanaNetwork() {
    if (!_isGhana) return;
    final brand = _detectedBrand;
    if (brand == null) return;
    final code = _brandToPrymo[brand];
    if (code != null && !_networkLocked) {
      _autoGhanaCode = code;
      _networkId = code;
    }
  }

  /// Name fallback when the operatorId isn't in the Prymo table — e.g.
  /// "AirtelTigo Ghana" still resolves to network code 1.
  static const _brandToPrymo = <String, String>{
    'MTN': '4',
    'AirtelTigo': '1',
    'Telecel': '6',
    'Glo': '3',
    'Busy': '8',
    'Surfline': '9',
  };

  String? _networkIdFromName(String operatorName) {
    final upper = operatorName.toUpperCase();
    for (final entry in _brandToPrymo.entries) {
      if (upper.contains(entry.key.toUpperCase())) return entry.value;
    }
    return null;
  }

  void _useMyNumber(String userPhone, List<ServiceOption> networks) {
    final digits = userPhone.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;
    _phone.text = _localNumberFor(_selectedCountry, digits);
    _onPhoneChanged(networks);
  }

  void _onInternationalNumberPasted(
    String raw,
    List<ServiceOption> networks,
    List<_CountryItem> countries,
  ) {
    final clean = raw.startsWith('00')
        ? raw.substring(2)
        : (raw.startsWith('+') ? raw.substring(1) : raw);
    final digits = clean.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return;

    _CountryItem? matched;
    String matchedDial = '';
    for (final c in countries) {
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

  /// The amount must satisfy the detected operator's min/max when the API
  /// reported them — Reloadly rejects out-of-range top-ups anyway.
  bool get _amountInRange =>
      _amountValue > 0 && (_detectedOperator?.accepts(_amountValue) ?? true);

  /// Network step gate. Ghana submits a concrete Prymo code, so a pick (or an
  /// "Auto detect" that has since resolved) must be in place. Reloadly
  /// destinations always carry a pick because "Auto detect" is preselected —
  /// the step can never dead-end on a catalogue that failed to load.
  bool get _networkReady => _isGhana ? _ghanaChoice != null : _networkId != null;

  bool get _canAdvanceStep => switch (_step) {
    1 => true,
    2 => _networkReady,
    3 => _hasValidPhone && !_detecting,
    4 => _amountInRange,
    5 => _canSubmit && !_submitting,
    _ => false,
  };

  /// A destination switch invalidates the previous operator — Prymo codes and
  /// Reloadly operator ids must never leak across the route switch.
  void _resetNetworkForCountry() {
    _networkId = _isGhana ? null : 'auto';
    _networkLocked = false;
    _ghanaChoice = null;
    _autoGhanaCode = null;
  }

  void _pickGhanaNetwork(String choice) {
    setState(() {
      _ghanaChoice = choice;
      _networkLocked = choice != 'auto';
      _networkId = choice == 'auto' ? (_autoGhanaCode ?? '0') : choice;
    });
  }

  /// Reloadly destinations pick from the operator catalogue, or leave it on
  /// "Auto detect" and let the number decide on the next step.
  void _pickInternationalNetwork(String id) {
    setState(() {
      _networkId = id;
      _networkLocked = id != 'auto';
    });
  }

  /// Forward navigation goes country → phone like the legacy wizard: the
  /// network answers itself by detection ("Auto Detect" is preselected on
  /// both routes) and the dedicated step only remains as an explicit edit.
  /// Ghana resolves the pick from the number's prefix, Reloadly destinations
  /// through autodetect, so NEXT is never gated on a lookup the user may not
  /// need at all.
  void _enterPhoneStep() {
    if (_isGhana) {
      _pickGhanaNetwork(_ghanaChoice ?? 'auto');
    } else {
      _networkId ??= 'auto';
    }
    setState(() => _step = 3);
    // Detection may already have run against the profile number while the
    // user was still picking a destination — only fire when it's still needed.
    if (_hasValidPhone && !_detecting && _detectedOperator == null) {
      _detectOperator();
    }
    _maybeShowGhanaPopup();
  }

  /// Ghana: once detection resolves and the user deferred to it, open the
  /// half-screen operating-network sheet once per detection so a ported number
  /// can be corrected (an explicit pick on the Network step skips it).
  void _maybeShowGhanaPopup() {
    final resolved = _detectedOperator != null || _autoGhanaCode != null;
    if (!_isGhana ||
        !resolved ||
        _networkLocked ||
        _step != 3 ||
        _popupForSeq == _detectSeq) {
      return;
    }
    _popupForSeq = _detectSeq;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _step == 3) _showGhanaNetworkPopup();
    });
  }

  void _nextStep() {
    if ((_step == 1 || _step == 2) && _canAdvanceStep) {
      _enterPhoneStep();
      return;
    }
    if (_step < 5 && _canAdvanceStep) {
      setState(() => _step += 1);
    } else if (_step == 5 && _canSubmit) {
      _submit();
    }
  }

  /// LV USE locks the country to Ghana — going "back" past the phone step
  /// would land on a one-country picker, so its floor is the phone step.
  int get _firstStep =>
      _funding == ServiceFunding.lidaValueUse ? 3 : widget.initialStep;

  Future<void> _prevStep() async {
    if (_step > _firstStep) {
      // The network step is skipped in forward navigation, so back from the
      // phone step returns to the country picker like the legacy wizard.
      setState(() => _step = _step == 3 ? 1 : _step - 1);
    } else {
      Navigator.of(context).pop();
    }
  }

  /// Refresh the ledger, points, Lida Value and dashboard summary so the
  /// newly settled top-up and its accrued LidaPoints show immediately.
  void _invalidateActivityFeeds() {
    ref.invalidate(historyProvider);
    ref.invalidate(historyAnalyticsProvider);
    ref.invalidate(recentTransactionsProvider);
    ref.invalidate(walletSummaryProvider);
    ref.invalidate(lidaPointsProvider);
    ref.invalidate(lidaValueProvider);
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

  /// Payment-first ordering (matches the released app): the pending
  /// purchase is persisted, Advansis checkout opens, and the provider call
  /// only runs after `query-transaction` confirms payment. Lida Value
  /// funding skips the browser entirely — the wallet debit *is* the
  /// payment, then the same delivery calls run.
  Future<void> _submit() async {
    if (!_canSubmit || _submitting) return;
    final user = ref.read(authSessionProvider)?.user;
    final recipientDigits = _digits;
    var funding = _funding;

    // USE is self-only. If the entered number belongs to someone else the
    // purchase must be re-labelled SEND so the recipient-choice rules apply.
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
    // Sending to your own number is a USE self-topup: the backend bypasses
    // the recipient-decision flow and delivers directly.
    final isSelf =
        funding == ServiceFunding.lidaValueUse ||
        (_isSelfRecipient(user?.phoneNumber) && !funding.isLidaValue);
    final orderDesc =
        'Lidapay airtime top-up $_amountCurrency '
        '${_amountValue.toStringAsFixed(2)} for $recipientDigits';
    final draft = _isGhana
        ? PendingPayment.ghanaAirtime(
            reference: newPaymentReference(),
            amount: _amountValue,
            recipientNumber: recipientDigits,
            networkId: _networkId!,
            saveToLidaValue: false,
            isSelfTopup: isSelf,
            orderDesc: orderDesc,
          )
        : PendingPayment.globalAirtime(
            reference: newPaymentReference(),
            // Charged exactly as Reloadly quotes it (sender currency, e.g.
            // USD) — the fx rate only describes what the recipient receives.
            payAmount: _amountValue,
            payCurrency: _amountCurrency,
            deliverAmount: _amountValue,
            deliverCurrency: _amountCurrency,
            recipientNumber: recipientDigits,
            countryCode: _selectedCountry.isoCode,
            operatorId: (_networkId == null || _networkId == 'auto')
                ? null
                : _networkId,
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
          .execute(draft: draft, funding: funding, serviceType: 'AIRTIME');
      if (mounted) setState(() => _submitting = false);
      return;
    }

    if (!mounted) return;
    final choice = await showPaymentMethodSheet(
      context: context,
      amountLabel: _priceLabel(_amountValue),
      orderSummary: 'Airtime top-up · $recipientDigits',
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
        'choice between direct airtime and Lida Value.',
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

  String get _stepTitle => switch (_step) {
    1 => 'Select Country',
    2 => 'Select Network',
    3 => 'Enter Phone Number',
    4 => 'Select Amount',
    _ => 'Confirm Airtime',
  };

  @override
  Widget build(BuildContext context) {
    // The deep-link return and the awaiting panel's "I've paid" both resolve
    // through the shared session: a finished credit surfaces its receipt
    // here; a terminal failure leaves the wizard on the confirm step.
    ref.listen<PaymentSessionState>(paymentSessionProvider, (prev, next) {
      if (!mounted) return;
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
          amountLabel: _priceLabel(_amountValue),
          recipientLabel: _digits,
          serviceLabel: 'airtime',
          icon: Icons.call_rounded,
          onDone: () => Navigator.of(context).pop(),
        );
      }
      return ServiceReceiptScreen(
        receipt: receipt,
        icon: Icons.call_rounded,
        onDone: () => Navigator.of(context).pop(),
      );
    }

    // Any persisted in-flight purchase blocks a new one until it settles —
    // the panel also resumes verification after a cold start.
    final paymentActive = ref.watch(
      paymentSessionProvider.select(
        (s) => s.phase != PaymentPhase.idle && s.pending != null,
      ),
    );

    // Route-aware operator list. Ghana uses the fixed Prymo networks; Reloadly
    // destinations resolve the operator from the phone number via autodetect
    // (matching Lidapay-old) and only fetch the full country operator list
    // when the user explicitly opens Step 2 to override the network.
    final networksAsync = _isGhana
        ? ref.watch(ghanaNetworksProvider)
        : _step == 2
        ? ref.watch(internationalOperatorsProvider(_selectedCountry.isoCode))
        : const AsyncValue.data(<ServiceOption>[]);
    final networks = networksAsync.valueOrNull ?? const <ServiceOption>[];
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
            delegate: _PinnedAirtimeHeaderDelegate(
              height: MediaQuery.paddingOf(context).top + 74,
              title: _stepTitle,
              onBack: () => Navigator.of(context).pop(),
            ),
          ),
          SliverToBoxAdapter(
            child: ServiceWizardStepBar(
              currentStep: _step,
              onStepTap: (target) {
                if (target < _step) setState(() => _step = target);
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
              child: paymentActive
                  ? const PaymentAwaitingPanel()
                  // The country picker only needs `countriesProvider` — it must
                  // stay usable even when the previously selected country's
                  // operator lookup is loading or failing, otherwise a bad
                  // destination locks the wizard on an error with no list.
                  : _step == 1
                  ? _buildCountryStep(isDark, cardBg)
                  : _isGhana && !networksAsync.hasValue
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
                              onPressed: () => setState(() => _step = 1),
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
                      3 => _buildPhoneAndQuickAmountStep(
                        networks,
                        userPhone,
                        isDark,
                        cardBg,
                      ),
                      4 => _buildAmountStep(networks, isDark, cardBg),
                      _ => _buildConfirmStep(networks, isDark, cardBg),
                    },
            ),
          ),
        ],
      ),
      bottomNavigationBar:
          (_isGhana && !networksAsync.hasValue) || paymentActive
          ? null
          : ServiceWizardBottomBar(
              isFinalStep: _step == 5,
              confirmLabel: _amountValue > 0
                  ? (_funding.isLidaValue
                        ? 'Pay ${_amountValue.toStringAsFixed(2)} LV'
                        : 'Pay ${_priceLabel(_amountValue)}')
                  : 'Pay now',
              canNext: _canAdvanceStep,
              submitting: _submitting,
              onPrevious: _prevStep,
              onNext: _nextStep,
            ),
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
          'Choose the country for airtime topup',
          style: TextStyle(
            fontSize: 15,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          decoration: BoxDecoration(
            color: cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isDark ? Colors.white10 : const Color(0xFFEAE8F0),
            ),
            boxShadow: [
              if (!isDark)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
            ],
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
          _CountryTile(
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
                  // Stale Ghana network codes / Reloadly operator ids must
                  // never leak across the route switch — and a number typed
                  // for the old country is meaningless under the new one.
                  _resetNetworkForCountry();
                  _detectedOperator = null;
                  _detectError = null;
                  _detecting = false;
                  _detectDebounce?.cancel();
                  _phone.clear();
                }
              });
              // Countries merged from `reloadly/country-list` arrive without a
              // dial code — resolve it before the phone step needs it, or the
              // local number never expands to a valid Reloadly MSISDN.
              _resolveCountryDialCode(country);
              _enterPhoneStep();
            },
          ),
          const SizedBox(height: 12),
        ],
      ],
    );
  }

  /// Ghana's operating-network options — the active Prymo networks (auto
  /// trust resolves to the API-detected code; ported numbers pick theirs).
  static const _ghanaOptions = <(String, String, IconData)>[
    ('auto', 'Auto Detect', Icons.auto_fix_high_rounded),
    ('4', 'MTN', Icons.cell_tower_rounded),
    ('6', 'Telecel', Icons.cell_tower_rounded),
    ('1', 'AirtelTigo', Icons.cell_tower_rounded),
  ];

  /// Step 2 — the destination's networks. Ghana lists its fixed Prymo
  /// operators; every other destination lists the Reloadly catalogue for the
  /// country with "Auto Detect" pinned on top, so an operator lookup that
  /// fails still leaves a selectable, non-blocking choice.
  Widget _buildNetworkStep(List<ServiceOption> networks) {
    final scheme = Theme.of(context).colorScheme;
    if (_isGhana) {
      return ServiceNetworkStep(
        intro: 'Select the network this number operates on.',
        options: [
          for (final (key, label, icon) in _ghanaOptions)
            NetworkStepOption(
              id: key,
              label: label,
              icon: icon,
              subtitle: key == 'auto'
                  ? 'Match it from the number on the next step'
                  : null,
            ),
        ],
        selectedId: _ghanaChoice,
        onSelected: (option) => _pickGhanaNetwork(option.id),
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
            subtitle: network.meta,
          ),
      ],
      selectedId: _networkId ?? 'auto',
      onSelected: (option) => _pickInternationalNetwork(option.id),
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
                    internationalOperatorsProvider(_selectedCountry.isoCode),
                  ),
                  child: const Text('Retry'),
                ),
              ],
            )
          : Text(
              '${networks.length} operator${networks.length == 1 ? '' : 's'} '
              'available for ${_selectedCountry.name}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: AppColors.primary,
              ),
            ),
    );
  }

  /// Ported-number popup — shown once per detection like the legacy app:
  /// the API names the operator, the user confirms the billing network.
  void _showGhanaNetworkPopup() {
    final detected = _detectedOperator?.name;
    showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? AppColors.darkSurface : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 28),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : const Color(0xFFE5E3EC),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const Icon(
                    Icons.network_check_rounded,
                    color: AppColors.primary,
                    size: 30,
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Confirm Operating Network',
                    style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    detected != null
                        ? '$detected detected. Ported numbers may use a different\nnetwork — confirm the one this number operates on.'
                        : 'Ported numbers may use a different network.\nSelect the one this number operates on.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final (key, label, icon) in _ghanaOptions)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Material(
                        color: isDark
                            ? AppColors.darkInput
                            : const Color(0xFFF6F6F9),
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () {
                            _pickGhanaNetwork(key);
                            Navigator.of(ctx).pop();
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 13,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  alignment: Alignment.center,
                                  child: Icon(
                                    icon,
                                    size: 20,
                                    color: AppColors.primary,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        label,
                                        style: const TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      if (key == 'auto')
                                        Text(
                                          detected != null
                                              ? 'Trust the detected $detected'
                                              : 'Trust the detected operator',
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            color: Theme.of(ctx)
                                                .colorScheme
                                                .onSurfaceVariant,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.chevron_right_rounded,
                                  color: Theme.of(ctx)
                                      .colorScheme
                                      .onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Inline "Select Operating Network" card on the phone step — the legacy
  /// pills for correcting a ported number, with a Change link that reopens
  /// the popup.
  Widget _buildGhanaNetworkConfirm(bool isDark, Color cardBg) {
    final scheme = Theme.of(context).colorScheme;
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
                onTap: _showGhanaNetworkPopup,
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
              for (final (key, label, icon) in _ghanaOptions)
                GestureDetector(
                  onTap: () => _pickGhanaNetwork(key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: _ghanaChoice == key
                          ? AppColors.primary.withValues(alpha: 0.12)
                          : cardBg,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: _ghanaChoice == key
                            ? AppColors.primary
                            : (isDark
                                  ? Colors.white12
                                  : const Color(0xFFE0DEE8)),
                        width: _ghanaChoice == key ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          icon,
                          size: 15,
                          color: _ghanaChoice == key
                              ? AppColors.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          label,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: _ghanaChoice == key
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: _ghanaChoice == key
                                ? AppColors.primary
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildPhoneAndQuickAmountStep(
    List<ServiceOption> networks,
    String userPhone,
    bool isDark,
    Color cardBg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final detected = _detectedNetwork(networks);
    final countries = _mergedCountries(ref.watch(countriesProvider).valueOrNull);
    final rawUserDigits = userPhone.replaceAll(RegExp(r'\D'), '');
    final dialDigits = _selectedCountry.dialCode.replaceAll(RegExp(r'\D'), '');
    final isMyNumberForSelectedCountry = rawUserDigits.isNotEmpty &&
        (_isGhana
            ? (rawUserDigits.startsWith('233') ||
                rawUserDigits.length == 9 ||
                rawUserDigits.length == 10)
            : (dialDigits.isNotEmpty && rawUserDigits.startsWith(dialDigits)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Enter the phone number to recharge (network will be auto-detected), or tap "Use My Number" below to send it to yourself.',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13.5,
            color: scheme.onSurfaceVariant,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(14),
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
              Row(
                children: [
                  Text(
                    'Phone Number',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Recipient number',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  GestureDetector(
                    onTap: () => setState(() => _step = 1),
                    child: Container(
                      height: 52,
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
                            _selectedCountry.dialCode.isEmpty
                                ? _selectedCountry.isoCode
                                : _selectedCountry.dialCode,
                            style: TextStyle(
                              fontSize: 15,
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
                      height: 52,
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
                                _onInternationalNumberPasted(
                              raw,
                              networks,
                              countries,
                            ),
                          ),
                        ],
                        style: TextStyle(
                          fontSize: 16,
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
                                    size: 18,
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
                const SizedBox(height: 10),
                InkWell(
                  onTap: () => _useMyNumber(userPhone, networks),
                  borderRadius: BorderRadius.circular(24),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
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
                          size: 16,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            'Use My Number ($userPhone)',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
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
        // Detection feedback runs for every country (legacy _buildDetectingIndicator,
        // _buildOperatorInfo, _buildError); Ghana adds the ported-number
        // network confirmation below it.
        if (_detecting) ...[
          const SizedBox(height: 10),
          _DetectionBanner(
            icon: null,
            color: AppColors.primary,
            text: 'Detecting network…',
            isDark: isDark,
            showSpinner: true,
          ),
        ] else if (_detectedOperator != null) ...[
          const SizedBox(height: 10),
          _DetectionBanner(
            icon: Icons.check_circle_rounded,
            leading: OperatorLogoBadge(
              name: _detectedOperator!.name,
              logoUrl: _detectedOperator!.logoUrl,
              size: 26,
            ),
            color: const Color(0xFF33B457),
            text:
                '${_detectedOperator!.name} detected · ${_selectedCountry.name}',
            isDark: isDark,
          ),
        ] else if (_isGhana && _detectedBrand != null) ...[
          const SizedBox(height: 10),
          _DetectionBanner(
            icon: Icons.check_circle_rounded,
            color: const Color(0xFF33B457),
            text:
                '${detected?.name ?? '$_detectedBrand Ghana'} (${_detectedBrand!} detected) · ${_selectedCountry.name}',
            isDark: isDark,
          ),
        ] else if (_detectError != null) ...[
          const SizedBox(height: 10),
          _DetectionBanner(
            icon: Icons.error_outline_rounded,
            color: const Color(0xFFE5484D),
            text: _detectError!,
            isDark: isDark,
          ),
        ],
        if (_isGhana) ...[
          if (_ghanaMismatchLabel() case final mismatch?) ...[
            const SizedBox(height: 10),
            _DetectionBanner(
              icon: Icons.swap_horiz_rounded,
              color: AppColors.primary,
              text: mismatch,
              isDark: isDark,
            ),
          ],
          if (_hasValidPhone) ...[
            const SizedBox(height: 10),
            _buildGhanaNetworkConfirm(isDark, cardBg),
          ],
        ],
      ],
    );
  }

  /// Ghana: the number resolves to a different network than the one named on
  /// the Network step. Say so, and let the pills below correct it — the step
  /// is never blocked on a detection the user has already overridden.
  String? _ghanaMismatchLabel() {
    if (!_isGhana || !_networkLocked || _detectedOperator == null) return null;
    final detected = _autoGhanaCode;
    if (detected == null || detected == _ghanaChoice) return null;
    return '${_detectedOperator!.name} detected — correct the network '
        'below if this number was ported.';
  }

  Widget _buildAmountStep(
    List<ServiceOption> networks,
    bool isDark,
    Color cardBg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose the amount to recharge',
          style: TextStyle(
            fontSize: 15,
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
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
                'Enter amount',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              const SizedBox(height: 14),
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
                _isGhana
                    ? 'Min: GHS1 • Max: GHS45'
                    : [
                        _detectedOperator?.rangeLabel ??
                            'Charged in $_amountCurrency via Reloadly',
                        if (_detectedOperator?.fxRate != null &&
                            _detectedOperator?.fxCurrencyCode != null)
                          '1 $_amountCurrency ≈ '
                              '${_detectedOperator!.fxRate!.toStringAsFixed(2)} '
                              '${_detectedOperator!.fxCurrencyCode}',
                      ].join('  •  '),
                style: TextStyle(
                  fontSize: 12.5,
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
              ),
              if (!_isGhana && _amountValue > 0) ...[
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
                  child: Text(_globalPayBanner,
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
        const SizedBox(height: 22),
        _buildQuickAmountsSection(networks, isDark, cardBg),
      ],
    );
  }

  /// Amount-step banner: the charge is the quoted Reloadly figure as-is;
  /// the fx rate only describes what lands on the recipient's phone.
  String get _globalPayBanner {
    final fx = _detectedOperator?.paymentAmount(_amountValue);
    final fxCode = _detectedOperator?.fxCurrencyCode;
    return 'You will pay $_amountCurrency '
        '${_amountValue.toStringAsFixed(2)}'
        '${fx == null || fxCode == null ? '' : ' · recipient gets ≈ $fxCode ${fx.toStringAsFixed(2)}'}';
  }

  /// Non-Ghana amounts follow the detected operator's suggestions and range
  /// (Reloadly contract); Ghana keeps the fixed cedi presets.
  List<double> get _amountPresets {
    if (_isGhana) return _presets;
    final suggestions = _detectedOperator?.quickAmounts() ?? const [];
    return suggestions.isEmpty ? _presets : suggestions;
  }

  Widget _buildQuickAmountsSection(
    List<ServiceOption> networks,
    bool isDark,
    Color cardBg,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final allPresets = _amountPresets;
    if (allPresets.isEmpty) return const SizedBox.shrink();

    final hasMore = allPresets.length > _initialPresetCount;
    final displayedPresets = _showAllPresets || !hasMore
        ? allPresets
        : allPresets.take(_initialPresetCount).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
                onTap: () => setState(() => _showAllPresets = !_showAllPresets),
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _showAllPresets
                            ? 'Show less'
                            : 'View all (${allPresets.length})',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(
                        _showAllPresets
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
            // Responsive: 3 columns on phone widths, 4 on wide screens/tablets
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
              itemCount: displayedPresets.length,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: crossAxisCount,
                crossAxisSpacing: spacing,
                mainAxisSpacing: spacing,
                childAspectRatio: aspectRatio,
              ),
              itemBuilder: (context, index) {
                final value = displayedPresets[index];
                final selected = _amountValue == value;
                return GestureDetector(
                  onTap: () => setState(
                    () => _amount.text = value.toStringAsFixed(0),
                  ),
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
                      _presetLabel(value),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
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
            onTap: () => setState(() => _showAllPresets = !_showAllPresets),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 13,
              ),
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
                    _showAllPresets
                        ? Icons.keyboard_arrow_up_rounded
                        : Icons.keyboard_arrow_down_rounded,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _showAllPresets
                        ? 'Show less'
                        : 'More amounts (${allPresets.length - _initialPresetCount} more)',
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

  Widget _buildConfirmStep(
    List<ServiceOption> networks,
    bool isDark,
    Color cardBg,
  ) {
    final network = networks.firstWhere(
      (n) => n.id == _networkId,
      orElse: () => ServiceOption(
        id: 'auto',
        name: _detectedOperator?.name ?? (_isGhana ? 'MTN Ghana' : 'Auto-detect'),
      ),
    );
    final fxPaid = !_isGhana && _amountValue > 0
        ? _detectedOperator?.paymentAmount(_amountValue)
        : null;
    // The converted figure is denominated in fxCurrencyCode (e.g. NGN) —
    // label it with that code, never the sender's symbol ('$').
    final fxCode = _detectedOperator?.fxCurrencyCode ?? 'GHS';
    final isSelf = _isSelfRecipient(
      ref.watch(authSessionProvider)?.user.phoneNumber,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TopupReviewCard(
          serviceLabel: 'Airtime',
          heroValue: _priceLabel(_amountValue),
          heroCaption: !_isGhana && fxPaid != null
              ? '≈ $fxCode ${fxPaid.toStringAsFixed(2)} (${_selectedCountry.name})'
              : null,
          networkName: network.name,
          countryName: _selectedCountry.name,
          countryFlag: _selectedCountry.isoCode,
          countryFlagUrl: _selectedCountry.flagUrl,
          operatorLogoUrl: _detectedOperator?.logoUrl ?? network.flagUrl,
          recipientPhone: _digits,
          isSelf: isSelf,
          deliveryNote: isSelf
              ? 'Delivered instantly to your line once payment is confirmed.'
              : 'Recipient can take the airtime now or save it as Lida Value.',
          payWith:
              _funding.isLidaValue ? null : 'MoMo or Card · choose next',
          payAmount: fxPaid == null
              ? null
              : '$_amountCurrency ${_amountValue.toStringAsFixed(2)} · '
                    'recipient gets ≈ $fxCode ${fxPaid.toStringAsFixed(2)}',
          amountRowValue: !_isGhana && fxPaid != null
              ? '$_amountCurrency ${_amountValue.toStringAsFixed(2)} '
                    '(≈ $fxCode ${fxPaid.toStringAsFixed(2)})'
              : null,
          onChangeCountry: _funding == ServiceFunding.lidaValueUse
              ? null
              : () => setState(() => _step = 1),
          onChangeRecipient: () => setState(() => _step = 3),
          onChangeNetwork: () => setState(() => _step = 2),
          onChangeAmount: () => setState(() => _step = 4),
        ),
        const SizedBox(height: 16),
        ..._fundingAndEligibilityCards(cardBg),
      ],
    );
  }

  /// SEND/USE are Lida Value menu actions, so the wallet is what pays. The
  /// balance falling short is the only reason to leave that rail, and doing so
  /// changes how the user is charged — so ask first, never flip silently.
  Future<void> _switchToStandardCheckout() async {
    final confirmed = await confirmStandardCheckoutSwitch(
      context,
      serviceLabel: 'airtime',
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
      serviceLabel: 'airtime',
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
  List<Widget> _fundingAndEligibilityCards(Color cardBg) {
    final cards = <Widget>[];
    final user = ref.watch(authSessionProvider)?.user;

    if (_funding.isLidaValue) {
      final wallet = ref.watch(lidaValueProvider).valueOrNull;
      final short = wallet != null && _amountValue > wallet.balance;
      cards.add(
        Container(
          padding: const EdgeInsets.all(14),
          margin: const EdgeInsets.only(bottom: 14),
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

    // Recipient-choice hint — only when the destination is somebody else.
    // The probe is non-blocking: if it can't resolve we show nothing and the
    // backend still decides during the top-up call.
    if (_hasValidPhone && !_isSelfRecipient(user?.phoneNumber)) {
      final eligibility = ref.watch(
        recipientEligibilityProvider((
          phone: _digits,
          service: 'AIRTIME',
          iso: _selectedCountry.isoCode,
        )),
      );
      final prompt = eligibility.valueOrNull?.willPromptRecipient == true;
      if (prompt) {
        cards.add(
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 14),
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
                    'this airtime now or save it to Lida Value.',
                    style: const TextStyle(fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        );
      }
    }
    return cards;
  }
}

/// Inline status strip under the phone field — detecting spinner, detected
/// operator, or lookup error for the Reloadly route.
class _DetectionBanner extends StatelessWidget {
  const _DetectionBanner({
    required this.icon,
    required this.color,
    required this.text,
    required this.isDark,
    this.leading,
    this.showSpinner = false,
  });

  final IconData? icon;
  final Color color;
  final String text;
  final bool isDark;
  final Widget? leading;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.14 : 0.09),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          if (showSpinner)
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2.2, color: color),
            )
          else if (leading != null)
            leading!
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PinnedAirtimeHeaderDelegate extends SliverPersistentHeaderDelegate {
  _PinnedAirtimeHeaderDelegate({
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
        child: _WizardHeroHeader(title: title, onBack: onBack),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedAirtimeHeaderDelegate oldDelegate) {
    return oldDelegate.title != title || oldDelegate.height != height;
  }
}

class _WizardHeroHeader extends StatelessWidget {
  const _WizardHeroHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 8,
        20,
        12,
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Buy Airtime',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.78),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CountryTile extends StatelessWidget {
  const _CountryTile({
    required this.country,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final _CountryItem country;
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
              child: CountryFlagBadge(isoCode: country.isoCode, flagUrl: country.flagUrl, size: 34),
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
