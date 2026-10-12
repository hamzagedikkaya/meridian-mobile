import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/session.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_metrics.dart';
import 'form_scaffold.dart';
import 'nok_sheet.dart';

/// How the address field and the server settings reach `/health`: the real
/// [pingHealth]; tests swap in a fixed answer.
final serverPingProvider =
    Provider<Future<HealthResult> Function(String url)>((ref) => pingHealth);

/// As many lines as the address hint (a LAN and a Tailscale example) can
/// take at 200 % text on a small phone. A `TextField` reads a null
/// `hintMaxLines` as its own one line, so the cap is spelled out.
const serverHintMaxLines = 8;

enum _Ping { idle, checking, ok, fail }

/// Server address field with a debounced /health ping (1.5s after typing
/// stops) and a status slot (design-analysis §7.1).
///
/// * Empty until there is an address — never prefilled with an emulator's
///   `10.0.2.2` (the caller passes the saved address, or nothing).
/// * Its hint shows both kinds of address (a LAN IP, a Tailscale name), and
///   "Adresi nereden bulurum?" under it opens [showServerAddressHelp].
/// * A successful ping folds it into one row — a green check, the host and
///   "Değiştir", which opens the field again.
class ServerUrlField extends ConsumerStatefulWidget {
  final String initialUrl;
  final ValueChanged<String>? onVerifiedUrl;
  final ValueChanged<HealthResult?>? onStatus;

  const ServerUrlField({
    super.key,
    required this.initialUrl,
    this.onVerifiedUrl,
    this.onStatus,
  });

  @override
  ConsumerState<ServerUrlField> createState() => _ServerUrlFieldState();
}

class _ServerUrlFieldState extends ConsumerState<ServerUrlField> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  Timer? _debounce;
  _Ping _ping = _Ping.idle;
  bool _collapsed = false;
  int _seq = 0;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialUrl);
    _check();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    widget.onStatus?.call(null);
    _debounce?.cancel();
    setState(() => _ping = _Ping.idle);
    _debounce = Timer(const Duration(milliseconds: 1500), _check);
  }

  Future<void> _check() async {
    final url = _controller.text.trim();
    if (url.isEmpty) return;
    final seq = ++_seq;
    setState(() => _ping = _Ping.checking);
    final result = await ref.read(serverPingProvider)(url);
    if (!mounted || seq != _seq) return;
    setState(() {
      _ping = result.ok ? _Ping.ok : _Ping.fail;
      _collapsed = result.ok;
    });
    widget.onStatus?.call(result);
    if (result.ok) widget.onVerifiedUrl?.call(normalizeServerUrl(url));
  }

  void _expand() {
    setState(() => _collapsed = false);
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;

    if (_collapsed) {
      final host = normalizeServerUrl(_controller.text)
          .replaceFirst(RegExp(r'^https?://'), '');
      return MergeSemantics(
        child: Semantics(
          button: true,
          label: l.serverAddress,
          child: FormFieldBox(
            onTap: _expand,
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, size: 20, color: c.income),
                const SizedBox(width: Gap.sm),
                Expanded(
                  // The whole host, wrapping if it must: never cut.
                  child: Text(
                    host,
                    style: text.bodyMedium!.copyWith(color: c.inkHi),
                  ),
                ),
                const SizedBox(width: Gap.sm),
                Text(
                  l.labelChange,
                  style: text.labelLarge!.copyWith(color: c.gold),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focus,
          keyboardType: TextInputType.url,
          autocorrect: false,
          enableSuggestions: false,
          onChanged: _onChanged,
          onSubmitted: (_) {
            _debounce?.cancel();
            _check();
          },
          decoration: InputDecoration(
            labelText: l.serverAddress,
            hintText: l.serverAddressHint,
            // Both examples, wrapped as far as the text size needs — never
            // cut (null would mean the field's one line). The field keeps
            // the hint's height once typed in (maintainHintSize), so
            // nothing under it moves.
            hintMaxLines: serverHintMaxLines,
            // A widget, not errorText: the theme caps errorText at two
            // lines, and the Wi-Fi / Tailscale advice must be read whole
            // at any text size (§7.1, §8.3).
            error: _ping == _Ping.fail
                ? Text(l.serverAddressUnreachable)
                : null,
            suffixIcon: switch (_ping) {
              _Ping.idle => Icon(Icons.public_rounded, size: 24, color: c.inkLow),
              _Ping.checking => const Padding(
                  padding: EdgeInsets.all(14),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              _Ping.ok =>
                Icon(Icons.check_circle_rounded, size: 24, color: c.income),
              _Ping.fail =>
                Icon(Icons.error_outline_rounded, size: 24, color: c.error),
            },
          ),
        ),
        const Align(
          alignment: AlignmentDirectional.centerStart,
          child: ServerAddressHelpButton(),
        ),
      ],
    );
  }
}

/// "Adresi nereden bulurum?" — the gold text link under an address field;
/// opens [showServerAddressHelp].
class ServerAddressHelpButton extends StatelessWidget {
  const ServerAddressHelpButton({super.key});

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: () => showServerAddressHelp(context),
      icon: const Icon(Icons.help_outline_rounded, size: 18),
      label: Text(context.l10n.serverHelpAction),
    );
  }
}

/// Three short steps to the server's address (design-analysis §7.1): the
/// LAN IP, the Tailscale MagicDNS name, port 3000.
Future<void> showServerAddressHelp(BuildContext context) {
  final l = context.l10n;
  return showNokSheet<void>(
    context,
    title: l.serverHelpTitle,
    showClose: true,
    builder: (context) => const _ServerHelpSteps(),
  );
}

class _ServerHelpSteps extends StatelessWidget {
  const _ServerHelpSteps();

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final steps = [
      (l.serverHelpLanTitle, l.serverHelpLanBody),
      (l.serverHelpTailscaleTitle, l.serverHelpTailscaleBody),
      (l.serverHelpPortTitle, l.serverHelpPortBody),
    ];
    return SingleChildScrollView(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.sheetH,
            0,
            Insets.sheetH,
            Gap.xxl,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final (i, (title, body)) in steps.indexed) ...[
                if (i > 0) const SizedBox(height: Gap.lg),
                _HelpStep(number: i + 1, title: title, body: body),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _HelpStep extends StatelessWidget {
  final int number;
  final String title;
  final String body;

  const _HelpStep({
    required this.number,
    required this.title,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return MergeSemantics(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: c.goldContainer,
              shape: BoxShape.circle,
            ),
            child: Text(
              '$number',
              style: text.labelLarge!.copyWith(color: c.onGoldContainer),
            ),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: text.titleSmall),
                const SizedBox(height: Gap.xxs),
                Text(body, style: text.bodyMedium!.copyWith(color: c.inkMid)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
