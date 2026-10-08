import 'date_utils.dart';
import 'json_read.dart';

class User {
  final int id;
  final String displayName;
  final String initials;
  final String email;
  final String currency;
  final int subunitToUnit;
  final String locale;
  final String themePreference;

  /// The account's time zone as Rails names it (`"Istanbul"`): the zone the
  /// server computes "today", day boundaries and every datetime in.
  final String? timezone;

  /// The same zone as an IANA id (`"Europe/Istanbul"`).
  final String? timezoneIana;

  /// The zone's UTC offset in effect when the server answered (`+03:00`).
  /// Null from a server that predates G1.
  final Duration? utcOffset;

  /// The day the web's weekly review reminder falls on: 0 Sunday … 6
  /// Saturday. Null from a server that predates it.
  final int? weeklyReviewDay;

  const User({
    required this.id,
    required this.displayName,
    required this.initials,
    required this.email,
    required this.currency,
    required this.subunitToUnit,
    required this.locale,
    required this.themePreference,
    this.timezone,
    this.timezoneIana,
    this.utcOffset,
    this.weeklyReviewDay,
  });

  /// The zone's name to show: the IANA id, else the Rails name, else UTC.
  String get zoneName => timezoneIana ?? timezone ?? 'UTC';

  factory User.fromJson(Map<String, dynamic> json) => User(
        id: readId(json['id']),
        displayName: (json['display_name'] ?? json['name']) as String,
        initials: (json['initials'] as String?) ?? '',
        email: json['email'] as String,
        currency: (json['currency'] as String?) ?? 'TRY',
        subunitToUnit: readInt(json['subunit_to_unit'], fallback: 100),
        locale: (json['locale'] as String?) ?? 'tr',
        themePreference: (json['theme_preference'] as String?) ?? 'system',
        timezone: json['timezone'] as String?,
        timezoneIana: json['timezone_iana'] as String?,
        utcOffset: parseUtcOffset(json['utc_offset']),
        weeklyReviewDay: switch (readIntOrNull(json['weekly_review_day'])) {
          final int day when day >= 0 && day <= 6 => day,
          _ => null,
        },
      );
}
