/// The Profile screen's editors (design-research §4.1, §5.7): one bottom
/// sheet per setting, each saving on its own and closing once the server
/// has it.
///
/// * one-field and two-field sheets for the name and the e-mail, a three-field
///   one for the password — the server's refusals shown under the field they
///   are about, anything else above the save button;
/// * pickers for the currency, the time zone and the weekly review day,
///   which save as soon as a choice is tapped (a currency change asks first:
///   nothing is converted);
/// * the sign-out sheet, which says it signs out every device and warns
///   about an unsaved journal draft.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api.dart';
import '../../../core/formats.dart';
import '../../../core/haptics.dart';
import '../../../data/current_day.dart';
import '../../../data/profile_actions.dart';
import '../../../data/providers.dart';
import '../../../l10n/app_l10n.dart';
import '../../../models/date_utils.dart';
import '../../../models/me_options.dart';
import '../../../models/user.dart';
import '../../../theme/app_colors.dart';
import '../../widgets/confirm_dialog.dart';
import '../../widgets/primary_button.dart';
import '../../widgets/sync_hint.dart';

/// The weekday names the weekly review row and picker show, in the app's
/// language: 0 Sunday … 6 Saturday, as the server numbers them.
String weekdayName(int day, {String? locale}) =>
    // 4 October 2026 is a Sunday.
    formatWeekday(DateTime(2026, 10, 4 + day), locale: locale);

Future<T?> _showSheet<T>(BuildContext context, WidgetBuilder builder) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      barrierColor: const Color(0xFF171310).withValues(alpha: 0.6),
      builder: builder,
    );

/// Shows [message] on the screen under the sheet that just closed.
void _confirmSaved(ScaffoldMessengerState messenger, String message) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

/// What to say above the save button for a failure no field claims: the
/// password-check limit, the server's reason, or "couldn't save".
String _formMessage(Object error, AppL10n l) => switch (error) {
  ApiException(kind: ApiErrorKind.rateLimited) => l.profileRateLimited,
  _ => failureMessage(error, l, fallback: l.profileSaveFailed),
};

// --- Sheet chrome -------------------------------------------------------------

/// A sheet with inputs: its title and a visible close (X), the fields, the
/// failure no field claims, and the save button — all above the keyboard.
class _EditorFrame extends StatelessWidget {
  final String title;
  final List<Widget> children;
  final String actionLabel;
  final VoidCallback onAction;
  final bool busy;
  final String? formError;

  const _EditorFrame({
    required this.title,
    required this.children,
    required this.actionLabel,
    required this.onAction,
    required this.busy,
    this.formError,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final error = formError;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 0, 8, 16),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SheetTitle(title),
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 8),
                    ...children,
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Semantics(
                          liveRegion: true,
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.error_outline,
                                size: 18,
                                color: c.error,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  error,
                                  style: text.bodySmall!.copyWith(
                                    color: c.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    const SizedBox(height: 20),
                    PrimaryButton(
                      label: actionLabel,
                      loading: busy,
                      onPressed: onAction,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetTitle extends StatelessWidget {
  final String title;
  const _SheetTitle(this.title);

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Expanded(
          child: Semantics(
            header: true,
            child: Text(title, style: text.titleLarge),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }
}

/// Selects all of [controller]'s text — what a refused field does instead
/// of clearing it (design-research §4.4), so it can be retyped or fixed.
void _selectAll(TextEditingController controller) => controller.selection =
    TextSelection(baseOffset: 0, extentOffset: controller.text.length);

class _Note extends StatelessWidget {
  final String text;
  final Color? color;
  const _Note(this.text, {this.color});

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    return Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall!.copyWith(color: color ?? c.inkMid),
    );
  }
}

/// A password field with its own show/hide toggle (a 48 dp target).
class _SecretField extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final String label;
  final String? errorText;
  final Iterable<String> autofillHints;
  final TextInputAction action;
  final ValueChanged<String> onSubmitted;
  final ValueChanged<String> onChanged;

  const _SecretField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.errorText,
    required this.autofillHints,
    required this.action,
    required this.onSubmitted,
    required this.onChanged,
  });

  @override
  State<_SecretField> createState() => _SecretFieldState();
}

