/// How an edit form compares a text field with what the server stored.
///
/// A form trims what it sends, and sends nothing for a blank field. A value
/// saved elsewhere — a web textarea that ends in a newline, a name with a
/// trailing space — is the same value to the form: compared as stored, it
/// would open the form dirty and rewrite the field on a save that changed
/// nothing. So both sides are compared the way the form sends them.
library;

/// [text] the way a form sends it: trimmed, and null when blank.
String? asFormText(String? text) {
  final trimmed = text?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Whether a form's [value] differs from [stored] once both are read the
/// way the form sends them ([asFormText]).
bool formTextChanged(String? value, String? stored) =>
    asFormText(value) != asFormText(stored);
