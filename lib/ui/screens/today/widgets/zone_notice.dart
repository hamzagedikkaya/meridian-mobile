import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/session.dart';
import '../../../../data/current_day.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../../models/date_utils.dart';
import '../../../../theme/app_colors.dart';

/// Says, on Today, that days and times follow the account's time zone —
/// shown only while this phone is in another zone (see
/// [zoneMismatchProvider]), so a trip abroad does not make "Bugün", a habit
/// day or an event's "18:00" look wrong without a word.
///
/// Dismissing it hides it for this pair of zones; a new pair (the next
/// trip, a change of the account's zone) shows it again. Profile keeps the
/// same information for good.
class TodayZoneNotice extends ConsumerStatefulWidget {
  const TodayZoneNotice({super.key});

  @override
  ConsumerState<TodayZoneNotice> createState() => _TodayZoneNoticeState();
}

class _TodayZoneNoticeState extends ConsumerState<TodayZoneNotice> {
  /// The dismissed pair, once read from the device's preferences (only ever
  /// when there is a mismatch to show).
  String? _dismissed;
  var _read = false;

  static String _key(ZoneMismatch m) =>
      '${m.account.inMinutes}|${m.device.inMinutes}';

  String? _dismissedPair() {
    if (!_read) {
      _read = true;
      _dismissed = ref
          .read(sharedPrefsProvider)
          .getString(PrefKeys.zoneNoticeDismissed);
    }
    return _dismissed;
  }

  void _dismiss(ZoneMismatch mismatch) {
    final key = _key(mismatch);
    setState(() => _dismissed = key);
    ref.read(sharedPrefsProvider).setString(PrefKeys.zoneNoticeDismissed, key);
  }

  @override
  Widget build(BuildContext context) {
    final mismatch = ref.watch(zoneMismatchProvider);
    if (mismatch == null || _dismissedPair() == _key(mismatch)) {
      return const SizedBox.shrink();
    }
    final c = context.nok;
    final text = Theme.of(context).textTheme;
    final l = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 4, 4, 4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.hairline),
        ),
        child: Row(
          children: [
            Icon(Icons.schedule, size: 18, color: c.inkMid),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l.todayZoneNotice(
                  mismatch.zone,
                  formatUtcOffset(mismatch.account),
                ),
                style: text.bodySmall!.copyWith(color: c.inkMid),
              ),
            ),
            IconButton(
              tooltip: l.actionDismiss,
              icon: Icon(Icons.close, size: 18, color: c.inkLow),
              onPressed: () => _dismiss(mismatch),
            ),
          ],
        ),
      ),
    );
  }
}