class _SecretFieldState extends State<_SecretField> {
  var _hidden = true;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return TextField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _hidden,
      autocorrect: false,
      enableSuggestions: false,
      keyboardType: TextInputType.visiblePassword,
      textInputAction: widget.action,
      autofillHints: widget.autofillHints,
      onSubmitted: widget.onSubmitted,
      onChanged: widget.onChanged,
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: widget.errorText,
        errorMaxLines: 3,
        suffixIcon: IconButton(
          tooltip: _hidden ? l.profileShowPassword : l.profileHidePassword,
          icon: Icon(
            _hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          onPressed: () => setState(() => _hidden = !_hidden),
        ),
      ),
    );
  }
}

// --- Name ---------------------------------------------------------------------

/// The name, in a one-field sheet.
Future<void> showNameEditor(BuildContext context, {required User user}) =>
    _showSheet<void>(context, (_) => _NameSheet(user: user));

class _NameSheet extends ConsumerStatefulWidget {
  final User user;
  const _NameSheet({required this.user});

  @override
  ConsumerState<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends ConsumerState<_NameSheet> {
  /// The server's limit (`name`: 1–80 characters).
  static const _maxLength = 80;

  late final _name = TextEditingController(text: widget.user.displayName);
  var _saving = false;
  var _submitted = false;
  String? _nameError;
  String? _formError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  String? _check(AppL10n l) =>
      _name.text.trim().isEmpty ? l.validationDetail('blank') : null;

  Future<void> _save() async {
    // The keyboard's done key can send it again while it is being saved.
    if (_saving) return;
    final l = context.l10n;
    _submitted = true;
    final problem = _check(l);
    if (problem != null) {
      Haptics.danger();
      setState(() => _nameError = problem);
      return;
    }
    final name = _name.text.trim();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (name == widget.user.displayName) {
      navigator.pop();
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      await ref.read(profileActionsProvider).update(name: name);
      Haptics.success();
      if (mounted) navigator.pop();
      _confirmSaved(messenger, l.profileNameSaved);
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final field = e is ApiException ? e.fieldMessage(l, 'name') : null;
      setState(() {
        _saving = false;
        _nameError = field;
        _formError = field == null ? _formMessage(e, l) : null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return _EditorFrame(
      title: l.profileName,
      actionLabel: l.actionSave,
      onAction: _save,
      busy: _saving,
      formError: _formError,
      children: [
        TextField(
          controller: _name,
          autofocus: true,
          maxLength: _maxLength,
          maxLengthEnforcement: MaxLengthEnforcement.enforced,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          autofillHints: const [AutofillHints.name],
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_submitted) setState(() => _nameError = _check(l));
          },
          decoration: InputDecoration(
            labelText: l.profileName,
            helperText: l.profileNameHint,
            errorText: _nameError,
          ),
        ),
      ],
    );
  }
}

// --- E-mail -------------------------------------------------------------------

/// The e-mail, with the current password the server asks for along with it.
Future<void> showEmailEditor(BuildContext context, {required User user}) =>
    _showSheet<void>(context, (_) => _EmailSheet(user: user));

class _EmailSheet extends ConsumerStatefulWidget {
  final User user;
  const _EmailSheet({required this.user});

  @override
  ConsumerState<_EmailSheet> createState() => _EmailSheetState();
}

class _EmailSheetState extends ConsumerState<_EmailSheet> {
  late final _email = TextEditingController(text: widget.user.email);
  final _password = TextEditingController();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();
  var _saving = false;
  var _submitted = false;
  String? _emailError;
  String? _passwordError;
  String? _formError;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  bool get _unchanged =>
      _email.text.trim().toLowerCase() == widget.user.email.toLowerCase();

  /// The checks the server would make first, so a typo costs no password
  /// attempt (they count toward a rate limit).
  ({String? email, String? password}) _check(AppL10n l) {
    final email = _email.text.trim();
    return (
      email: email.isEmpty
          ? l.validationDetail('blank')
          : !RegExp(r'^[^@\s]+@[^@\s]+$').hasMatch(email)
          ? l.validationDetail('invalid')
          : null,
      password: _password.text.isEmpty ? l.errCurrentPasswordRequired : null,
    );
  }

  void _recheck(AppL10n l) {
    if (!_submitted) return;
    final problems = _check(l);
    setState(() {
      _emailError = problems.email;
      _passwordError = problems.password;
    });
  }

  Future<void> _save() async {
    // A second send would spend another password attempt.
    if (_saving) return;
    final l = context.l10n;
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    if (_unchanged) {
      navigator.pop();
      return;
    }
    _submitted = true;
    final problems = _check(l);
    if (problems.email != null || problems.password != null) {
      Haptics.danger();
      setState(() {
        _emailError = problems.email;
        _passwordError = problems.password;
      });
      (problems.email != null ? _emailFocus : _passwordFocus).requestFocus();
      return;
    }
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      await ref
          .read(profileActionsProvider)
          .update(email: _email.text.trim(), currentPassword: _password.text);
      Haptics.success();
      TextInput.finishAutofillContext();
      if (mounted) navigator.pop();
      _confirmSaved(messenger, l.profileEmailSaved);
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final refusal = e is ApiException ? e : null;
      final emailError = refusal?.fieldMessage(l, 'email');
      final passwordError = switch (refusal?.code) {
        'invalid_current_password' => l.errInvalidCurrentPassword,
        'current_password_required' => l.errCurrentPasswordRequired,
        _ => refusal?.fieldMessage(l, 'current_password'),
      };
      setState(() {
        _saving = false;
        _emailError = emailError;
        _passwordError = passwordError;
        _formError = emailError == null && passwordError == null
            ? _formMessage(e, l)
            : null;
      });
      if (passwordError != null) {
        _selectAll(_password);
        _passwordFocus.requestFocus();
      } else if (emailError != null) {
        _emailFocus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AutofillGroup(
      child: _EditorFrame(
        title: l.profileEmailTitle,
        actionLabel: l.actionSave,
        onAction: _save,
        busy: _saving,
        formError: _formError,
        children: [
          TextField(
            controller: _email,
            focusNode: _emailFocus,
            autofocus: true,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            autofillHints: const [AutofillHints.email],
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            onChanged: (_) => _recheck(l),
            decoration: InputDecoration(
              labelText: l.profileEmailNew,
              errorText: _emailError,
            ),
          ),
          const SizedBox(height: 12),
          _SecretField(
            controller: _password,
            focusNode: _passwordFocus,
            label: l.profileCurrentPassword,
            errorText: _passwordError,
            autofillHints: const [AutofillHints.password],
            action: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => _recheck(l),
          ),
          const SizedBox(height: 12),
          _Note(l.profileEmailNote),
        ],
      ),
    );
  }
}

// --- Password -----------------------------------------------------------------

/// The password: the current one, the new one, and the new one again.
Future<void> showPasswordEditor(BuildContext context) =>
    _showSheet<void>(context, (_) => const _PasswordSheet());

class _PasswordSheet extends ConsumerStatefulWidget {
  const _PasswordSheet();

  @override
  ConsumerState<_PasswordSheet> createState() => _PasswordSheetState();
}

class _PasswordSheetState extends ConsumerState<_PasswordSheet> {
  /// The server's limits (Devise: 6–128 characters).
  static const _minLength = 6;
  static const _maxLength = 128;

  final _current = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  final _currentFocus = FocusNode();
  final _passwordFocus = FocusNode();
  final _confirmationFocus = FocusNode();
  var _saving = false;
  var _submitted = false;
  String? _currentError;
  String? _passwordError;
  String? _confirmationError;
  String? _formError;

  @override
  void dispose() {
    for (final c in [_current, _password, _confirmation]) {
      c.dispose();
    }
    for (final f in [_currentFocus, _passwordFocus, _confirmationFocus]) {
      f.dispose();
    }
    super.dispose();
  }

  ({String? current, String? password, String? confirmation}) _check(
    AppL10n l,
  ) {
    final password = _password.text;
    return (
      current: _current.text.isEmpty ? l.errCurrentPasswordRequired : null,
      password: password.trim().isEmpty
          ? l.validationDetail('blank')
          : password.length < _minLength
          ? l.validationDetail('too_short', count: _minLength)
          : password.length > _maxLength
          ? l.validationDetail('too_long', count: _maxLength)
          : null,
      confirmation: _confirmation.text != password
          ? l.validationDetail('confirmation')
          : null,
    );
  }

  void _show(({String? current, String? password, String? confirmation}) p) =>
      setState(() {
        _currentError = p.current;
        _passwordError = p.password;
        _confirmationError = p.confirmation;
      });

  void _recheck(AppL10n l) {
    if (_submitted) _show(_check(l));
  }

  void _focusFirstError() {
    if (_currentError != null) {
      _currentFocus.requestFocus();
    } else if (_passwordError != null) {
      _passwordFocus.requestFocus();
    } else if (_confirmationError != null) {
      _confirmationFocus.requestFocus();
    }
  }

  Future<void> _save() async {
    // A second send would leave with the token the first one replaces.
    if (_saving) return;
    final l = context.l10n;
    _submitted = true;
    final problems = _check(l);
    if (problems.current != null ||
        problems.password != null ||
        problems.confirmation != null) {
      Haptics.danger();
      _show(problems);
      _focusFirstError();
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _formError = null;
    });
    try {
      await ref
          .read(profileActionsProvider)
          .changePassword(
            currentPassword: _current.text,
            password: _password.text,
            passwordConfirmation: _confirmation.text,
          );
      Haptics.success();
      TextInput.finishAutofillContext();
      if (mounted) navigator.pop();
      _confirmSaved(messenger, l.profilePasswordSaved);
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      final refusal = e is ApiException ? e : null;
      final current = switch (refusal?.code) {
        'invalid_current_password' => l.errInvalidCurrentPassword,
        'current_password_required' => l.errCurrentPasswordRequired,
        _ => refusal?.fieldMessage(l, 'current_password'),
      };
      final password = refusal?.fieldMessage(l, 'password');
      final confirmation = refusal?.fieldMessage(l, 'password_confirmation');
      setState(() {
        _saving = false;
        _formError = current == null && password == null && confirmation == null
            ? _formMessage(e, l)
            : null;
      });
      _show((current: current, password: password, confirmation: confirmation));
      if (current != null) _selectAll(_current);
      _focusFirstError();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return AutofillGroup(
      child: _EditorFrame(
        title: l.profilePasswordTitle,
        actionLabel: l.profilePasswordTitle,
        onAction: _save,
        busy: _saving,
        formError: _formError,
        children: [
          _SecretField(
            key: const ValueKey('current_password'),
            controller: _current,
            focusNode: _currentFocus,
            label: l.profileCurrentPassword,
            errorText: _currentError,
            autofillHints: const [AutofillHints.password],
            action: TextInputAction.next,
            onSubmitted: (_) => _passwordFocus.requestFocus(),
            onChanged: (_) => _recheck(l),
          ),
          const SizedBox(height: 12),
          _SecretField(
            key: const ValueKey('password'),
            controller: _password,
            focusNode: _passwordFocus,
            label: l.profileNewPassword,
            errorText: _passwordError,
            autofillHints: const [AutofillHints.newPassword],
            action: TextInputAction.next,
            onSubmitted: (_) => _confirmationFocus.requestFocus(),
            onChanged: (_) => _recheck(l),
          ),
          const SizedBox(height: 12),
          _SecretField(
            key: const ValueKey('password_confirmation'),
            controller: _confirmation,
            focusNode: _confirmationFocus,
            label: l.profileConfirmPassword,
            errorText: _confirmationError,
            autofillHints: const [AutofillHints.newPassword],
            action: TextInputAction.done,
            onSubmitted: (_) => _save(),
            onChanged: (_) => _recheck(l),
          ),
          const SizedBox(height: 12),
          _Note(l.profilePasswordNote),
        ],
      ),
    );
  }
}

// --- Pickers that save --------------------------------------------------------

/// One choice of a [_ChoiceSheet].
class _Item<T> {
  final T value;
  final String label;
  final String? subtitle;
  final String? trailing;

  const _Item(this.value, this.label, {this.subtitle, this.trailing});
}

/// A titled run of choices (the zones that match this device, then all).
class _Group<T> {
  final String? header;
  final List<_Item<T>> items;
  const _Group(this.items, {this.header});
}

/// A list of choices that saves the one tapped, then closes; while the
/// save runs the row shows a spinner, and a refusal shows above the list.
///
/// The choices may come from a read model ([source]): a skeleton-free
/// spinner on the first load, the error with a retry when it failed, and
/// the thin hint while it refreshes behind the list.
class _ChoiceSheet<T> extends ConsumerStatefulWidget {
  final String title;
  final String? note;
  final T? selected;

  /// The server field the save sends, for the refusal's wording.
  final String field;
  final AsyncValue<Object?>? source;
  final VoidCallback? onRetry;
  final List<_Group<T>> Function(String query) groups;
  final String? searchHint;
  final Future<bool> Function(BuildContext context, T value)? confirm;
  final Future<Object?> Function(T value) save;
  final String Function(T value) savedMessage;

  const _ChoiceSheet({
    required this.title,
    required this.selected,
    required this.field,
    required this.groups,
    required this.save,
    required this.savedMessage,
    this.note,
    this.source,
    this.onRetry,
    this.searchHint,
    this.confirm,
  });

  @override
  ConsumerState<_ChoiceSheet<T>> createState() => _ChoiceSheetState<T>();
}

class _ChoiceSheetState<T> extends ConsumerState<_ChoiceSheet<T>> {
  final _search = TextEditingController();
  var _query = '';
  T? _saving;
  var _busy = false;
  String? _error;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _pick(T value) async {
    if (_busy) return;
    final navigator = Navigator.of(context);
    if (value == widget.selected) {
      navigator.pop();
      return;
    }
    final confirm = widget.confirm;
    if (confirm != null && !await confirm(context, value)) return;
    if (!mounted) return;
    final l = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    Haptics.tick();
    setState(() {
      _busy = true;
      _saving = value;
      _error = null;
    });
    try {
      await widget.save(value);
      Haptics.success();
      if (mounted) navigator.pop();
      _confirmSaved(messenger, widget.savedMessage(value));
    } catch (e) {
      if (!mounted) return;
      Haptics.danger();
      setState(() {
        _busy = false;
        _saving = null;
        _error =
            (e is ApiException ? e.fieldMessage(l, widget.field) : null) ??
            _formMessage(e, l);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    final source = widget.source;
    final searchable = widget.searchHint != null;
    final groups = widget.groups(_query);
    final rows = <Widget>[
      for (final group in groups) ...[
        if (group.header != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Semantics(
              header: true,
              child: Text(
                group.header!,
                style: text.titleSmall!.copyWith(color: c.inkMid),
              ),
            ),
          ),
        for (final item in group.items) _row(context, item),
      ],
    ];

    // What shows instead of the list: the first load, its failure, or no
    // match for the search.
    Widget? message;
    if (source != null && source.isFirstLoad) {
      message = const Padding(
        padding: EdgeInsets.all(32),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    } else if (source != null && source.hasFailed) {
      message = Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l.profileOptionsFailed,
              textAlign: TextAlign.center,
              style: text.bodyMedium!.copyWith(color: c.inkMid),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: widget.onRetry,
              child: Text(l.actionRetry),
            ),
          ],
        ),
      );
    } else if (rows.isEmpty) {
      message = Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          l.profileTimeZoneNoMatch,
          textAlign: TextAlign.center,
          style: text.bodyMedium!.copyWith(color: c.inkMid),
        ),
      );
    }

    final heading = <Widget>[
      Padding(
        padding: const EdgeInsets.only(left: 20, right: 8),
        child: _SheetTitle(widget.title),
      ),
      if (widget.note != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: _Note(widget.note!),
        ),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Semantics(
            liveRegion: true,
            child: _Note(_error!, color: c.error),
          ),
        ),
    ];

    final Widget content;
    if (searchable) {
      // The title and the note scroll with the zones, the search stays put:
      // with the keyboard up and large text, the list still gets the room
      // that is left.
      final sheetColor =
          Theme.of(context).bottomSheetTheme.modalBackgroundColor ??
          Theme.of(context).bottomSheetTheme.backgroundColor ??
          c.surface3;
      content = SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: CustomScrollView(
          slivers: [
            SliverList.list(children: heading),
            PinnedHeaderSliver(
              child: ColoredBox(
                color: sheetColor,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 4),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    autocorrect: false,
                    onChanged: (q) => setState(() => _query = q),
                    decoration: InputDecoration(
                      hintText: widget.searchHint,
                      prefixIcon: const Icon(Icons.search),
                    ),
                  ),
                ),
              ),
            ),
            if (message != null)
              SliverToBoxAdapter(child: message)
            else
              SliverPadding(
                padding: const EdgeInsets.only(bottom: 8),
                sliver: SliverList.list(children: rows),
              ),
          ],
        ),
      );
    } else {
      content = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ...heading,
          Flexible(
            child:
                message ??
                ListView(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 8),
                  children: rows,
                ),
          ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SyncHint.over(
          active: source?.isRefetching ?? false,
          child: content,
        ),
      ),
    );
  }

  Widget _row(BuildContext context, _Item<T> item) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final selected = item.value == widget.selected;
    final saving = _busy && item.value == _saving;
    final trailing = item.trailing;
    return ListTile(
      selected: selected,
      enabled: !_busy || saving,
      minTileHeight: 56,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      title: Text(item.label, style: text.titleMedium),
      subtitle: item.subtitle == null
          ? null
          : Text(
              item.subtitle!,
              style: text.bodySmall!.copyWith(color: c.inkMid),
            ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (trailing != null)
            Text(trailing, style: text.bodySmall!.copyWith(color: c.inkMid)),
          if (saving) ...[
            const SizedBox(width: 12),
            const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ] else if (selected) ...[
            const SizedBox(width: 12),
            Icon(Icons.check, color: c.gold, size: 20),
          ],
        ],
      ),
      onTap: () => _pick(item.value),
    );
  }
}

