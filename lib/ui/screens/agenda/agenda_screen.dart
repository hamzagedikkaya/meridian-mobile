import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../theme/app_colors.dart';
import '../events/agenda_screen.dart' as events;
import '../shell/app_tabs.dart';
import '../todos/todos_screen.dart';

/// The Ajanda tab (design-analysis §6.1): tasks and events in one tab.
///
/// Until WP-7 merges them day by day (§7.4), it shows p24's two screens
/// as they are — the todo list (filters, lists, swipes) and the days ahead
/// with their events — one at a time, under a "Görevler · Etkinlikler"
/// switch.
///
/// Opened with `?view=` (a todo filter — `open`, `today`, `upcoming`,
/// `overdue`, `inbox` for undated, `done` — or `events`) and `?list=` (a
/// list id, or `none`) — the old `/todos` links, redirected here — it shows
/// that, then takes the query off the location.
class AgendaTabScreen extends ConsumerStatefulWidget {
  final String? view;
  final String? list;

  const AgendaTabScreen({super.key, this.view, this.list});

  @override
  ConsumerState<AgendaTabScreen> createState() => _AgendaTabScreenState();
}

class _AgendaTabScreenState extends ConsumerState<AgendaTabScreen>
    with TabRootScroll<AgendaTabScreen> {
  @override
  AppTab get tab => AppTab.agenda;

  bool _events = false;
  String _filter = 'open';
  int? _listId;
  bool _unlisted = false;

  /// Bumped by each `?view=` / `?list=` applied, so the todo list starts
  /// over on it.
  int _opened = 0;

  @override
  void initState() {
    super.initState();
    _apply(widget.view, widget.list);
    // The open todos' overdue count is the tab badge's once it is newer
    // than /home's (§6.1). Also the list the todo view opens on, so it is
    // not fetched twice.
    ref.listenManual(todosProvider(const TodoQuery()), (_, next) {
      final fetched = next.value;
      if (fetched == null || fetched.data.counts.isEmpty) return;
      ref.read(agendaOverdueProvider.notifier).report(
          Fetched(fetched.data.counts['overdue'] ?? 0, fetched.at));
    }, fireImmediately: true);
  }

  @override
  void didUpdateWidget(AgendaTabScreen old) {
    super.didUpdateWidget(old);
    if (widget.view != old.view || widget.list != old.list) {
      _apply(widget.view, widget.list);
    }
  }

  void _apply(String? view, String? list) {
    if (view == null && list == null) return;
    _opened++;
    _events = view == 'events';
    if (!_events) {
      _filter = switch (view) {
        'inbox' => 'undated',
        final String v when todoScreenFilters.contains(v) => v,
        _ => 'open',
      };
      _listId = list == null ? null : int.tryParse(list);
      _unlisted = list == 'none';
    }
    // Shown once: the location goes back to the bare tab, so the same link
    // followed again applies again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.go(AppTab.agenda.location);
    });
  }

  void _show(bool events) {
    if (events == _events) return;
    setState(() => _events = events);
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    return primaryScroll(Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        title: Text(l.tabAgenda, style: text.headlineLarge),
        actions: [
          IconButton(
            icon: const Icon(Icons.format_list_bulleted_rounded),
            tooltip: l.todoListsManage,
            onPressed: () => context.push('/agenda/lists'),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            // Wraps rather than overflows at 200 % text.
            child: Wrap(
              spacing: 8,
              children: [
                _ViewChip(
                  label: l.titleTodos,
                  selected: !_events,
                  onSelected: () => _show(false),
                ),
                _ViewChip(
                  label: l.titleEvents,
                  selected: _events,
                  onSelected: () => _show(true),
                ),
              ],
            ),
          ),
          Expanded(
            child: _events
                ? const events.AgendaScreen(embedded: true)
                : TodosScreen(
                    key: ValueKey('agenda-todos-$_opened'),
                    embedded: true,
                    initialFilter: _filter,
                    initialListId: _listId,
                    initialUnlisted: _unlisted,
                  ),
          ),
        ],
      ),
    ));
  }
}

class _ViewChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;

  const _ViewChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onSelected(),
      );
}
