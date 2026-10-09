import 'package:flutter/material.dart';

import '../../../l10n/app_l10n.dart';
import '../../widgets/empty_state.dart';

/// The search page (`/search?q=`, design-analysis §6.8). WP-16 builds it —
/// and turns `kSearchEnabled` on, which draws the ways in; until then the
/// route exists and says search is on its way.
class SearchScreen extends StatelessWidget {
  /// The query it was opened with.
  final String query;

  const SearchScreen({super.key, this.query = ''});

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l.titleSearch)),
      body: Center(
        child: SingleChildScrollView(
          child: EmptyState(
            icon: Icons.search_rounded,
            title: l.searchComingSoon,
          ),
        ),
      ),
    );
  }
}
