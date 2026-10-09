import 'package:flutter/material.dart';
import '../../../../theme/app_colors.dart';
import '../../../../theme/entity_color.dart';

/// Parse a "#B8860B" / "#b8860b" hex string into a Color (opaque).
/// New code draws record colours through `entityTone` (theme/entity_color).
Color hexColor(String hex, {Color fallback = const Color(0xFF6B8FA0)}) =>
    parseEntityHex(hex, fallback: fallback);

/// Todo priority → 3dp left edge bar color (design §4.3).
Color priorityEdgeColor(NokturnColors c, String priority) => switch (priority) {
      'urgent' => c.error,
      'high' => c.warning,
      'medium' => c.goldDim,
      _ => Colors.transparent,
    };
