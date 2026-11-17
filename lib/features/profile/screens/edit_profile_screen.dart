import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/location_service.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/surface_card.dart';
import '../../auth/data/auth_models.dart';
import '../../auth/providers.dart';

/// Personal details plus email/phone verification. The API has no document
/// KYC endpoint, so this screen covers everything users can update live.
class EditProfileScreen extends ConsumerStatefulWidget {
  const EditProfileScreen({super.key});

  @override
  ConsumerState<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends ConsumerState<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _email;
  late final TextEditingController _phone;
  late final TextEditingController _street;
  late final TextEditingController _city;
  late final TextEditingController _region;
  late final TextEditingController _country;
  late final TextEditingController _digitalAddress;
  double? _latitude;
  double? _longitude;

  bool _saving = false;
  bool _locating = false;
  bool _sendingEmail = false;
  bool _sendingPhone = false;
  String? _apiError;

  @override
  void initState() {
    super.initState();
    final user = ref.read(authSessionProvider)?.user;
    _firstName = TextEditingController(text: user?.firstName ?? '');
    _lastName = TextEditingController(text: user?.lastName ?? '');
    _email = TextEditingController(text: user?.email ?? '');
    _phone = TextEditingController(text: user?.phoneNumber ?? '');
    _street = TextEditingController(text: user?.street ?? '');
    _city = TextEditingController(text: user?.city ?? '');
    _region = TextEditingController(
      text: (user?.region.isNotEmpty ?? false) ? user!.region : 'Greater Accra',
    );
    _country = TextEditingController(
      text: (user?.country.isNotEmpty ?? false) ? user!.country : 'Ghana',
    );
    _digitalAddress = TextEditingController(text: user?.digitalAddress ?? '');
    _latitude = user?.latitude;
    _longitude = user?.longitude;
  }

