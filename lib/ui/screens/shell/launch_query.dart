import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Something a tab root does when its location carries a query key — a
/// shortcut's `/today?capture=1` opens quick add, `/finance?new=tx` the
/// transaction form, `/journal?new=1` the editor (design-analysis §6.9).
typedef LaunchAction = void Function(BuildContext context, String value);

/// Runs a [LaunchAction] once for each of [triggers]' keys the location's
/// [query] carries, once the tab is on screen, then takes those keys off
/// the location — so going back to the tab, or rebuilding it, never runs
/// them again, and following the same link again does.
class LaunchQuery extends StatefulWidget {
  const LaunchQuery({
    super.key,
    required this.path,
    required this.query,
    required this.triggers,
    required this.child,
  });

  /// The tab's location without its query (`/today`).
  final String path;

  /// The location's query parameters.
  final Map<String, String> query;

  final Map<String, LaunchAction> triggers;

  final Widget child;

  @override
  State<LaunchQuery> createState() => _LaunchQueryState();
}

class _LaunchQueryState extends State<LaunchQuery> {
  @override
  void initState() {
    super.initState();
    _check();
  }

  @override
  void didUpdateWidget(LaunchQuery old) {
    super.didUpdateWidget(old);
    if (!mapEquals(old.query, widget.query)) _check();
  }

  void _check() {
    final query = widget.query;
    final hits = [
      for (final key in widget.triggers.keys)
        if (query.containsKey(key)) key,
    ];
    if (hits.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final rest = {
        for (final MapEntry(:key, :value) in query.entries)
          if (!widget.triggers.containsKey(key)) key: value,
      };
      context.go(Uri(
        path: widget.path,
        queryParameters: rest.isEmpty ? null : rest,
      ).toString());
      for (final key in hits) {
        widget.triggers[key]!(context, query[key]!);
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
