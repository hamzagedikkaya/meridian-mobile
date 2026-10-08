/// What a write changed on the server, and the hook the repository reports
/// writes through.
///
/// Kept free of Riverpod so `repository.dart` stays a plain Dart class. The
/// table that turns a scope into the cached screens it affects lives in
/// `sync.dart`.
library;

/// A kind of server data a write can change.
///
/// Every repository write declares the scopes it touches; `sync.dart` maps
/// each scope to every cached read model whose server response depends on
/// it, including the aggregates (`/home`, `/finance/dashboard`, goals that
/// recalculate from transactions and habit logs). A screen never picks what
/// to refresh after a write.
enum DataScope {
  /// Transactions created, edited or deleted.
  transactions,

  /// An account's own data — its name, colour, type, currency or opening
  /// balance — or the account deleted: what transaction rows, the
  /// dashboard, subscriptions and financial goals embed or are computed from.
  accounts,

  /// Which accounts there are and which are archived: an account opened,
  /// archived or restored. Nothing else embeds that.
  accountList,

  /// A finance category renamed, recoloured, moved or deleted: what
  /// transaction rows, the dashboard, budgets and subscriptions embed.
  categories,

  /// A finance category added: nothing shows it yet but the category lists
  /// and the categories a budget can go on.
  categoryList,

  /// Monthly budgets.
  budgets,

  /// Recurring subscriptions.
  subscriptions,

  /// Habit definitions: created, edited, archived.
  habits,

  /// Habit check-ins: a day's count and completion.
  habitLogs,

  /// Goals: created, edited, progress logged, recalculated, abandoned.
  goals,

  /// Todos: created, edited, completed, reopened.
  todos,

  /// Calendar events.
  events,

  /// Journal entries.
  journal,

  /// The account settings that shape every server aggregate: the currency
  /// sums are reported in and the time zone that decides what "today" is.
  /// (Language and theme shape nothing the server reports.)
  me,
}

/// One server record a write deleted: its kind and its id.
typedef DeletedRecord = ({DataScope scope, int id});

/// Told about every write the repository sends.
abstract interface class WriteListener {
  /// A write request is about to leave.
  void writeStarted();

  /// The write is over. [changed] is what the server may now report
  /// differently — empty when nothing changed (a rejected write, a dead
  /// session, or a write that touches nothing the app reads).
  ///
  /// [deleted] is the record the write deleted, once the server confirmed
  /// it. Its own detail is not asked for again (that could only answer 404,
  /// typically while its screen is still animating out); everything else
  /// [changed] reaches refreshes as usual.
  void writeFinished(Set<DataScope> changed, {DeletedRecord? deleted});
}
