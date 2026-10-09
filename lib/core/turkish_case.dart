/// Turkish-correct upper and lower case (design-analysis §3.6 rule 9).
///
/// Dart's `toUpperCase()` / `toLowerCase()` follow English rules: "istanbul"
/// becomes "ISTANBUL" and "IŞIK" becomes "işik". Turkish pairs the dotted and
/// dotless i differently — i ↔ İ, ı ↔ I — so any case change on text a person
/// wrote or reads (initials, search folding) goes through these instead.
///
/// Overlines are uppercased in the l10n files, not at runtime; ISO currency
/// codes may keep `toUpperCase()`.
library;

/// [text] in upper case by Turkish rules: i → İ, ı → I.
String trUpper(String text) =>
    text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// [text] in lower case by Turkish rules: I → ı, İ → i.
///
/// The replacements run before `toLowerCase()`, which would otherwise turn
/// "İ" into "i̇" (i + combining dot) and "I" into "i".
String trLower(String text) =>
    text.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// [text] with its first character upper-cased by Turkish rules.
String trCapitalize(String text) {
  if (text.isEmpty) return text;
  final first = String.fromCharCode(text.runes.first);
  return trUpper(first) + text.substring(first.length);
}

/// Case- and dotting-insensitive form of [text] for search: Turkish lower
/// case with the dotless ı folded into i, so "IŞIK", "Işık", "ışık" and an
/// English keyboard's "işik" all meet.
String trFold(String text) => trLower(text).replaceAll('ı', 'i');
