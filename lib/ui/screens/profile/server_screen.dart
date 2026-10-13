import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../data/sync.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../../theme/app_metrics.dart';
import '../../../theme/app_motion.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/nok_sheet.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/server_url_field.dart';

enum _Phase { idle, testing, done }

/// Server settings (design-analysis §7.1): the address — with the same hint
/// and "where do I find it?" help as the login screen — a connection test
/// with its latency, and Save.
///
/// Saving an address that did not answer asks first, in a sheet. A new
/// address ends the session (its token belongs to the old server).
class ServerScreen extends ConsumerStatefulWidget {
  const ServerScreen({super.key});

  @override
  ConsumerState<ServerScreen> createState() => _ServerScreenState();
}

class _ServerScreenState extends ConsumerState<ServerScreen> {
  late final TextEditingController _controller;
  _Phase _phase = _Phase.idle;
  HealthResult? _result;
  bool _saving = false;

  /// The test now on its way: an answer to an older one — for an address
  /// since edited, or tested again — is dropped.
  int _seq = 0;

  /// The address [_result] is for (normalized): only it counts as tested.
  String? _testedUrl;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: ref.read(serverUrlProvider));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    // Always: the field's hint (two lines while empty) follows the text.
    // A test still on its way was for the text before this edit.
    _seq++;
    setState(() {
      _phase = _Phase.idle;
      _result = null;
      _testedUrl = null;
    });
  }

  Future<void> _test() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      showAppSnack(context, context.l10n.serverEmpty, isError: true);
      return;
    }
    final seq = ++_seq;
    setState(() {
      _phase = _Phase.testing;
      _result = null;
      _testedUrl = null;
    });
    final res = await ref.read(serverPingProvider)(url);
    if (!mounted || seq != _seq) return;
    setState(() {
      _phase = _Phase.done;
      _result = res;
      _testedUrl = normalizeServerUrl(url);
    });
    res.ok ? Haptics.confirm() : Haptics.reject();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final url = _controller.text.trim();
    if (url.isEmpty) {
      showAppSnack(context, l.serverEmpty, isError: true);
      return;
    }
    // Verified only by a test of the address in the field now.
    final verified =
        _phase == _Phase.done &&
        (_result?.ok ?? false) &&
        _testedUrl == normalizeServerUrl(url);
    if (!verified) {
      final signsOut = _signsOut(url);
      final go = await showNokSheet<bool>(
        context,
        title: l.serverUnverifiedTitle,
        builder: (context) => _SaveAnywaySheet(signsOut: signsOut),
      );
      if (go != true || !mounted) return;
    }
    setState(() => _saving = true);
    // A new address signs out (its token belongs to the old server). The
    // same address — typically saved after a test showed the server is back
    // — refetches everything instead, so an error screen behind this one
    // recovers without a manual retry.
    final unchanged = normalizeServerUrl(url) == ref.read(serverUrlProvider);
    final sync = ref.read(dataSyncProvider);
    await ref.read(serverUrlProvider.notifier).set(url);
    if (unchanged) sync.refreshAll();
    if (!mounted) return;
    showAppSnack(context, unchanged ? l.serverSaved : l.serverSavedSignIn);
    context.pop();
  }

  /// Saving [url] signs this phone out: a different address than the one
  /// in use, while signed in (its token belongs to the old server).
  bool _signsOut(String url) =>
      url.trim().isNotEmpty &&
      normalizeServerUrl(url) != ref.read(serverUrlProvider) &&
      ref.read(sessionProvider) is SessionLoggedIn;

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final testing = _phase == _Phase.testing;

    return Scaffold(
      appBar: AppBar(title: Text(l.titleServer)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          Insets.gutter,
          Gap.md,
          Insets.gutter,
          Gap.x4,
        ),
        children: [
          Text(
            l.serverBlurb,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: Gap.xl),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _onChanged,
            onSubmitted: (_) => _test(),
            decoration: InputDecoration(
              labelText: l.serverAddress,
              hintText: l.serverAddressHint,
              // Both examples, wrapped as far as the text size needs —
              // never cut; the field keeps that height once typed in.
              hintMaxLines: serverHintMaxLines,
            ),
          ),
          const Align(
            alignment: AlignmentDirectional.centerStart,
            child: ServerAddressHelpButton(),
          ),
          // Said before Save, not after: a new address signs out.
          if (_signsOut(_controller.text))
            Padding(
              padding: const EdgeInsets.only(bottom: Gap.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Icon(
                      Icons.info_outline_rounded,
                      size: 16,
                      color: c.inkMid,
                    ),
                  ),
                  const SizedBox(width: Gap.sm),
                  Expanded(
                    child: Text(
                      l.serverChangeSignsOut,
                      style: text.bodySmall!.copyWith(color: c.inkMid),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: Gap.xs),
          OutlinedButton.icon(
            onPressed: testing ? null : _test,
            icon: testing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering_rounded, size: 18),
            label: Text(l.serverTest),
          ),
          // AnimatedSize cannot take zero time (it would re-lay itself out
          // mid-layout): under reduced motion the result just takes its
          // place.
          if (Motion.reduced(context))
            _ResultRow(phase: _phase, result: _result)
          else
            AnimatedSize(
              duration: Motion.collapse,
              curve: Motion.enter,
              alignment: Alignment.topCenter,
              child: _ResultRow(phase: _phase, result: _result),
            ),
          const SizedBox(height: Gap.xxl),
          PrimaryButton(
            label: l.actionSave,
            loading: _saving,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}

/// "Bu adres yanıt vermiyor. Yine de kaydet?" — a sheet, not a dialog
/// (design-analysis §7.1): "Yine de kaydet" first, "Vazgeç" under it. Pops
/// true to save.
class _SaveAnywaySheet extends StatelessWidget {
  /// Saving signs this phone out: said here too.
  final bool signsOut;
  const _SaveAnywaySheet({required this.signsOut});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final navigator = Navigator.of(context);
    return SingleChildScrollView(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.sheetH,
            0,
            Insets.sheetH,
            Gap.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l.serverUnverifiedBody,
                style: text.bodyMedium!.copyWith(color: c.inkMid),
              ),
              if (signsOut) ...[
                const SizedBox(height: Gap.sm),
                Text(
                  l.serverChangeSignsOut,
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                ),
              ],
              const SizedBox(height: Gap.xxl),
              PrimaryButton(
                label: l.serverSaveAnyway,
                onPressed: () => navigator.pop(true),
              ),
              const SizedBox(height: Gap.sm),
              TextButton(
                onPressed: () => navigator.pop(false),
                child: Text(l.actionCancel),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Inline test outcome: "Bağlandı · Meridian v1.x · 38 ms" with a green
/// check, or the failure in the error colour.
class _ResultRow extends StatelessWidget {
  final _Phase phase;
  final HealthResult? result;

  const _ResultRow({required this.phase, required this.result});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final l = context.l10n;

    if (phase != _Phase.done || result == null) {
      return const SizedBox(width: double.infinity);
    }
    final r = result!;

    if (r.ok) {
      final parts = <String>[
        l.serverConnected,
        if (r.version != null) l.serverVersion(r.version!),
        if (r.latencyMs != null) l.serverLatency(r.latencyMs!),
      ];
      return _line(
        context,
        icon: Icons.check_circle_rounded,
        color: c.income,
        label: parts.join(' · '),
      );
    }
    return _line(
      context,
      icon: Icons.error_outline_rounded,
      color: c.error,
      label: l.serverCantConnect,
    );
  }

  Widget _line(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
  }) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: Gap.md),
      child: Semantics(
        liveRegion: true,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(width: Gap.sm),
            Expanded(
              child: Text(label, style: text.bodyMedium!.copyWith(color: color)),
            ),
          ],
        ),
      ),
    );
  }
}
