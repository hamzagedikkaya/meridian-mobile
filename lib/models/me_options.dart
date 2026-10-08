import 'currency.dart';
import 'date_utils.dart';
import 'user.dart';

/// What a password change answers with (`PATCH /me/password`): the
/// account's new token — the old one no longer works anywhere — and the
/// user.
typedef PasswordChanged = ({String token, User user});

/// One time zone the server accepts as the account's (`GET /me/options`
/// `timezones[]`).
class TimeZoneOption {
  /// The Rails zone name to send as `timezone` (`"Istanbul"`).
  final String value;

  /// The web's label, with the zone's standard offset
  /// (`"(GMT+03:00) Istanbul"`).
  final String name;

  /// The IANA id the server uses for it (`"Europe/Istanbul"`).
  final String iana;

  /// The offset in effect now, daylight saving included; null when the
  /// server sent none it could read.
  final Duration? utcOffset;

  const TimeZoneOption({
    required this.value,
    required this.name,
    required this.iana,
    this.utcOffset,
  });

  factory TimeZoneOption.fromJson(Map<String, dynamic> json) {
    final value = (json['value'] as String?) ?? '';
    return TimeZoneOption(
      value: value,
      name: (json['name'] as String?) ?? value,
      iana: (json['iana'] as String?) ?? value,
      utcOffset: parseUtcOffset(json['utc_offset']),
    );
  }

  /// Whether [query] — typed in the picker's search — names this zone: by
  /// its name, its Rails name, its IANA id or its offset (`+03`, `+3`,
  /// `UTC+03`, `GMT+3`, as the picker's hint suggests), ignoring case and
  /// the Turkish dotted/dotless i.
  bool matches(String query) {
    final q = _folded(query.trim());
    if (q.isEmpty) return true;
    // The offset as the picker shows it (`UTC+03:00`) and unpadded
    // (`UTC+3:00`), so "+3" finds it too.
    final shown = utcOffset == null ? null : formatUtcOffset(utcOffset!);
    final offsets = shown == null
        ? ''
        : 'utc$shown utc${shown.replaceFirst(RegExp(r'(?<=[+-])0(?=\d)'), '')}';
    final haystack = _folded('$name $value $iana $offsets');
    if (haystack.contains(q)) return true;
    // "GMT+3", "UTC +3": the offset, however its prefix was typed.
    final asUtc = q.replaceFirst(RegExp(r'^(?:utc|gmt)\s*(?=[+-])'), 'utc');
    return asUtc != q && haystack.contains(asUtc);
  }

  static String _folded(String text) => text
      .replaceAll('İ', 'i')
      .replaceAll('I', 'i')
      .replaceAll('ı', 'i')
      .toLowerCase()
      .replaceAll('_', ' ');
}

/// The choices behind the profile pickers (`GET /me/options`): the
/// currencies and time zones the server accepts for the account. Labels
/// are in the account's language.
///
/// Weekdays, languages and themes are not read from here: the app words
/// them itself, so they read in the app's language and need no request.
class MeOptions {
  final List<CurrencyOption> currencies;
  final List<TimeZoneOption> timezones;

  const MeOptions({required this.currencies, required this.timezones});

  factory MeOptions.fromJson(Map<String, dynamic> json) => MeOptions(
    currencies: [
      for (final raw in (json['currencies'] as List?) ?? const [])
        if (raw is Map<String, dynamic>) CurrencyOption.fromJson(raw),
    ],
    timezones: [
      for (final raw in (json['timezones'] as List?) ?? const [])
        if (raw is Map<String, dynamic> && raw['value'] is String)
          TimeZoneOption.fromJson(raw),
    ],
  );

  /// The zone the account is in: by its Rails name, else by its IANA id
  /// (the first zone that uses it, as the server would store it).
  TimeZoneOption? zoneOf({String? value, String? iana}) {
    for (final zone in timezones) {
      if (value != null && zone.value == value) return zone;
    }
    for (final zone in timezones) {
      if (iana != null && zone.iana == iana) return zone;
    }
    return null;
  }

  /// The zones whose clock reads the same as a device [offset] from UTC
  /// right now — what the time-zone picker suggests first, since the phone
  /// does not tell the app its zone's name.
  List<TimeZoneOption> zonesAt(Duration offset) => [
    for (final zone in timezones)
      if (zone.utcOffset == offset) zone,
  ];
}
