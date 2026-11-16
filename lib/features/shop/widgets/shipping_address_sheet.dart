import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../auth/data/auth_models.dart';
import '../data/shop_models.dart';
import 'delivery_pin_screen.dart';

/// Collects the `shippingAddress` the shop checkout contract requires.
/// The backend only accepts the postal/contact fields below — no GPS
/// coordinates, courier objects or extra keys are sent. Returns null when
/// the customer dismisses the sheet.
Future<ShippingAddress?> showShippingAddressSheet({
  required BuildContext context,
  UserProfile? user,
  ShippingAddress? initial,
}) {
  return showModalBottomSheet<ShippingAddress>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _ShippingAddressSheet(user: user, initial: initial),
  );
}

class _ShippingAddressSheet extends StatefulWidget {
  const _ShippingAddressSheet({required this.user, this.initial});

  final UserProfile? user;
  final ShippingAddress? initial;

  @override
  State<_ShippingAddressSheet> createState() => _ShippingAddressSheetState();
}

class _ShippingAddressSheetState extends State<_ShippingAddressSheet> {
  final _formKey = GlobalKey<FormState>();
  late final _fullName = TextEditingController(
    text: widget.initial?.fullName ?? widget.user?.fullName ?? '',
  );
  late final _phone = TextEditingController(
    text: widget.initial?.phone ?? widget.user?.phoneNumber ?? '',
  );
  late final _email = TextEditingController(
    text: widget.initial?.email ?? widget.user?.email ?? '',
  );
  late final _addressLine1 = TextEditingController(
    text: widget.initial?.addressLine1 ?? widget.user?.street ?? '',
  );
  late final _addressLine2 = TextEditingController(
    text: widget.initial?.addressLine2 ?? '',
  );
  late final _city = TextEditingController(
    text: widget.initial?.city ?? widget.user?.city ?? '',
  );
  late final _region = TextEditingController(
    text:
        widget.initial?.region ??
        ((widget.user?.region.isNotEmpty ?? false)
            ? widget.user!.region
            : 'Greater Accra'),
  );
  late final _country = TextEditingController(
    text:
        widget.initial?.country ??
        ((widget.user?.country.isNotEmpty ?? false)
            ? widget.user!.country
            : 'Ghana'),
  );
  late final _postalCode = TextEditingController(
    text: widget.initial?.postalCode ?? widget.user?.digitalAddress ?? '',
  );
  late final _instructions = TextEditingController(
    text: widget.initial?.deliveryInstructions ?? '',
  );

  /// Optional customer delivery-pin coordinates. Sent only when both lat/lng
  /// are present so customers who decline map/location can still check out
  /// with a manual street address.
  DeliveryPin? _pin;

  @override
  void initState() {
    super.initState();
    final lat = widget.initial?.latitude;
    final lng = widget.initial?.longitude;
    if (lat != null && lng != null) {
      _pin = (latitude: lat, longitude: lng);
    }
  }

  @override
  void dispose() {
    for (final c in [
      _fullName,
      _phone,
      _email,
      _addressLine1,
      _addressLine2,
      _city,
      _region,
      _country,
      _postalCode,
      _instructions,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickPin() async {
    final pin = await showDeliveryPinPicker(
      context: context,
      initialLatitude: _pin?.latitude ?? widget.initial?.latitude,
      initialLongitude: _pin?.longitude ?? widget.initial?.longitude,
    );
    if (pin == null || !mounted) return;
    setState(() {
      _pin = pin;
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    HapticFeedback.mediumImpact();
    Navigator.of(context).pop(
      ShippingAddress(
        fullName: _fullName.text.trim(),
        phone: _phone.text.trim(),
        email: _email.text.trim(),
        addressLine1: _addressLine1.text.trim(),
        addressLine2: _addressLine2.text.trim(),
        city: _city.text.trim(),
        region: _region.text.trim(),
        country: _country.text.trim(),
        postalCode: _postalCode.text.trim(),
        deliveryInstructions: _instructions.text.trim(),
        latitude: _pin?.latitude,
        longitude: _pin?.longitude,
      ),
    );
  }

  Widget _pinSection(ColorScheme scheme) {
    final pin = _pin;
    return InkWell(
      onTap: _pickPin,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: pin != null
              ? AppColors.primaryTint.withValues(alpha: 0.5)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              pin != null ? Icons.place_rounded : Icons.add_location_alt_rounded,
              size: 22,
              color: pin != null ? AppColors.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Delivery pin on map',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    pin != null
                        ? '${pin.latitude.toStringAsFixed(5)}, '
                              '${pin.longitude.toStringAsFixed(5)} — tap to adjust'
                        : 'Optional — tap to drop a pin for courier routing',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkSurface : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 14, 24, 28),
          child: Form(
            key: _formKey,
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
                  'Delivery Address',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  'Where should the shop deliver this order?',
                  style: TextStyle(
                    fontSize: 12.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                AppTextField(
                  controller: _fullName,
                  label: 'Recipient full name',
                  validator: (v) => Validators.required(v, 'Full name'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _phone,
                  label: 'Contact phone',
                  hint: '0244123456',
                  keyboardType: TextInputType.phone,
                  maxLength: 16,
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[\d+]')),
                  ],
                  validator: Validators.internationalPhone,
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _addressLine1,
                  label: 'Street address / House No.',
                  hint: '12 Osu Avenue, near Total Station',
                  validator: (v) => Validators.required(v, 'Street address'),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _addressLine2,
                  label: 'Apartment / Landmark (optional)',
                  hint: 'Flat 4B',
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
                        validator: (v) => Validators.required(v, 'City'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        controller: _region,
                        label: 'Region',
                        hint: 'Greater Accra',
                        validator: (v) => Validators.required(v, 'Region'),
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
                        controller: _postalCode,
                        label: 'Digital / Postal address (optional)',
                        hint: 'GA-184-4521',
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: AppTextField(
                        controller: _country,
                        label: 'Country',
                        validator: (v) => Validators.required(v, 'Country'),
                        textInputAction: TextInputAction.next,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _email,
                  label: 'Email (optional)',
                  hint: 'you@example.com',
                  keyboardType: TextInputType.emailAddress,
                  validator: (v) =>
                      (v ?? '').trim().isEmpty ? null : Validators.email(v),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 14),
                AppTextField(
                  controller: _instructions,
                  label: 'Delivery instructions (optional)',
                  hint: 'Call when you arrive',
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                ),
                const SizedBox(height: 16),
                _pinSection(scheme),
                const SizedBox(height: 22),
                AppButton(
                  label: 'Continue to Payment',
                  icon: const Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                  onPressed: _submit,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
