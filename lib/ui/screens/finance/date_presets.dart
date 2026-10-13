/// İşlemler's date presets, as plain dates — no Flutter here, so a test can
/// run them in a VM set to a time zone that changes its clocks.
library;

/// The range of the preset [key] ("month", "30d", "year") around [today]
/// (a local midnight), or null for no such preset.
///
/// Days are counted on the calendar, never as 24-hour spans: across a
/// daylight-saving change a day is 23 or 25 hours long, and
/// `today.subtract(Duration(days: 30))` would land on the evening before —
/// one day too many in "Son 30 gün" for a month after the clocks spring
/// forward.
({DateTime from, DateTime to})? txDatePreset(String key, DateTime today) =>
    switch (key) {
      'month' => (
          from: DateTime(today.year, today.month, 1),
          to: DateTime(today.year, today.month + 1, 0),
        ),
      '30d' => (
          from: DateTime(today.year, today.month, today.day - 30),
          to: today,
        ),
      'year' => (
          from: DateTime(today.year, 1, 1),
          to: DateTime(today.year, 12, 31),
        ),
      _ => null,
    };