// --- Currency -----------------------------------------------------------------

/// The account's currency: what budgets and every total are in. Nothing is
/// converted, so a change asks first, with an example.
Future<void> showCurrencyEditor(BuildContext context, {required User user}) =>
    _showSheet<void>(context, (_) => _CurrencySheet(user: user));

class _CurrencySheet extends ConsumerWidget {
  final User user;
  const _CurrencySheet({required this.user});

  /// The example amount in the confirmation: 5.000,00 in a two-decimal
  /// currency.
  static const _exampleMinorUnits = 500000;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final options = ref.watch(meOptionsProvider);
    final currencies = options.value?.data.currencies ?? const [];
    return _ChoiceSheet<String>(
      title: l.profileCurrency,
      note: l.profileCurrencyNote,
      selected: user.currency,
      field: 'currency',
      source: options,
      onRetry: () => ref.invalidate(meOptionsProvider),
      groups: (_) => [
        _Group([
          for (final currency in currencies)
            _Item(
              currency.code,
              currency.name == currency.code
                  ? currency.code
                  : '${currency.name} (${currency.code})',
              trailing: currency.symbol,
            ),
        ]),
      ],
      confirm: (context, code) {
        final next = currencies.where((c) => c.code == code).firstOrNull;
        return showConfirmDialog(
          context,
          title: l.profileCurrencyConfirmTitle(code),
          message: l.profileCurrencyConfirmBody(
            formatMoney(_exampleMinorUnits, user.currency, user.subunitToUnit),
            formatMoney(_exampleMinorUnits, code, next?.subunitToUnit ?? 100),
          ),
          confirmLabel: l.profileCurrencyConfirm,
        );
      },
      save: (code) => ref.read(profileActionsProvider).update(currency: code),
      savedMessage: l.profileCurrencySaved,
    );
  }
}

