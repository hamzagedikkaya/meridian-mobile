/// Moved to `../agenda/agenda_days.dart` (WP-7: the events agenda is now
/// part of the Agenda tab). This re-export keeps old imports — Today's
/// agenda card reads [occurrencesIn] from here — compiling until WP-17
/// removes it.
library;

export '../agenda/agenda_days.dart' show Occurrence, dayHeading, occurrencesIn;
