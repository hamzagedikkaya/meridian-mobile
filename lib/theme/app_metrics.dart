/// Spacing, insets, hit targets and corner radii (design-analysis §3.8–3.9).
///
/// Use these instead of literals so the rhythm stays one system:
///
///     Padding(padding: const EdgeInsets.symmetric(horizontal: Insets.gutter))
///     SizedBox(height: Gap.md)
///     BorderRadius.circular(Radii.lg)
///
/// Rhythm (§3.8): 12 dp between stacked cards · 24 dp before a 48 dp
/// `SectionHeader` · 4 dp between a header and its card · 32 dp between
/// sections without a header · 20 dp screen edge · 20 dp card padding
/// (16 in the goal grid) · list cards pad 4 dp vertically and let rows bring
/// their own 20 dp horizontally.
library;

import 'package:flutter/painting.dart';

/// The spacing scale, in dp.
abstract final class Gap {
  static const xxs = 2.0;
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
  static const xxl = 24.0;
  static const x3 = 32.0;
  static const x4 = 40.0;
  static const x5 = 48.0;
}

/// Named paddings, in dp.
abstract final class Insets {
  /// Screen edge, left and right.
  static const gutter = 20.0;

  /// Standard card padding (hero cards too).
  static const card = 20.0;

  /// Card padding in the goal grid only.
  static const cardGrid = 16.0;

  /// Row padding: horizontal and vertical.
  static const rowH = 20.0;
  static const rowV = 10.0;

  /// Sheet and form side padding.
  static const sheetH = 20.0;
  static const formH = 20.0;

  /// Bottom padding of a list under an extended FAB (56 + 16 + 16 + slack).
  /// Add `MediaQuery.paddingOf(context).bottom` on edge-to-edge screens.
  static const fabClearance = 96.0;

  /// Bottom padding of a list under the CaptureBar.
  static const captureBarClearance = 84.0;
}

/// Touch targets.
abstract final class Hit {
  /// The minimum hit area of anything tappable, 48×48 dp — the visual can
  /// be smaller. Adjacent targets keep ≥ 8 dp ([Gap.sm]) apart.
  static const min = 48.0;
  static const minSize = Size(min, min);
}

/// Corner radii, in dp. Plain circular corners, no superellipse.
///
/// | Token | Where |
/// |---|---|
/// | [xs] 4 | Bars (1.5 on 2 dp bars), skeleton text bones |
/// | [sm] 8 | Tooltip, keypad ripple mask, chart tooltip |
/// | [md] 12 | Input, picker row, StatTile, notice card, snackbar, popup menu |
/// | [lg] 16 | Card, FAB, AccountTile |
/// | [xl] 24 | Sheet top corners, dialog |
/// | `StadiumBorder` | Chip, pill, segment, badge, Filled and Outlined buttons |
abstract final class Radii {
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;

  static const xsAll = BorderRadius.all(Radius.circular(xs));
  static const smAll = BorderRadius.all(Radius.circular(sm));
  static const mdAll = BorderRadius.all(Radius.circular(md));
  static const lgAll = BorderRadius.all(Radius.circular(lg));
  static const xlAll = BorderRadius.all(Radius.circular(xl));

  /// A sheet's rounded top.
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(xl));
}