// --- Time zone ----------------------------------------------------------------

/// The account's time zone: what "today" and every time is counted in. The
/// zones that read the same time as this phone come first.
Future<void> showTimeZoneEditor(BuildContext context, {required User user}) =>
    _showSheet<void>(context, (_) => _TimeZoneSheet(user: user));

class _TimeZoneSheet extends ConsumerWidget {
  final User user;
  const _TimeZoneSheet({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    final options = ref.watch(meOptionsProvider);
    final bundle = options.value?.data;
    final device = ref.watch(deviceUtcOffsetProvider);
    final current = bundle?.zoneOf(
      value: user.timezone,
      iana: user.timezoneIana,
    );

    _Item<String> item(TimeZoneOption zone) => _Item(
      zone.value,
      zone.value,
      subtitle: zone.iana,
      trailing: zone.utcOffset == null
          ? null
          : 'UTC${formatUtcOffset(zone.utcOffset!)}',
    );

    return _ChoiceSheet<String>(
      title: l.profileTimeZone,
      note: l.profileTimeZoneNote,
      selected: current?.value ?? user.timezone,
      field: 'timezone',
      source: options,
      onRetry: () => ref.invalidate(meOptionsProvider),
      searchHint: l.profileTimeZoneSearch,
      groups: (query) {
        if (bundle == null) return const [];
        final all = [
          for (final zone in bundle.timezones)
            if (zone.matches(query)) zone,
        ];
        final nearby = [
          for (final zone in bundle.zonesAt(device))
            if (zone.matches(query)) zone,
        ];
        return [
          if (nearby.isNotEmpty)
            _Group([
              for (final zone in nearby) item(zone),
            ], header: l.profileTimeZoneDeviceGroup(formatUtcOffset(device))),
          if (all.isNotEmpty)
            _Group([
              for (final zone in all) item(zone),
            ], header: nearby.isEmpty ? null : l.profileTimeZoneAllGroup),
        ];
      },
      save: (zone) => ref.read(profileActionsProvider).update(timezone: zone),
      savedMessage: l.profileTimeZoneSaved,
    );
  }
}

// --- Weekly review day --------------------------------------------------------

/// The day of the web's weekly review reminder, Monday first.
Future<void> showWeeklyReviewEditor(
  BuildContext context, {
  required User user,
}) => _showSheet<void>(context, (_) => _WeeklyReviewSheet(user: user));

class _WeeklyReviewSheet extends ConsumerWidget {
  final User user;
  const _WeeklyReviewSheet({required this.user});

