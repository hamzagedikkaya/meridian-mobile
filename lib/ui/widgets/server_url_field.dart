import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/session.dart';
import '../../l10n/app_l10n.dart';
import '../../theme/app_colors.dart';

enum _Ping { idle, checking, ok, fail }

/// Server address field with a debounced /health ping (1.5s after typing
/// stops) and a status slot; collapses to a compact row on success
/// (design §4.2, grafted from Kehribar/Akış).
class ServerUrlField extends StatefulWidget {
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
  State<ServerUrlField> createState() => _ServerUrlFieldState();
}

class _ServerUrlFieldState extends State<ServerUrlField> {
  late final TextEditingController _controller;
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
    final result = await pingHealth(url);
    if (!mounted || seq != _seq) return;
    setState(() {
      _ping = result.ok ? _Ping.ok : _Ping.fail;
      _collapsed = result.ok;
    });
    widget.onStatus?.call(result);
    if (result.ok) widget.onVerifiedUrl?.call(normalizeServerUrl(url));
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;

    if (_collapsed) {
      final host = normalizeServerUrl(_controller.text)
          .replaceFirst(RegExp(r'^https?://'), '');
      return InkWell(
        onTap: () => setState(() => _collapsed = false),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: c.hairline),
          ),
          child: Row(
            children: [
              Icon(Icons.check_circle, size: 18, color: c.income),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  host,
                  style: text.bodyMedium!.copyWith(color: c.inkMid),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(l.labelChange,
                  style: text.labelLarge!.copyWith(color: c.gold)),
            ],
          ),
        ),
      );
    }

    return TextField(
      controller: _controller,
      keyboardType: TextInputType.url,
      autocorrect: false,
      onChanged: _onChanged,
      onSubmitted: (_) {
        _debounce?.cancel();
        _check();
      },
      decoration: InputDecoration(
        labelText: l.serverAddress,
        hintText: 'http://192.168.1.20:3000',
        errorText: _ping == _Ping.fail
            ? l.serverAddressUnreachable
            : null,
        suffixIcon: switch (_ping) {
          _Ping.idle => Icon(Icons.public, size: 24, color: c.inkLow),
          _Ping.checking => const Padding(
              padding: EdgeInsets.all(14),
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          _Ping.ok => Icon(Icons.check_circle, size: 24, color: c.income),
          _Ping.fail => Icon(Icons.error_outline, size: 24, color: c.error),
        },
      ),
    );
  }
}
