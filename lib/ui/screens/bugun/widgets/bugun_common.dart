import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';

/// Parse a "#B8860B" / "#b8860b" hex string into a Color (opaque).
Color hexColor(String hex, {Color fallback = const Color(0xFF6B8FA0)}) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  final value = int.tryParse(h, radix: 16);
  return value == null ? fallback : Color(value);
}

/// Todo priority → 3dp left edge bar color (design §4.3).
Color priorityEdgeColor(NokturnColors c, String priority) => switch (priority) {
      'urgent' => c.error,
      'high' => c.warning,
      'medium' => c.goldDim,
      _ => Colors.transparent,
    };