  static const _mondayFirst = [1, 2, 3, 4, 5, 6, 0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = context.l10n;
    String name(int day) => weekdayName(day, locale: l.localeCode);
    return _ChoiceSheet<int>(
      title: l.profileWeeklyReview,
      note: l.profileWeeklyReviewNote,
      selected: user.weeklyReviewDay,
      field: 'weekly_review_day',
      groups: (_) => [
        _Group([for (final day in _mondayFirst) _Item(day, name(day))]),
      ],
      save: (day) =>
          ref.read(profileActionsProvider).update(weeklyReviewDay: day),
      savedMessage: (day) => l.profileWeeklyReviewSaved(name(day)),
    );
  }
}

// --- Sign out -----------------------------------------------------------------

/// Asks, in a sheet, before signing out: it says that every device signed
/// in to the account is signed out, and warns when an unsaved journal draft
/// would go. "Çıkış Yap" then signs out (see [ProfileActions.signOut]) and
/// the router takes the user to the login screen.
Future<void> showSignOutSheet(BuildContext context) =>
    _showSheet<void>(context, (_) => const _SignOutSheet());

class _SignOutSheet extends ConsumerStatefulWidget {
  const _SignOutSheet();

  @override
  ConsumerState<_SignOutSheet> createState() => _SignOutSheetState();
}

class _SignOutSheetState extends ConsumerState<_SignOutSheet> {
  late final Future<bool> _draft = ref
      .read(profileActionsProvider)
      .hasUnsavedDraft();
  var _busy = false;

