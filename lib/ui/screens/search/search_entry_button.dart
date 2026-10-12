import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/search.dart';
import '../../../l10n/app_l10n.dart';

/// The way into global search (design-analysis §6.8): a 48 dp
/// `search_rounded` button that opens `/search` — in Today's header (placed
/// by WP-5, before the avatar) and Agenda's app bar (WP-7, in place of its
/// `kSearchEnabled` icon).
///
/// Draws nothing while search is not offered: [kSearchEnabled] off, or a
/// server without `GET /search` (it answered 404; contract §13), so a
/// screen can always place it.
class SearchEntryButton extends ConsumerWidget {
  const SearchEntryButton({super.key, this.color});

  /// The icon's colour; the app bar's (inkMid) by default.
  final Color? color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(searchOfferedProvider)) return const SizedBox.shrink();
    return IconButton(
      onPressed: () => context.push('/search'),
      tooltip: context.l10n.titleSearch,
      color: color,
      icon: const Icon(Icons.search_rounded),
    );
  }
}
