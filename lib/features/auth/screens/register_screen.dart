import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_hero_header.dart';
import '../../legal/policy_acceptance.dart';
import '../../services/data/service_models.dart';
import '../../services/providers.dart';
import '../../services/widgets/country_flag_badge.dart';
import '../data/auth_models.dart';
import '../providers.dart';

enum _AccountType { personal, merchant }

class _PickedCountry {
  const _PickedCountry({
    required this.iso,
    required this.name,
    required this.dialCode,
    this.flagUrl,
  });

  final String iso;
  final String name;
  final String dialCode;
  final String? flagUrl;

  /// ISO-3166 alpha-2 → regional indicator flag emoji.
  String get flag {
    if (iso.length != 2) return '';
    final base = 0x1F1E6;
    final a = iso.codeUnitAt(0) - 0x41;
    final b = iso.codeUnitAt(1) - 0x41;
    if (a < 0 || a > 25 || b < 0 || b > 25) return '';
    return String.fromCharCodes([base + a, base + b]);
  }
}

/// Registration wizard: account type → details (with a searchable,
/// locale-prefilled country picker) → review & submit.
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _detailsFormKey = GlobalKey<FormState>();

  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  final _businessName = TextEditingController();
  final _businessType = TextEditingController();

  int _step = 0;
  _AccountType _type = _AccountType.personal;
  _PickedCountry? _country;
  bool _loading = false;
  bool _termsAccepted = false;
  String? _apiError;

  bool get _detailsAreValid {
    if (_country == null ||
        Validators.email(_email.text) != null ||
        _phoneValidator(_phone.text) != null ||
        Validators.password(_password.text) != null ||
        Validators.confirmPassword(_confirm.text, _password.text) != null) {
      return false;
    }
    if (_type == _AccountType.merchant) {
      return Validators.required(_businessName.text, 'Business name') == null &&
          Validators.required(_businessType.text, 'Business type') == null;
    }
    return Validators.required(_firstName.text, 'First name') == null &&
        Validators.required(_lastName.text, 'Last name') == null;
  }

  bool get _canSubmit => _detailsAreValid && _termsAccepted && !_loading;

  @override
  void initState() {
    super.initState();
  }

  /// Location assist: when the live catalogue resolves, preselect the
  /// country matching the device locale. The user still confirms or changes
  /// it — the flag just saves a search for the common case.
  void _prefillCountry(List<ServiceOption> countries) {
    if (_country != null) return;
    final region =
        WidgetsBinding.instance.platformDispatcher.locale.countryCode;
    if (region == null || region.isEmpty) return;
    for (final c in countries) {
      if (c.id.toUpperCase() == region.toUpperCase()) {
        _country = _PickedCountry(
          iso: c.id.toUpperCase(),
          name: c.name,
          dialCode: c.dialCode ?? '', flagUrl: c.flagUrl,
        );
        return;
      }
    }
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _email,
      _phone,
      _password,
      _confirm,
      _businessName,
      _businessType,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _selectType(_AccountType type) {
    setState(() => _type = type);
    if (_step != 0) return;
    // Tap selects and flows into details after a beat — the step chips
    // animate the progress.
    Future.delayed(const Duration(milliseconds: 350), () {
      if (mounted && _step == 0) setState(() => _step = 1);
    });
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    } else {
      context.pop();
    }
  }

  void _continueToConfirm() {
    setState(() => _apiError = null);
    final formValid = _detailsFormKey.currentState?.validate() ?? false;
    if (!formValid) return;
    if (_country == null) {
      setState(() => _apiError = 'Pick your country to continue.');
      return;
    }
    setState(() => _step = 2);
  }

  String? _phoneValidator(String? v) {
    final digits = (v ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return 'Phone number is required';
    if (_country?.iso == 'GH') {
      if (!RegExp(r'^0\d{9}$').hasMatch(digits)) {
        return 'Enter a valid Ghana number (e.g. 0244588584)';
      }
    } else if (digits.length < 6 || digits.length > 15) {
      return 'Enter a valid phone number';
    }
    return null;
  }

  Future<void> _submit() async {
    setState(() => _apiError = null);
    if (!_detailsAreValid) {
      setState(() => _apiError = 'Complete all required details to continue.');
      return;
    }
    if (!_termsAccepted) {
      setState(
        () => _apiError = 'Please accept the Terms of Service and Privacy Policy to continue.',
      );
      return;
    }
    setState(() => _loading = true);
    try {
      final notifier = ref.read(authSessionProvider.notifier);
      if (_type == _AccountType.personal) {
        await notifier.register(
          RegisterRequest(
            firstName: _firstName.text.trim(),
            lastName: _lastName.text.trim(),
            email: _email.text.trim(),
            phoneNumber: _phone.text.trim(),
            country: _country!.name,
            password: _password.text,
          ),
        );
      } else {
        await notifier.registerMerchant(
          MerchantRegisterRequest(
            name: _businessName.text.trim(),
            businessType: _businessType.text.trim(),
            email: _email.text.trim(),
            phoneNumber: _phone.text.trim(),
            country: _country!.name,
            password: _password.text,
          ),
        );
      }
      // Checkbox gates submission — record the versioned acceptance.
      unawaited(ref.read(policyStatusProvider.notifier).accept());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account created — sign in to continue.'),
          ),
        );
        context.go(AppRoutes.login);
      }
    } on ApiException catch (e) {
      setState(() => _apiError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickCountry() async {
    final picked = await showModalBottomSheet<_PickedCountry>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CountryPickerSheet(selectedIso: _country?.iso),
    );
    if (picked != null) setState(() => _country = picked);
  }

  @override
  Widget build(BuildContext context) {
    // Watching (not reading) the catalogue keeps the locale prefill live and
    // lets the picker sheet populate as soon as the list resolves.
    final countries = ref.watch(countriesProvider).valueOrNull;
    if (countries != null) _prefillCountry(countries);
    final scheme = Theme.of(context).colorScheme;
    final titles = switch (_type) {
      _AccountType.personal => const [
        'Create account',
        'Your details',
        'Almost done',
      ],
      _AccountType.merchant => const [
        'Create account',
        'Business details',
        'Almost done',
      ],
    };
    final subtitles = switch (_step) {
      0 => 'What brings you to Lidapay?',
      1 => 'A few details and you are set.',
      _ => 'Check everything, then go.',
    };

    return Scaffold(
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AuthHeroHeader(
            height: 200,
            title: titles[_step],
            subtitle: subtitles,
            onBack: _back,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
            child: Row(
              children: [
                _StepChip(label: 'Type', active: _step == 0, done: _step > 0),
                _Connector(active: _step > 0, scheme: scheme),
                _StepChip(
                  label: 'Details',
                  active: _step == 1,
                  done: _step > 1,
                ),
                _Connector(active: _step > 1, scheme: scheme),
                _StepChip(label: 'Confirm', active: _step == 2, done: false),
              ],
            ),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOut,
              transitionBuilder: (child, animation) => FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween(
                    begin: Offset(_step == 0 ? -0.06 : 0.06, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              ),
              child: switch (_step) {
                0 => _buildTypeStep(scheme),
                1 => _buildDetailsStep(scheme),
                _ => _buildConfirmStep(scheme),
              },
            ),
          ),
        ],
      ),
    );
  }

  // -- Step 0: account type --------------------------------------------------

  Widget _buildTypeStep(ColorScheme scheme) {
    return ListView(
      key: const ValueKey('step-type'),
      padding: const EdgeInsets.fromLTRB(24, 26, 24, 24),
      children: [
        _TypeCard(
          icon: Icons.person_rounded,
          title: 'Personal',
          subtitle:
              'Airtime, data, wallet, Lida Value and the shop — '
              'the everyday Lidapay account.',
          selected: _type == _AccountType.personal,
          onTap: () => _selectType(_AccountType.personal),
        ),
        const SizedBox(height: 14),
        _TypeCard(
          icon: Icons.storefront_rounded,
          title: 'Merchant',
          subtitle:
              'Accept payments and sell on Lidapay — for shops, '
              'agents and businesses.',
          selected: _type == _AccountType.merchant,
          onTap: () => _selectType(_AccountType.merchant),
        ),
        const SizedBox(height: 20),
        Text(
          'Tap a card to continue',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12.5, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }

  // -- Step 1: details -------------------------------------------------------

  Widget _buildDetailsStep(ColorScheme scheme) {
    final merchant = _type == _AccountType.merchant;
    return ListView(
      key: const ValueKey('step-details'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Form(
          key: _detailsFormKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (merchant) ...[
                AppTextField(
                  controller: _businessName,
                  label: 'Business name',
                  onChanged: (_) => setState(() {}),
                  validator: (v) => Validators.required(v, 'Business name'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _businessType,
                  label: 'Business type',
                  hint: 'Retail, agent, services…',
                  onChanged: (_) => setState(() {}),
                  validator: (v) => Validators.required(v, 'Business type'),
                  textInputAction: TextInputAction.next,
                ),
              ] else
                Row(
                  children: [
                    Expanded(
                      child: AppTextField(
                        controller: _firstName,
                        label: 'First name',
                        onChanged: (_) => setState(() {}),
                        validator: (v) => Validators.required(v, 'First name'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: AppTextField(
                        controller: _lastName,
                        label: 'Last name',
                        onChanged: (_) => setState(() {}),
                        validator: (v) => Validators.required(v, 'Last name'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _email,
                label: 'Email',
                hint: 'you@example.com',
                onChanged: (_) => setState(() {}),
                keyboardType: TextInputType.emailAddress,
                validator: Validators.email,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              AppTextField(
                controller: _phone,
                label: 'Phone number',
                hint: _country?.iso == 'GH' || _country == null
                    ? '0244588584'
                    : '${_country!.dialCode} …',
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() {}),
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: _phoneValidator,
                textInputAction: TextInputAction.next,
              ),
              const SizedBox(height: 16),
              _CountryField(
                key: const Key('register-country-field'),
                country: _country,
                onTap: _pickCountry,
              ),
              const SizedBox(height: 18),
              ValueListenableBuilder(
                valueListenable: _password,
                builder: (context, value, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppTextField(
                      fieldKey: const ValueKey('register-password-input'),
                      controller: _password,
                      label: 'Password',
                      hint: 'At least 6 characters',
                      obscureText: true,
                      onChanged: (_) => setState(() {}),
                      validator: Validators.password,
                      textInputAction: TextInputAction.next,
                    ),
                    if (value.text.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      _StrengthMeter(strength: PasswordStrength.of(value.text)),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              AppTextField(
                fieldKey: const ValueKey('register-confirm-password-input'),
                controller: _confirm,
                label: 'Confirm password',
                obscureText: true,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _continueToConfirm(),
                validator: (v) => Validators.confirmPassword(v, _password.text),
              ),
              if (_apiError != null) ...[
                const SizedBox(height: 18),
                _ErrorBanner(message: _apiError!, scheme: scheme),
              ],
              const SizedBox(height: 24),
              AppButton(
                label: 'Continue',
                icon: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                ),
                onPressed: _detailsAreValid ? _continueToConfirm : null,
                  ),
            ],
          ),
        ),
      ],
    );
  }

  // -- Step 2: confirm --------------------------------------------------------

  Widget _buildConfirmStep(ColorScheme scheme) {
    final merchant = _type == _AccountType.merchant;
    final rows = <(String, String)>[
      ('Account type', merchant ? 'Merchant' : 'Personal'),
      if (merchant)
        ('Business', '${_businessName.text} · ${_businessType.text}')
      else
        ('Name', '${_firstName.text} ${_lastName.text}'.trim()),
      ('Email', _email.text),
      ('Phone', _phone.text),
      if (_country != null)
        ('Country', '${_country!.iso} · ${_country!.name}'),
      ('Password', '••••••••'),
    ];

    return ListView(
      key: const ValueKey('step-confirm'),
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),
          child: Column(
            children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 18,
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                Row(
                  children: [
                    SizedBox(
                      width: 110,
                      child: Text(
                        rows[i].$1,
                        style: TextStyle(
                          fontSize: 13,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        rows[i].$2,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Icon(Icons.verified_user_outlined, size: 16, color: scheme.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Finish KYC later from your Profile — it unlocks higher '
                'limits.',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _TermsGate(
          accepted: _termsAccepted,
          onChanged: (v) => setState(() => _termsAccepted = v),
        ),
        if (_apiError != null) ...[
          const SizedBox(height: 14),
          _ErrorBanner(message: _apiError!, scheme: scheme),
        ],
        const SizedBox(height: 20),
        AppButton(
          label: merchant ? 'Register business' : 'Create account',
          loading: _loading,
          onPressed: _canSubmit ? _submit : null,
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'Already have an account? ',
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
            GestureDetector(
              onTap: () => context.pop(),
              child: Text(
                'Sign in',
                style: TextStyle(
                  color: scheme.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Supporting widgets
// ---------------------------------------------------------------------------

class _Connector extends StatelessWidget {
  const _Connector({required this.active, required this.scheme});

  final bool active;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        height: 1.5,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        color: active
            ? scheme.primary.withValues(alpha: 0.6)
            : scheme.onSurfaceVariant.withValues(alpha: 0.2),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return AnimatedScale(
      scale: selected ? 1.0 : 0.985,
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(22),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 220),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                width: selected ? 1.6 : 1,
                color: selected
                    ? scheme.primary
                    : (isDark ? Colors.white10 : const Color(0xFFECEAF2)),
              ),
              gradient: selected
                  ? LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        scheme.primary.withValues(alpha: 0.09),
                        AppColors.violet.withValues(alpha: 0.05),
                      ],
                    )
                  : null,
            ),
            child: Row(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    gradient: selected
                        ? AppColors.brandGradient
                        : LinearGradient(
                            colors: [
                              scheme.onSurfaceVariant.withValues(alpha: 0.14),
                              scheme.onSurfaceVariant.withValues(alpha: 0.08),
                            ],
                          ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(
                    icon,
                    size: 26,
                    color: selected ? Colors.white : scheme.onSurfaceVariant,
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
                          fontSize: 16.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12.5,
                          height: 1.4,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: selected ? 1 : 0,
                  child: const Icon(
                    Icons.check_circle_rounded,
                    color: AppColors.primary,
                    size: 24,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CountryField extends StatelessWidget {
  const _CountryField({super.key, required this.country, required this.onTap});

  final _PickedCountry? country;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Country',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: scheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 7),
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: country == null
                    ? scheme.primary.withValues(alpha: 0.45)
                    : scheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                if (country != null)
                  CountryFlagBadge(isoCode: country!.iso, flagUrl: country!.flagUrl, size: 22)
                else
                  Icon(Icons.public_rounded, size: 20, color: scheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    country?.name ?? 'Choose your country',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      color: country == null
                          ? scheme.onSurfaceVariant
                          : scheme.onSurface,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: scheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Searchable bottom sheet over the live `/reloadly/country-list` catalogue.
class _CountryPickerSheet extends ConsumerStatefulWidget {
  const _CountryPickerSheet({required this.selectedIso});

  final String? selectedIso;

  @override
  ConsumerState<_CountryPickerSheet> createState() =>
      _CountryPickerSheetState();
}

class _CountryPickerSheetState extends ConsumerState<_CountryPickerSheet> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<ServiceOption> _filtered(List<ServiceOption> countries) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return countries;
    return countries
        .where(
          (c) =>
              c.name.toLowerCase().contains(q) ||
              c.id.toLowerCase().contains(q) ||
              (c.dialCode ?? '').toLowerCase().contains(q) ||
              (c.meta ?? '').toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final media = MediaQuery.of(context);
    final bottomInset = media.padding.bottom;
    final countriesAsync = ref.watch(countriesProvider);
    final countries = countriesAsync.valueOrNull ?? const <ServiceOption>[];
    final filtered = _filtered(countries);

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
      child: Material(
        color: isDark ? AppColors.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: media.size.height * 0.8,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 14, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Choose your country',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            countries.isEmpty
                                ? 'Search supported destinations'
                                : '${countries.length} destinations available',
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close country picker',
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search name, code or dial code',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Clear search',
                            onPressed: () {
                              _search.clear();
                              setState(() => _query = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                    filled: true,
                    fillColor: isDark
                        ? AppColors.darkInput
                        : scheme.surfaceContainerHighest.withValues(
                            alpha: 0.55,
                          ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(
                        color: scheme.outlineVariant.withValues(alpha: 0.45),
                      ),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: countriesAsync.isLoading && countries.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? Center(
                        child: Text(
                          countries.isEmpty
                              ? 'Country list is unavailable — try again later.'
                              : 'No countries match “$_query”.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          2,
                          12,
                          16 + bottomInset,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 5),
                        itemBuilder: (context, index) {
                          final c = filtered[index];
                          final picked = _PickedCountry(
                            iso: c.id.toUpperCase(),
                            name: c.name,
                            dialCode: c.dialCode ?? '', flagUrl: c.flagUrl,
                          );
                          final selected = picked.iso == widget.selectedIso;
                          return Material(
                            color: selected
                                ? AppColors.primary.withValues(
                                    alpha: isDark ? 0.22 : 0.08,
                                  )
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: ListTile(
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                                side: BorderSide(
                                  color: selected
                                      ? AppColors.primary.withValues(alpha: 0.4)
                                      : Colors.transparent,
                                ),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 3,
                              ),
                              leading: Container(
                                width: 42,
                                height: 42,
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.06)
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(
                                    color: scheme.outlineVariant.withValues(
                                      alpha: 0.35,
                                    ),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: CountryFlagBadge(
                                  isoCode: picked.iso,
                                  flagUrl: picked.flagUrl,
                                  size: 26,
                                ),
                              ),
                              title: Text(
                                c.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              subtitle: Text(
                                [
                                  if (picked.dialCode.isNotEmpty)
                                    picked.dialCode.startsWith('+')
                                        ? picked.dialCode
                                        : '+${picked.dialCode}',
                                  picked.iso,
                                  if (c.meta?.isNotEmpty == true) c.meta!,
                                ].join('  ·  '),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                              trailing: selected
                                  ? const Icon(
                                      Icons.check_circle_rounded,
                                      color: AppColors.primary,
                                    )
                                  : Icon(
                                      Icons.chevron_right_rounded,
                                      color: scheme.onSurfaceVariant,
                                    ),
                              onTap: () => Navigator.pop(context, picked),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.scheme});

  final String message;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.error.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.error_outline_rounded, color: scheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: scheme.error, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepChip extends StatelessWidget {
  const _StepChip({
    required this.label,
    required this.active,
    required this.done,
  });

  final String label;
  final bool active;
  final bool done;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = done || active ? scheme.primary : scheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 24,
          height: 24,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: done || active
                ? scheme.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: done || active ? 0.6 : 0.35),
            ),
          ),
          child: Icon(
            done ? Icons.check_rounded : Icons.circle,
            size: done ? 14 : 6,
            color: color,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: done || active ? scheme.onSurface : scheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _StrengthMeter extends StatelessWidget {
  const _StrengthMeter({required this.strength});

  final PasswordStrength strength;

  @override
  Widget build(BuildContext context) {
    const segments = 4;
    final filled = switch (strength) {
      PasswordStrength.empty => 0,
      PasswordStrength.weak => 1,
      PasswordStrength.fair => 2,
      PasswordStrength.good => 3,
      PasswordStrength.strong => 4,
    };
    final color = switch (strength) {
      PasswordStrength.weak => AppColors.error,
      PasswordStrength.fair => AppColors.warning,
      PasswordStrength.good => AppColors.success,
      PasswordStrength.strong => AppColors.primary,
      PasswordStrength.empty => Colors.transparent,
    };

    return Row(
      children: [
        for (var i = 0; i < segments; i++)
          Expanded(
            child: Container(
              height: 4,
              margin: EdgeInsets.only(right: i < segments - 1 ? 6 : 0),
              decoration: BoxDecoration(
                color: i < filled
                    ? color
                    : Theme.of(context).colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        const SizedBox(width: 10),
        Text(
          strength.label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// Registration gate: the account can't be created until the user ticks
/// the box. Both document names deep-link into the legal module.
class _TermsGate extends StatelessWidget {
  const _TermsGate({required this.accepted, required this.onChanged});

  final bool accepted;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => onChanged(!accepted),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accepted
                ? scheme.primary.withValues(alpha: 0.5)
                : scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              height: 22,
              child: Checkbox(
                value: accepted,
                onChanged: (v) => onChanged(v ?? false),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: scheme.onSurfaceVariant,
                  ),
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _InlineDocLink(
                        label: 'Terms of Service',
                        docId: 'terms',
                      ),
                    ),
                    const TextSpan(text: ' and the '),
                    WidgetSpan(
                      alignment: PlaceholderAlignment.baseline,
                      baseline: TextBaseline.alphabetic,
                      child: _InlineDocLink(
                        label: 'Privacy Policy',
                        docId: 'privacy',
                      ),
                    ),
                    const TextSpan(
                      text:
                          ', including how payments, refunds '
                          'and Lida Value are handled.',
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InlineDocLink extends StatelessWidget {
  const _InlineDocLink({required this.label, required this.docId});

  final String label;
  final String docId;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => context.push('${AppRoutes.legal}/$docId'),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: scheme.primary,
          decoration: TextDecoration.underline,
          decorationColor: scheme.primary.withValues(alpha: 0.5),
        ),
      ),
    );
  }
}
