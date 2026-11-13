class Validators {
  Validators._();

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Email is required';
    final re = RegExp(r'^[\w.+-]+@[\w-]+\.[\w.]+$');
    if (!re.hasMatch(v)) return 'Enter a valid email address';
    return null;
  }

  /// Ghana format per the API spec: 0xxxxxxxx (10 digits starting with 0).
  static String? phone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^0\d{9}$').hasMatch(v)) {
      return 'Enter a valid Ghana number (e.g. 0244588584)';
    }
    return null;
  }

  /// Profile/contact numbers may carry a country dial code — accepts
  /// `+233…`, `233…` or the local `0…` form (6–15 digits total).
  static String? internationalPhone(String? value) {
    final v = (value ?? '').replaceAll(RegExp(r'[\s\-()]'), '');
    if (v.isEmpty) return 'Phone number is required';
    if (!RegExp(r'^\+?\d{6,15}$').hasMatch(v)) {
      return 'Enter a valid number with country code (e.g. +233244588584)';
    }
    return null;
  }

  /// Either an email address or a phone number (local or international) —
  /// used where the backend accepts `{email}` or `{phoneNumber}`.
  static String? emailOrPhone(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your email or phone number';
    if (v.contains('@')) return email(v);
    if (!RegExp(r'^\+?\d[\d\s\-()]{5,}$').hasMatch(v)) {
      return 'Enter a valid email or phone number';
    }
    return null;
  }

  static String? required(String? value, [String field = 'This field']) {
    if (value == null || value.trim().isEmpty) return '$field is required';
    return null;
  }

  /// Spec minimum: 6 characters.
  static String? password(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Password is required';
    if (v.length < 6) return 'Password must be at least 6 characters';
    return null;
  }

  static String? confirmPassword(String? value, String password) {
    if (value == null || value.isEmpty) return 'Please confirm your password';
    if (value != password) return 'Passwords do not match';
    return null;
  }

  static String? otp(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Enter your 6-digit verification code';
    if (!RegExp(r'^\d{6}$').hasMatch(v)) {
      return 'Code must be 6 digits';
    }
    return null;
  }
}

enum PasswordStrength {
  empty(''),
  weak('Weak'),
  fair('Fair'),
  good('Good'),
  strong('Strong');

  const PasswordStrength(this.label);
  final String label;

  static PasswordStrength of(String password) {
    if (password.isEmpty) return empty;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'\d').hasMatch(password)) score++;
    if (RegExp(r'[^A-Za-z0-9]').hasMatch(password)) score++;
    return switch (score) {
      0 || 1 => weak,
      2 || 3 => fair,
      4 => good,
      _ => strong,
    };
  }
}
