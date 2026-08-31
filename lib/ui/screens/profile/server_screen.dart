import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/haptics.dart';
import '../../../core/session.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/app_snackbar.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/primary_button.dart';

enum _Phase { idle, testing, done }

/// Server settings — address + connection test with latency (design §4.8).
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
    if (_phase != _Phase.idle) {
      setState(() {
        _phase = _Phase.idle;
        _result = null;
      });
    }
  }

  Future<void> _test() async {
    final url = _controller.text.trim();
    if (url.isEmpty) {
      showAppSnack(context, context.l10n.serverEmpty, isError: true);
      return;
    }
    setState(() {
      _phase = _Phase.testing;
      _result = null;
    });
    final res = await pingHealth(url);
    if (!mounted) return;
    setState(() {
      _phase = _Phase.done;
      _result = res;
    });
    res.ok ? Haptics.success() : Haptics.danger();
  }

  Future<void> _save() async {
    final l = context.l10n;
    final url = _controller.text.trim();
    if (url.isEmpty) {
      showAppSnack(context, l.serverEmpty, isError: true);
      return;
    }
    final verified = _phase == _Phase.done && (_result?.ok ?? false);
    if (!verified) {
      final go = await showConfirmDialog(
        context,
        title: l.serverUnverifiedTitle,
        message: l.serverUnverifiedBody,
        confirmLabel: l.serverSaveAnyway,
      );
      if (!go) return;
    }
    setState(() => _saving = true);
    await ref.read(serverUrlProvider.notifier).set(url);
    if (!mounted) return;
    showAppSnack(context, l.serverSaved);
    context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;

    return Scaffold(
      appBar: AppBar(title: Text(l.titleServer)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: [
          Text(
            l.serverBlurb,
            style: text.bodyMedium!.copyWith(color: c.inkMid),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _controller,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: _onChanged,
            onSubmitted: (_) => _test(),
            decoration: InputDecoration(
              labelText: l.serverAddress,
              hintText: 'http://192.168.1.20:3000',
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _phase == _Phase.testing ? null : _test,
            icon: _phase == _Phase.testing
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.wifi_tethering, size: 20),
            label: Text(l.serverTest),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _ResultRow(phase: _phase, result: _result),
          ),
          const SizedBox(height: 24),
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

/// Inline test outcome: green "Connected · Meridian vX · 38 ms" or red failure.
class _ResultRow extends StatelessWidget {
  final _Phase phase;
  final HealthResult? result;

  const _ResultRow({required this.phase, required this.result});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
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
        icon: Icons.check_circle,
        color: c.income,
        label: parts.join(' · '),
        style: text.bodyMedium!,
      );
    }
    return _line(
      context,
      icon: Icons.error_outline,
      color: c.error,
      label: l.serverCantConnect,
      style: text.bodyMedium!,
    );
  }

  Widget _line(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String label,
    required TextStyle style,
  }) {
    final c = context.nok;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(label, style: style.copyWith(color: color))),
          ],
        ),
      ),
    );
  }
}
