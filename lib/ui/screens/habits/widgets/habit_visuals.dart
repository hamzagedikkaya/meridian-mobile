import 'package:flutter/material.dart';
import '../../../../models/habit.dart';
import '../../../../theme/app_colors.dart';

/// Parse "#B8860B" / "#b8860b" → Color, with a gold fallback.
Color hexColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  if (h.length != 8) return const Color(0xFFD4A853);
  final v = int.tryParse(h, radix: 16);
  return v == null ? const Color(0xFFD4A853) : Color(v);
}

/// Fill + optional border for a per-habit chain / heatmap cell (base = habit
/// color) — design §4.5.
({Color fill, Color? border}) habitChainCell(
  ChainStatus status,
  Color base,
  NokturnColors c,
) {
  switch (status) {
    case ChainStatus.completed:
    case ChainStatus.perfect:
      return (fill: base, border: null);
    case ChainStatus.partial:
      return (fill: base.withValues(alpha: 0.4), border: null);
    case ChainStatus.todayPending:
      return (fill: Colors.transparent, border: c.gold);
    case ChainStatus.noHabits:
      return (fill: Colors.transparent, border: null);
    case ChainStatus.missed:
      return (fill: c.surface2, border: null);
  }
}