  Future<void> _signOut() async {
    setState(() => _busy = true);
    final navigator = Navigator.of(context);
    await ref.read(profileActionsProvider).signOut();
    // The router has left for the login screen; the sheet goes with the
    // page under it, unless it is still up.
    if (mounted && navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The words scroll when large text makes them too long; the two
            // buttons stay on screen under them.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(
                        l.profileSignOutTitle,
                        style: text.titleLarge,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l.profileSignOutBody,
                      style: text.bodyMedium!.copyWith(color: c.inkMid),
                    ),
                    FutureBuilder<bool>(
                      future: _draft,
                      builder: (context, snapshot) {
                        if (snapshot.data != true) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.warning_amber_rounded,
                                size: 20,
                                color: c.warning,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  l.profileSignOutDraft,
                                  style: text.bodyMedium!.copyWith(
                                    color: c.warning,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _signOut,
              style: FilledButton.styleFrom(
                backgroundColor: c.error,
                foregroundColor: c.inkHi,
                disabledBackgroundColor: c.error.withValues(alpha: 0.6),
                minimumSize: const Size.fromHeight(52),
              ),
              child: _busy
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: c.inkHi,
                      ),
                    )
                  : Text(l.profileSignOut),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(l.actionCancel),
            ),
          ],
        ),
      ),
    );
  }
}
