import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/providers.dart';
import '../../../models/journal.dart';

/// Single journal entry (GET /journal_entries/:id) for the detail screen.
/// Kept here so the editor can invalidate it after an update.
final journalEntryProvider =
    FutureProvider.autoDispose.family<JournalEntry, int>((ref, id) async {
  return ref.watch(repositoryProvider).fetchJournalEntry(id);
});
