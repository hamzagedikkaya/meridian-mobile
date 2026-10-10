import 'package:flutter/material.dart';

import '../../../../data/current_day.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import 'nudges.dart';

/// Says, on Today, that days and times follow the account's time zone —
/// shown only while this phone is in another zone (see
/// [zoneMismatchProvider]), so a trip abroad does not make "Bugün", a habit
/// day or an event's "18:00" look wrong without a word.
///
/// One of the nudge slot's cards ([TodayNudgeSlot] decides when it shows).
/// Dismissing it hides it for this pair of zones ([zoneNoticeKey]); a new
/// pair (the next trip, a change of the account's zone) shows it again.
/// Profile keeps the same information for good.
class TodayZoneNotice extends StatelessWidget {
  const TodayZoneNotice({
    super.key,
    required this.mismatch,
    required this.onDismiss,
  });

  final ZoneMismatch mismatch;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final l = context.l10n;
    return NudgeCard(
      icon: Icons.schedule_rounded,
      message: l.todayZoneNotice(
        mismatch.zone,
        formatUtcOffset(mismatch.account),
      ),
      onDismiss: onDismiss,
    );
  }
}

/// What a dismissal of the zone notice remembers: the pair of zones.
String zoneNoticeKey(ZoneMismatch m) =>
    '${m.account.inMinutes}|${m.device.inMinutes}';
