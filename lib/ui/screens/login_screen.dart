import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/session.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import '../../theme/app_motion.dart';
import '../widgets/app_snackbar.dart';
import '../widgets/monogram.dart';
import '../widgets/primary_button.dart';
import '../widgets/server_url_field.dart';

/// Giriş (design-analysis §7.1): the monogram, the server address, then
/// the e-mail and the password.
///
/// * The credentials wait, dimmed and untappable, until the server has
///   answered — a saved address too is pinged first; once it has they come
///   up to full strength, rising 8 dp.
/// * An empty field is said under it before anything is sent.
/// * A wrong password is REJECT and "E-posta veya şifre hatalı"; too many
///   tries (429) asks to wait. Success is CONFIRM — and the router goes
///   back to where an expired session left off (`/login?from=`), else to
///   Today.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  /// The address the field starts with: the one saved on this phone, never
  /// the emulator default a fresh install would fall back to.
  late final String _savedUrl;
  bool _serverOk = false;
  // 0 while the server has not answered (40 %, 8 dp low), 1 once it has.
  late final AnimationController _rise = AnimationController(vsync: this);
  bool _obscure = true;
  bool _loading = false;
  // Held as the exception, not a sentence, so it re-renders in the language
  // that is active when it is shown.
  ApiException? _error;
  // The empty-field checks, once a send was tried; cleared as they type.
  bool _emailMissing = false;
  bool _passwordMissing = false;
  bool _noticeShown = false;

  @override
  void initState() {
    super.initState();
    final saved = ref.read(sharedPrefsProvider).getString(PrefKeys.serverUrl);
    _savedUrl = saved == null ? '' : ref.read(serverUrlProvider);
  }

  void _serverAnswered(bool ok) {
    if (ok == _serverOk) return;
    setState(() => _serverOk = ok);
    _rise.animateTo(
      ok ? 1 : 0,
      duration: Motion.orInstant(context, Motion.sheetIn), // 350 ms
      curve: Motion.enter,
    );
  }

  @override
  void dispose() {
    _rise.dispose();
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_loading) return;
    final emailMissing = _email.text.trim().isEmpty;
    final passwordMissing = _password.text.isEmpty;
    if (emailMissing || passwordMissing) {
      Haptics.reject();
      setState(() {
        _emailMissing = emailMissing;
        _passwordMissing = passwordMissing;
        _error = null;
      });
      (emailMissing ? _emailFocus : _passwordFocus).requestFocus();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(_email.text, _password.text);
      Haptics.confirm();
      TextInput.finishAutofillContext();
      // The router takes over on the session change.
    } on ApiException catch (e) {
      Haptics.reject();
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _edited() {
    if (_error != null || _emailMissing || _passwordMissing) {
      setState(() {
        _error = null;
        if (_email.text.trim().isNotEmpty) _emailMissing = false;
        if (_password.text.isNotEmpty) _passwordMissing = false;
      });
    }
  }

  String _errorText(ApiException e, AppL10n l) =>
      e.kind == ApiErrorKind.rateLimited ? l.loginRateLimited : e.localized(l);

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;

    // Session-expired notice from a mid-session 401; or, after signing out,
    // that the server could not be told (the session still works elsewhere).
    final session = ref.watch(sessionProvider);
    final notice = switch (session) {
      SessionLoggedOut(expired: true) => l.noticeSessionExpired,
      SessionLoggedOut(revokeFailed: true) => l.noticeSignOutNotRevoked,
      _ => null,
    };
    if (notice != null && !_noticeShown) {
      _noticeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          showAppSnack(context, notice, duration: const Duration(seconds: 8));
        }
      });
    }

    final error = _error;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.xxl),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: Monogram(size: 64)),
                const SizedBox(height: Gap.xl),
                Text(l.appName,
                    textAlign: TextAlign.center, style: text.displayMedium),
                const SizedBox(height: Gap.xs),
                Text(
                  l.tagline,
                  textAlign: TextAlign.center,
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                ),
                const SizedBox(height: Gap.x4),
                ServerUrlField(
                  initialUrl: _savedUrl,
                  onStatus: (result) => _serverAnswered(result?.ok ?? false),
                  onVerifiedUrl: (url) =>
                      ref.read(serverUrlProvider.notifier).set(url),
                ),
                const SizedBox(height: Gap.md),
                // Until the server answers: 40 % and out of reach, 8 dp low.
                // The animation stays in the leaf (§5.10): one controller
                // moves the paint and the opacity, nothing is rebuilt.
                _RiseTransition(
                  rise: _rise,
                  distance: 8,
                  child: FadeTransition(
                    opacity: _rise.drive(Tween(begin: 0.4, end: 1)),
                    child: IgnorePointer(
                      ignoring: !_serverOk,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _email,
                              focusNode: _emailFocus,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autocorrect: false,
                              autofillHints: const [AutofillHints.email],
                              onChanged: (_) => _edited(),
                              onSubmitted: (_) => _passwordFocus.requestFocus(),
                              decoration: InputDecoration(
                                labelText: l.loginEmail,
                                errorText: _emailMissing
                                    ? l.loginEmailRequired
                                    : null,
                              ),
                            ),
                            const SizedBox(height: Gap.md),
                            TextField(
                              controller: _password,
                              focusNode: _passwordFocus,
                              obscureText: _obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              textInputAction: TextInputAction.done,
                              autofillHints: const [AutofillHints.password],
                              onChanged: (_) => _edited(),
                              onSubmitted: (_) => _submit(),
                              decoration: InputDecoration(
                                labelText: l.loginPassword,
                                errorText: _passwordMissing
                                    ? l.loginPasswordRequired
                                    : null,
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? l.profileShowPassword
                                      : l.profileHidePassword,
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                    color: c.inkMid,
                                  ),
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                ),
                              ),
                            ),
                            // The refusal, just above the button.
                            if (error != null) ...[
                              const SizedBox(height: Gap.md),
                              Semantics(
                                liveRegion: true,
                                child: Text(
                                  _errorText(error, l),
                                  style:
                                      text.bodySmall!.copyWith(color: c.error),
                                ),
                              ),
                            ],
                            const SizedBox(height: Gap.xl),
                            PrimaryButton(
                              label: l.loginSubmit,
                              loading: _loading,
                              onPressed: _serverOk ? _submit : null,
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
      ),
    );
  }
}