  @override
  void dispose() {
    for (final c in [
      _firstName,
      _lastName,
      _email,
      _phone,
      _street,
      _city,
      _region,
      _country,
      _digitalAddress,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _fetchLatestLocation() async {
    setState(() => _locating = true);
    try {
      final loc = await ref.read(locationServiceProvider).getCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        _notify(
          'Could not detect GPS location. Enable location access or type your address below.',
          isError: true,
        );
        return;
      }
      setState(() {
        _latitude = loc.latitude;
        _longitude = loc.longitude;
        if (loc.addressLine != null && loc.addressLine!.isNotEmpty) {
          _street.text = loc.addressLine!;
        }
        if (loc.city != null && loc.city!.isNotEmpty) {
          _city.text = loc.city!;
        }
        if (loc.region != null && loc.region!.isNotEmpty) {
          _region.text = loc.region!;
        }
        if (loc.country != null && loc.country!.isNotEmpty) {
          _country.text = loc.country!;
        }
        if (_digitalAddress.text.trim().isEmpty) {
          _digitalAddress.text =
              'GPS ${loc.latitude.toStringAsFixed(5)}, ${loc.longitude.toStringAsFixed(5)}';
        }
      });
      HapticFeedback.lightImpact();
      _notify('Latest GPS location captured.', isError: false);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    setState(() => _apiError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(authSessionProvider.notifier)
          .updateProfile(
            ProfileUpdateRequest(
              firstName: _firstName.text.trim(),
              lastName: _lastName.text.trim(),
              email: _email.text.trim(),
              phoneNumber: _phone.text.trim(),
              street: _street.text.trim(),
              city: _city.text.trim(),
              region: _region.text.trim(),
              country: _country.text.trim(),
              digitalAddress: _digitalAddress.text.trim(),
              latitude: _latitude,
              longitude: _longitude,
            ),
          );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile & KYC address updated.')),
      );
      context.pop();
    } on ApiException catch (e) {
      if (mounted) setState(() => _apiError = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resend({required bool email}) async {
    setState(() => email ? _sendingEmail = true : _sendingPhone = true);
    try {
      final notifier = ref.read(authSessionProvider.notifier);
      await (email
          ? notifier.resendEmailVerification()
          : notifier.resendPhoneVerification());
      if (!mounted) return;
      if (email) {
        _notify(
          'Verification email sent — check your inbox for the link. '
          'If it expired, request another.',
          isError: false,
        );
      } else {
        // SMS codes need confirming — open the code sheet right away.
        await _promptPhoneCode();
      }
    } on ApiException catch (e) {
      if (mounted) _notify(e.message, isError: true);
    } finally {
      if (mounted) {
        setState(() => email ? _sendingEmail = false : _sendingPhone = false);
      }
    }
  }

  /// POST /api/v1/users/verify-phone — the SMS code from the resend call.
  /// The code went to the *saved* profile number, not the editable field.
  Future<void> _promptPhoneCode() async {
    final savedPhone =
        ref.read(authSessionProvider)?.user.phoneNumber ?? _phone.text.trim();
    final verified = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PhoneCodeSheet(phone: savedPhone),
    );
    if (verified == true && mounted) {
      _notify('Phone verified — thank you.', isError: false);
    }
  }

  void _notify(String message, {required bool isError}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? scheme.error : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final user = ref.watch(authSessionProvider)?.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      body: Column(
        children: [
          const _ProfileHeroHeader(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 140),
              children: [
                _VerificationCard(
                  email: user?.email ?? '',
                  phone: user?.phoneNumber ?? '',
                  emailVerified: user?.emailVerified ?? false,
                  phoneVerified: user?.phoneVerified ?? false,
                  sendingEmail: _sendingEmail,
                  sendingPhone: _sendingPhone,
                  contactChanged:
                      _email.text.trim() != (user?.email ?? '') ||
                      _phone.text.trim() != (user?.phoneNumber ?? ''),
                  onResendEmail: () => _resend(email: true),
                  onResendPhone: () => _resend(email: false),
                ),
                const SizedBox(height: 28),
                const _SectionTitle('Personal details'),
                SurfaceCard(
                  padding: const EdgeInsets.all(20),
                  color: isDark
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                      : null,
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: AppTextField(
                                controller: _firstName,
                                label: 'First name',
                                validator: (v) =>
                                    Validators.required(v, 'First name'),
                                textInputAction: TextInputAction.next,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: AppTextField(
                                controller: _lastName,
                                label: 'Last name',
                                validator: (v) =>
                                    Validators.required(v, 'Last name'),
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
                          keyboardType: TextInputType.emailAddress,
                          validator: Validators.email,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        AppTextField(
                          controller: _phone,
                          label: 'Phone number',
                          hint: '+233244588584',
                          keyboardType: TextInputType.phone,
                          maxLength: 16,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[\d+]')),
                          ],
                          validator: Validators.internationalPhone,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) => setState(() {}),
                          onFieldSubmitted: (_) => _save(),
                        ),
                        const SizedBox(height: 20),
                        Divider(
                          color: scheme.onSurface.withValues(alpha: 0.08),
                        ),
                        const SizedBox(height: 12),
                        _ReadOnlyRow(
                          label: 'Username',
                          value: user?.username.isNotEmpty == true
                              ? user!.username
                              : '—',
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 28),
                Row(
                  children: [
                    const Expanded(
                      child: _SectionTitle('Delivery address & location (KYC)'),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TextButton.icon(
                        onPressed: _locating ? null : _fetchLatestLocation,
                        icon: _locating
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.my_location_rounded, size: 16),
                        label: Text(
                          _locating ? 'Locating…' : 'Get Latest Location',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SurfaceCard(
                  padding: const EdgeInsets.all(20),
                  color: isDark
                      ? scheme.surfaceContainerHighest.withValues(alpha: 0.5)
                      : null,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_latitude != null && _longitude != null) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.success.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.gps_fixed_rounded,
                                size: 16,
                                color: AppColors.success,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Pinned GPS: ${_latitude!.toStringAsFixed(5)}, ${_longitude!.toStringAsFixed(5)}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.success,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 14),
                      ],
                      AppTextField(
                        controller: _street,
                        label: 'Street address / House No.',
                        hint:
                            '12 Osu Oxford Street, near Total Filling Station',
                        textInputAction: TextInputAction.next,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _city,
                              label: 'City / Town',
                              hint: 'Accra',
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _region,
                              label: 'Region / State',
                              hint: 'Greater Accra',
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: AppTextField(
                              controller: _digitalAddress,
                              label: 'Digital Address / Landmark',
                              hint: 'GA-184-4521',
                              textInputAction: TextInputAction.next,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: AppTextField(
                              controller: _country,
                              label: 'Country',
                              hint: 'Ghana',
                              textInputAction: TextInputAction.done,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (_apiError != null) ...[
                  const SizedBox(height: 18),
                  _ErrorBanner(message: _apiError!),
                ],
                const SizedBox(height: 24),
                AppButton(
                  label: 'Save changes',
                  loading: _saving,
                  onPressed: _save,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Brand-gradient header matching the service wizards — pinned above the
/// form, no plain AppBar.
class _ProfileHeroHeader extends StatelessWidget {
  const _ProfileHeroHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(gradient: AppColors.heroGradient),
      padding: EdgeInsets.fromLTRB(
        20,
        MediaQuery.paddingOf(context).top + 8,
        20,
        16,
      ),
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
              onPressed: () => Navigator.of(context).pop(),
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
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Profile & KYC',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                  ),
                ),
                Text(
                  'Details, verification & identity',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.verified_user_outlined,
              color: Colors.white,
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

/// Six-digit SMS code entry — confirms `POST /users/verify-phone`.
class _PhoneCodeSheet extends ConsumerStatefulWidget {
  const _PhoneCodeSheet({required this.phone});

  final String phone;

  @override
  ConsumerState<_PhoneCodeSheet> createState() => _PhoneCodeSheetState();
}

class _PhoneCodeSheetState extends ConsumerState<_PhoneCodeSheet> {
  final _code = TextEditingController();
  bool _submitting = false;
  String? _error;

  Future<void> _confirm() async {
    final code = _code.text.trim();
    if (code.length != 6) {
      setState(() => _error = 'Enter the 6-digit code we sent you.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref
          .read(authSessionProvider.notifier)
          .confirmPhoneVerification(phoneNumber: widget.phone, code: code);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _submitting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Verification failed — check the code and try again.';
          _submitting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'Enter the SMS code',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              'We sent a 6-digit code to ${widget.phone}.',
              style: TextStyle(fontSize: 13.5, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 18),
            AppTextField(
              controller: _code,
              label: 'Verification code',
              hint: '••••••',
              keyboardType: TextInputType.number,
              maxLength: 6,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onFieldSubmitted: (_) => _confirm(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              _ErrorBanner(message: _error!),
            ],
            const SizedBox(height: 18),
            AppButton(
              label: 'Verify phone',
              loading: _submitting,
              onPressed: _submitting ? null : _confirm,
            ),
          ],
        ),
      ),
    );
  }
}

class _VerificationCard extends StatelessWidget {
  const _VerificationCard({
    required this.email,
    required this.phone,
    required this.emailVerified,
    required this.phoneVerified,
    required this.sendingEmail,
    required this.sendingPhone,
    required this.contactChanged,
    required this.onResendEmail,
    required this.onResendPhone,
  });

  final String email;
  final String phone;
  final bool emailVerified;
  final bool phoneVerified;
  final bool sendingEmail;
  final bool sendingPhone;

  /// True while the form's email/phone differs from the saved profile —
  /// the backend resets verification flags when contacts change.
  final bool contactChanged;
  final VoidCallback onResendEmail;
  final VoidCallback onResendPhone;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SurfaceCard(
      padding: const EdgeInsets.all(22),
      radius: 28,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: AppColors.brandGradient,
                  borderRadius: BorderRadius.circular(15),
                  boxShadow: AppShadows.glow(AppColors.primary, alpha: 0.28),
                ),
                child: const Icon(
                  Icons.verified_user_rounded,
                  color: Colors.white,
                  size: 23,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Account verification',
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Confirm both contacts to secure your wallet.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ContactRow(
            icon: Icons.mail_outline_rounded,
            title: 'Email',
            value: email.isEmpty ? '—' : email,
            verified: emailVerified,
            sending: sendingEmail,
            onResend: onResendEmail,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Divider(color: scheme.onSurface.withValues(alpha: 0.07)),
          ),
          _ContactRow(
            icon: Icons.smartphone_rounded,
            title: 'Phone',
            value: phone.isEmpty ? '—' : phone,
            verified: phoneVerified,
            sending: sendingPhone,
            onResend: onResendPhone,
          ),
          if (contactChanged) ...[
            const SizedBox(height: 14),
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
                    'Saving a new email or phone number will ask you to verify the new contact.',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: scheme.onSurfaceVariant,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.icon,
    required this.title,
    required this.value,
    required this.verified,
    required this.sending,
    required this.onResend,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool verified;
  final bool sending;
  final VoidCallback onResend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final statusColor = verified ? AppColors.success : AppColors.warning;

    return Row(
      children: [
        Icon(icon, size: 20, color: scheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  letterSpacing: 0.4,
                ),
              ),
              const SizedBox(height: 1),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 3),
              Row(
                children: [
                  Icon(
                    verified
                        ? Icons.check_circle_rounded
                        : Icons.schedule_rounded,
                    size: 13,
                    color: statusColor,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    verified ? 'Verified' : 'Not verified',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: statusColor,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        if (!verified)
          TextButton(
            onPressed: sending ? null : onResend,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              minimumSize: const Size(0, 36),
            ),
            child: sending
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Resend'),
          ),
      ],
    );
  }
}

class _ReadOnlyRow extends StatelessWidget {
  const _ReadOnlyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            color: scheme.onSurface.withValues(alpha: 0.75),
          ),
        ),
        const SizedBox(width: 6),
        Icon(
          Icons.lock_outline_rounded,
          size: 14,
          color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
