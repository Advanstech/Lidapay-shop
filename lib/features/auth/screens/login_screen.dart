import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:local_auth/local_auth.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/app_button.dart';
import '../../../core/widgets/app_text_field.dart';
import '../../../core/widgets/auth_hero_header.dart';
import '../data/auth_models.dart';
import '../providers.dart';

enum _VerifyMode { otp, password }

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _localAuth = LocalAuthentication();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _otpControllers = List.generate(6, (_) => TextEditingController());
  final _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _obscure = true;
  bool _loading = false;
  bool _sendingOtp = false;
  String? _apiError;
  String? _otpStatusMessage;
  bool _inVerifyStep = false;
  _VerifyMode _verifyMode = _VerifyMode.otp;
  bool _canContinue = false;
  bool _canSignInPassword = false;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    _username.addListener(_onUsernameChanged);
    _password.addListener(_onPasswordChanged);
    for (final node in _otpFocusNodes) {
      node.addListener(() {
        if (mounted) setState(() {});
      });
    }
  }

  void _onUsernameChanged() {
    final hasText = _username.text.trim().isNotEmpty;
    if (_canContinue != hasText) {
      setState(() => _canContinue = hasText);
    }
  }

  void _onPasswordChanged() {
    final valid = Validators.password(_password.text) == null;
    if (_canSignInPassword != valid) {
      setState(() => _canSignInPassword = valid);
    }
  }

  String get _otpCode => _otpControllers.map((c) => c.text).join();

  bool get _canVerifyOtp => Validators.otp(_otpCode) == null;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _username.removeListener(_onUsernameChanged);
    _password.removeListener(_onPasswordChanged);
    _username.dispose();
    _password.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  void _startCooldown([int? seconds]) {
    _cooldownTimer?.cancel();
    setState(
      () =>
          _resendCooldown = seconds ?? AppConstants.otpResendCooldown.inSeconds,
    );
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendCooldown <= 1) {
        timer.cancel();
        setState(() => _resendCooldown = 0);
      } else {
        setState(() => _resendCooldown--);
      }
    });
  }

  Future<void> _onNext() async {
    final value = _username.text.trim();
    if (value.isEmpty) {
      setState(() => _apiError = 'Phone or email is required');
      return;
    }
    HapticFeedback.lightImpact();
    setState(() {
      _apiError = null;
      _inVerifyStep = true;
      _verifyMode = _VerifyMode.otp;
    });
    await _requestOtpChallenge(silentIfPasswordRequired: true);
    if (mounted && _verifyMode == _VerifyMode.otp) {
      _otpFocusNodes.first.requestFocus();
    }
  }

  Future<void> _requestOtpChallenge({
    bool silentIfPasswordRequired = false,
  }) async {
    final username = _username.text.trim();
    if (username.isEmpty || _sendingOtp) return;
    setState(() {
      _sendingOtp = true;
      if (!silentIfPasswordRequired) _apiError = null;
    });
    try {
      final challenge = await ref
          .read(authSessionProvider.notifier)
          .requestLoginOtp(
            username: username,
            password: _password.text.isEmpty ? null : _password.text,
          );
      if (!mounted) return;
      _startCooldown();
      setState(() {
        _otpStatusMessage = challenge.message;
        _apiError = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      if (silentIfPasswordRequired) {
        // The API requires the password before it issues a code — the OTP
        // pane is a dead end without a challenge, so land on the password
        // pane where the user can sign in or request the code. A 400 is
        // the expected "password is required" validation; anything else is
        // a real failure worth surfacing.
        setState(() {
          _verifyMode = _VerifyMode.password;
          if (e.statusCode != 400) _apiError = e.message;
        });
      } else {
        setState(() => _apiError = e.message);
      }
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  void _onBackToUsername() {
    HapticFeedback.selectionClick();
    setState(() {
      _inVerifyStep = false;
      _apiError = null;
    });
  }

  void _switchVerifyMode(_VerifyMode mode) {
    if (_verifyMode == mode) return;
    HapticFeedback.selectionClick();
    setState(() {
      _verifyMode = mode;
      _apiError = null;
    });
    if (mode == _VerifyMode.otp) {
      final targetIndex = _otpControllers.indexWhere((c) => c.text.isEmpty);
      final idx = targetIndex == -1 ? 5 : targetIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocusNodes[idx].requestFocus();
      });
    }
  }

  void _clearOtpBoxes() {
    for (final c in _otpControllers) {
      c.clear();
    }
  }

  void _onOtpDigitChanged(int index, String rawValue) {
    setState(() => _apiError = null);
    final digits = rawValue.replaceAll(RegExp(r'\D'), '');

    if (digits.length > 1) {
      // Handle multi-digit paste across all 6 boxes.
      for (var i = 0; i < 6; i++) {
        _otpControllers[i].text = i < digits.length ? digits[i] : '';
      }
      final nextEmpty = _otpControllers.indexWhere((c) => c.text.isEmpty);
      if (nextEmpty == -1) {
        _otpFocusNodes.last.unfocus();
        setState(() {});
        _submitOtp();
      } else {
        _otpFocusNodes[nextEmpty].requestFocus();
        setState(() {});
      }
      return;
    }

    if (digits.isEmpty) {
      _otpControllers[index].clear();
      if (index > 0) {
        _otpFocusNodes[index - 1].requestFocus();
      }
      setState(() {});
      return;
    }

    _otpControllers[index].text = digits;
    _otpControllers[index].selection = const TextSelection.collapsed(offset: 1);
    HapticFeedback.selectionClick();

    if (index < 5) {
      _otpFocusNodes[index + 1].requestFocus();
    } else {
      _otpFocusNodes[index].unfocus();
    }
    setState(() {});

    if (_otpCode.length == 6) {
      _submitOtp();
    }
  }

  Future<void> _submitOtp() async {
    final validationError = Validators.otp(_otpCode);
    if (validationError != null) {
      setState(() => _apiError = validationError);
      return;
    }
    if (_loading) return;
    setState(() {
      _loading = true;
      _apiError = null;
    });
    try {
      final username = _username.text.trim();
      final notifier = ref.read(authSessionProvider.notifier);
      if (notifier.pendingOtpChallenge == null) {
        await notifier.requestLoginOtp(
          username: username,
          password: _password.text.isEmpty ? null : _password.text,
        );
      }
      await notifier.verifyLoginOtp(username: username, otpCode: _otpCode);
      await _finishSignIn();
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _apiError = e.message);
      _clearOtpBoxes();
      _otpFocusNodes.first.requestFocus();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _submitPassword() async {
    setState(() => _apiError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    try {
      final username = _username.text.trim();
      await ref
          .read(authSessionProvider.notifier)
          .login(LoginRequest(username: username, password: _password.text));
        await _finishSignIn();
    } on ApiException catch (e) {
      if (mounted) setState(() => _apiError = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sendOtpFromPasswordStep() async {
    setState(() => _apiError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _sendingOtp = true);
    try {
      final username = _username.text.trim();
      final challenge = await ref
          .read(authSessionProvider.notifier)
          .requestLoginOtp(username: username, password: _password.text);
      if (!mounted) return;
      _startCooldown();
      _clearOtpBoxes();
      setState(() {
        _otpStatusMessage = challenge.message;
        _verifyMode = _VerifyMode.otp;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _otpFocusNodes.first.requestFocus();
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _apiError = e.message);
    } finally {
      if (mounted) setState(() => _sendingOtp = false);
    }
  }

  Future<void> _finishSignIn() async {
    if (!kIsWeb) {
      final notifier = ref.read(authSessionProvider.notifier);
      try {
        final alreadyEnabled = await notifier.hasBiometricLogin;
        final biometrics = await _localAuth.getAvailableBiometrics();
        if (!alreadyEnabled && biometrics.isNotEmpty && mounted) {
          final enable = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
              title: const Text('Enable biometric sign-in?'),
              content: const Text(
                'Use Face ID or your fingerprint the next time you sign in on this device.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Not now'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Enable'),
                ),
              ],
            ),
          );
          if (enable == true && mounted) {
            final authenticated = await _localAuth.authenticate(
              localizedReason: 'Confirm your identity to enable biometric sign-in',
              options: const AuthenticationOptions(
                biometricOnly: true,
                stickyAuth: true,
              ),
            );
            if (authenticated) await notifier.enableBiometricLogin();
          }
        }
      } on PlatformException {
        // Biometric setup is optional; a device without a usable biometric
        // configuration can still finish normal sign-in.
      } catch (_) {
        // Biometric setup must not block a valid password/OTP sign-in.
      }
    }
    if (mounted) context.go(AppRoutes.home);
  }

  Future<void> _biometricSignIn() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _apiError = null;
    });
    try {
      final notifier = ref.read(authSessionProvider.notifier);
      if (!await notifier.hasBiometricLogin) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Sign in with your password first to enable biometrics.'),
            ),
          );
        }
        return;
      }
      final authenticated = await _localAuth.authenticate(
        localizedReason: 'Sign in to Lidapay',
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (!authenticated) return;
      await notifier.biometricLogin();
      if (mounted) context.go(AppRoutes.home);
    } on ApiException catch (error) {
      if (mounted) setState(() => _apiError = error.message);
    } on PlatformException catch (error) {
      if (mounted) {
        setState(() {
          _apiError = error.message ?? 'Biometric sign-in could not be completed.';
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _apiError = 'Biometric sign-in could not be completed.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Stack(
        children: [
          const AuthHeroHeader(
            height: 350,
            title: 'Welcome back',
            subtitle:
                'Sign in to send airtime, shop deals and grow your Lida Value.',
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: SingleChildScrollView(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(context).bottom,
              ),
              child: TweenAnimationBuilder<Offset>(
                tween: Tween<Offset>(
                  begin: const Offset(0, 1),
                  end: Offset.zero,
                ),
                duration: const Duration(milliseconds: 550),
                curve: Curves.easeOutQuart,
                builder: (context, offset, child) {
                  return FractionalTranslation(
                    translation: offset,
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(24, 30, 24, 36),
                  decoration: BoxDecoration(
                    color: scheme.surface,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 30,
                        offset: const Offset(0, -10),
                      ),
                    ],
                  ),
                  child: AnimatedSize(
                    duration: const Duration(milliseconds: 380),
                    curve: Curves.fastOutSlowIn,
                    alignment: Alignment.topCenter,
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 360),
                      switchInCurve: Curves.easeOutQuart,
                      switchOutCurve: Curves.easeInQuart,
                      layoutBuilder: (currentChild, previousChildren) {
                        return Stack(
                          alignment: Alignment.topCenter,
                          children: <Widget>[
                            ...previousChildren,
                            ?currentChild,
                          ],
                        );
                      },
                      transitionBuilder: (child, animation) {
                        final isVerify =
                            child.key == const ValueKey('verify_step');
                        final inAnimation = Tween<Offset>(
                          begin: Offset(isVerify ? 0.35 : -0.35, 0.0),
                          end: Offset.zero,
                        ).animate(animation);
                        return FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: inAnimation,
                            child: child,
                          ),
                        );
                      },
                      child: _inVerifyStep
                          ? _buildVerifyStep(scheme)
                          : _buildUsernameStep(scheme),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsernameStep(ColorScheme scheme) {
    return Form(
      key: const ValueKey('username_step'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sign In',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: scheme.onSurface,
                ),
              ),
              if (!kIsWeb)
                OutlinedButton(
                  onPressed: _loading ? null : _biometricSignIn,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 12,
                    ),
                    side: BorderSide(
                      color: scheme.onSurfaceVariant.withValues(alpha: 0.2),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: const Icon(
                    Icons.fingerprint_rounded,
                    color: AppColors.primary,
                    size: 26,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          AppTextField(
            controller: _username,
            label: 'Phone or Email',
            hint: 'you@example.com or 0244588584',
            prefixIcon: const Icon(Icons.person_outline_rounded, size: 22),
            large: true,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _onNext(),
          ),
          if (_apiError != null) ...[
            const SizedBox(height: 16),
            _ErrorBanner(message: _apiError!),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 350),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.bottomCenter,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _canContinue
                ? Padding(
                    key: const ValueKey('continue_button'),
                    padding: const EdgeInsets.only(top: 28),
                    child: AppButton(label: 'Continue', onPressed: _onNext),
                  )
                : const SizedBox(key: ValueKey('empty_space'), height: 14),
          ),
          const SizedBox(height: 22),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  'New to Lidapay? ',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 15.5,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              GestureDetector(
                onTap: () => context.push(AppRoutes.register),
                child: Text(
                  'Create account',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildVerifyStep(ColorScheme scheme) {
    final isOtp = _verifyMode == _VerifyMode.otp;

    return KeyedSubtree(
      key: const ValueKey('verify_step'),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                onPressed: _onBackToUsername,
                icon: const Icon(Icons.arrow_back_rounded, size: 24),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 240),
                  layoutBuilder: (currentChild, previousChildren) => Align(
                    alignment: Alignment.centerLeft,
                    child: currentChild,
                  ),
                  child: Text(
                    isOtp ? 'Enter 6-Digit Code' : 'Enter Password',
                    key: ValueKey<bool>(isOtp),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Interactive account chip to change phone/email
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: _onBackToUsername,
              borderRadius: BorderRadius.circular(999),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.account_circle_outlined,
                      size: 17,
                      color: scheme.primary,
                    ),
                    const SizedBox(width: 7),
                    Flexible(
                      child: Text(
                        _username.text.trim(),
                        style: TextStyle(
                          color: scheme.onSurface,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Change',
                      style: TextStyle(
                        color: scheme.primary,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // Smooth animated segmented toggle: 6-Digit Code <-> Password
          _AuthMethodToggle(mode: _verifyMode, onChanged: _switchVerifyMode),
          const SizedBox(height: 18),
          AnimatedSize(
            duration: const Duration(milliseconds: 320),
            curve: Curves.fastOutSlowIn,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                final showingOtp = child.key == const ValueKey('otp_pane');
                final offsetTween = Tween<Offset>(
                  begin: Offset(showingOtp ? -0.2 : 0.2, 0),
                  end: Offset.zero,
                );
                return FadeTransition(
                  opacity: animation,
                  child: SlideTransition(
                    position: offsetTween.animate(animation),
                    child: child,
                  ),
                );
              },
              child: isOtp ? _buildOtpPane(scheme) : _buildPasswordPane(scheme),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpPane(ColorScheme scheme) {
    return Column(
      key: const ValueKey('otp_pane'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          _otpStatusMessage ??
              'Enter the 6-digit verification code sent to your account.',
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 13.5,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 16),
        AutofillGroup(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final boxWidth = ((constraints.maxWidth - (5 * 8)) / 6).clamp(
                40.0,
                54.0,
              );
              return Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: List.generate(6, (index) {
                  final hasValue = _otpControllers[index].text.isNotEmpty;
                  final isFocused = _otpFocusNodes[index].hasFocus;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    width: boxWidth,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: isFocused
                          ? [
                              BoxShadow(
                                color: scheme.primary.withValues(alpha: 0.18),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              ),
                            ]
                          : null,
                    ),
                    child: TextFormField(
                      key: ValueKey('otp_box_$index'),
                      controller: _otpControllers[index],
                      focusNode: _otpFocusNodes[index],
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      textInputAction: index == 5
                          ? TextInputAction.done
                          : TextInputAction.next,
                      autofillHints: index == 0
                          ? const [AutofillHints.oneTimeCode]
                          : null,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(6),
                      ],
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface,
                      ),
                      decoration: InputDecoration(
                        counterText: '',
                        filled: true,
                        fillColor: hasValue
                            ? scheme.primary.withValues(alpha: 0.08)
                            : scheme.surfaceContainerHighest.withValues(
                                alpha: 0.45,
                              ),
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 15,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: hasValue
                                ? scheme.primary.withValues(alpha: 0.55)
                                : scheme.outlineVariant.withValues(alpha: 0.5),
                            width: hasValue ? 1.5 : 1.0,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                          borderSide: BorderSide(
                            color: scheme.primary,
                            width: 2.0,
                          ),
                        ),
                      ),
                      onChanged: (value) => _onOtpDigitChanged(index, value),
                    ),
                  );
                }),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: _sendingOtp
                    ? Text(
                        'Sending code…',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : _resendCooldown > 0
                    ? Text(
                        'Resend code in 0:${_resendCooldown.toString().padLeft(2, '0')}',
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      )
                    : TextButton(
                        onPressed: () => _requestOtpChallenge(
                          silentIfPasswordRequired: false,
                        ),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          textStyle: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.refresh_rounded, size: 17),
                            SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                'Send / Resend code',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => _switchVerifyMode(_VerifyMode.password),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    textStyle: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.lock_outline_rounded, size: 17),
                      SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'Use password instead',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        if (_apiError != null) ...[
          const SizedBox(height: 10),
          _ErrorBanner(message: _apiError!),
        ],
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutBack,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) => SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.bottomCenter,
            child: FadeTransition(opacity: animation, child: child),
          ),
          child: _canVerifyOtp
              ? Padding(
                  key: const ValueKey('verify_otp_button'),
                  padding: const EdgeInsets.only(top: 14),
                  child: AppButton(
                    label: 'Verify & Sign in',
                    loading: _loading,
                    onPressed: _submitOtp,
                  ),
                )
              : const SizedBox(key: ValueKey('verify_otp_hidden'), height: 4),
        ),
      ],
    );
  }

  Widget _buildPasswordPane(ColorScheme scheme) {
    return Form(
      key: _formKey,
      child: Column(
        key: const ValueKey('password_pane'),
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppTextField(
            controller: _password,
            label: 'Password',
            hint: 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline_rounded, size: 22),
            large: true,
            obscureText: _obscure,
            textInputAction: TextInputAction.done,
            onFieldSubmitted: (_) {
              if (_canSignInPassword) _submitPassword();
            },
            validator: Validators.password,
            suffixIcon: IconButton(
              icon: Icon(
                _obscure
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                size: 22,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => _switchVerifyMode(_VerifyMode.otp),
                icon: const Icon(Icons.dialpad_rounded, size: 17),
                label: const Text('Use 6-digit code'),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => context.push(AppRoutes.forgotPassword),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  textStyle: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                child: const Text('Forgot password?'),
              ),
            ],
          ),
          if (_apiError != null) ...[
            const SizedBox(height: 8),
            _ErrorBanner(message: _apiError!),
            const SizedBox(height: 12),
          ],
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            switchInCurve: Curves.easeOutBack,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return SizeTransition(
                sizeFactor: animation,
                alignment: Alignment.bottomCenter,
                child: FadeTransition(opacity: animation, child: child),
              );
            },
            child: _canSignInPassword
                ? Column(
                    key: const ValueKey('signin_actions'),
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: 6),
                      AppButton(
                        key: const ValueKey('signin_button'),
                        label: 'Sign in',
                        loading: _loading,
                        onPressed: _submitPassword,
                      ),
                      const SizedBox(height: 8),
                      Center(
                        child: TextButton.icon(
                          onPressed: _sendingOtp
                              ? null
                              : _sendOtpFromPasswordStep,
                          icon: const Icon(
                            Icons.mark_email_read_outlined,
                            size: 17,
                          ),
                          label: Text(
                            _sendingOtp
                                ? 'Sending 6-digit code…'
                                : 'Or send 6-digit code to email',
                          ),
                          style: TextButton.styleFrom(
                            textStyle: const TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ],
                  )
                : const SizedBox(key: ValueKey('signin_hidden'), height: 6),
          ),
        ],
      ),
    );
  }
}

class _AuthMethodToggle extends StatelessWidget {
  const _AuthMethodToggle({required this.mode, required this.onChanged});

  final _VerifyMode mode;
  final ValueChanged<_VerifyMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isOtp = mode == _VerifyMode.otp;

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          AnimatedAlign(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: isOtp ? Alignment.centerLeft : Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.5,
              heightFactor: 1.0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(_VerifyMode.otp),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.dialpad_rounded,
                          size: 16,
                          color: isOtp
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '6-Digit Code',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: isOtp
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isOtp
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(_VerifyMode.password),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 16,
                          color: !isOtp
                              ? scheme.primary
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Password',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: !isOtp
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: !isOtp
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
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