/// Draws [child] [distance] dp lower while [rise] is 0, in place at 1 —
/// `Transform.translate` (§7.1) done in paint, as `FadeTransition` does its
/// opacity: the frames of the rise repaint and never rebuild or re-lay out
/// (§5.10).
class _RiseTransition extends SingleChildRenderObjectWidget {
  final Animation<double> rise;
  final double distance;

  const _RiseTransition({
    required this.rise,
    required this.distance,
    required super.child,
  });

  @override
  _RenderRise createRenderObject(BuildContext context) =>
      _RenderRise(rise, distance);

  @override
  void updateRenderObject(BuildContext context, _RenderRise renderObject) {
    renderObject
      ..rise = rise
      ..distance = distance;
  }
}

class _RenderRise extends RenderProxyBox {
  _RenderRise(this._rise, this._distance);

  Animation<double> _rise;
  set rise(Animation<double> value) {
    if (value == _rise) return;
    if (attached) _rise.removeListener(markNeedsPaint);
    _rise = value;
    if (attached) _rise.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _distance;
  set distance(double value) {
    if (value == _distance) return;
    _distance = value;
    markNeedsPaint();
  }

  Offset get _shift => Offset(0, _distance * (1 - _rise.value));

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _rise.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _rise.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset + _shift);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintOffset(
      offset: _shift,
      position: position,
      hitTest: (result, transformed) =>
          child.hitTest(result, position: transformed),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _shift;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }
}
