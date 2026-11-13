import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.fieldKey,
    this.label,
    this.hint,
    this.validator,
    this.keyboardType,
    this.obscureText = false,
    this.prefixIcon,
    this.suffixIcon,
    this.textInputAction,
    this.onChanged,
    this.onFieldSubmitted,
    this.maxLength,
    this.inputFormatters,
    this.large = false,
  });

  final TextEditingController? controller;
  final Key? fieldKey;
  final String? label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputType? keyboardType;
  final bool obscureText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onFieldSubmitted;
  final int? maxLength;
  final List<TextInputFormatter>? inputFormatters;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(
            label!,
            style: large
                ? Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurface,
                  )
                : Theme.of(context).textTheme.labelLarge,
          ),
          SizedBox(height: large ? 10 : 8),
        ],
        TextFormField(
          key: fieldKey,
          controller: controller,
          validator: validator,
          keyboardType: keyboardType,
          obscureText: obscureText,
          textInputAction: textInputAction,
          onChanged: onChanged,
          onFieldSubmitted: onFieldSubmitted,
          maxLength: maxLength,
          inputFormatters: inputFormatters,
          style: large
              ? TextStyle(
                  fontSize: 17.5,
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                )
              : null,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: large
                ? TextStyle(
                    color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
                    fontSize: 16.5,
                    fontWeight: FontWeight.w500,
                  )
                : null,
            prefixIcon: prefixIcon,
            suffixIcon: suffixIcon,
            counterText: '',
            contentPadding: large
                ? const EdgeInsets.symmetric(horizontal: 22, vertical: 23)
                : null,
          ),
        ),
      ],
    );
  }
}
