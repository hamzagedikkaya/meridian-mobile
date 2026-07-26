import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/haptics.dart';
import '../../core/session.dart';
import '../../theme/app_colors.dart';
import '../widgets/monogram.dart';
import '../widgets/primary_button.dart';
import '../widgets/server_url_field.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _passwordFocus = FocusNode();

  bool _serverOk = false;
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  bool _noticeShown = false;

  @override
  void initState() {
    super.initState();
    _serverOk = ref.read(serverUrlProvider).isNotEmpty;
  }

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ref
          .read(sessionProvider.notifier)
          .login(_email.text, _password.text);
      TextInput.finishAutofillContext();
      Haptics.success();
      // Router redirect takes over on the session change.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;

    // Session-expired notice from a mid-session 401.
    final session = ref.watch(sessionProvider);
    if (session is SessionLoggedOut && session.notice != null && !_noticeShown) {
      _noticeShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(session.notice!)),
          );
        }
      });
    }

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: Monogram(size: 64)),
                const SizedBox(height: 20),
                Text('Meridian',
                    textAlign: TextAlign.center, style: text.displayMedium),
                const SizedBox(height: 4),
                Text(
                  'Kişisel yaşam merkezin',
                  textAlign: TextAlign.center,
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                ),
                const SizedBox(height: 40),
                ServerUrlField(
                  initialUrl: ref.read(serverUrlProvider),
                  onStatus: (result) {
                    final ok = result?.ok ?? false;
                    if (ok != _serverOk) setState(() => _serverOk = ok);
                  },
                  onVerifiedUrl: (url) =>
                      ref.read(serverUrlProvider.notifier).set(url),
                ),
                const SizedBox(height: 20),
                AnimatedOpacity(
                  opacity: _serverOk ? 1 : 0.4,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: IgnorePointer(
                    ignoring: !_serverOk,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextField(
                            controller: _email,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.email],
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                            onSubmitted: (_) => _passwordFocus.requestFocus(),
                            decoration:
                                const InputDecoration(labelText: 'E-posta'),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _password,
                            focusNode: _passwordFocus,
                            obscureText: _obscure,
                            autocorrect: false,
                            enableSuggestions: false,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onChanged: (_) {
                              if (_error != null) setState(() => _error = null);
                            },
                            onSubmitted: (_) => _submit(),
                            decoration: InputDecoration(
                              labelText: 'Şifre',
                              suffixIcon: IconButton(
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
                          if (_error != null) ...[
                            const SizedBox(height: 12),
                            Text(_error!,
                                style:
                                    text.bodySmall!.copyWith(color: c.error)),
                          ],
                          const SizedBox(height: 20),
                          PrimaryButton(
                            label: 'Giriş Yap',
                            loading: _loading,
                            onPressed: _serverOk ? _submit : null,
                          ),
                        ],
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
