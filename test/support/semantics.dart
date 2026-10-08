import 'package:flutter/semantics.dart';

/// Runs [node]'s custom semantics action named [label] — what a screen
/// reader's actions menu does (a row's swipe actions, say). Fails when the
/// node has no such action.
void performCustomAction(SemanticsNode node, String label) {
  final ids = node.getSemanticsData().customSemanticsActionIds ?? const [];
  final action = ids
      .map(CustomSemanticsAction.getAction)
      .firstWhere((a) => a?.label == label, orElse: () => null);
  if (action == null) {
    throw StateError('No custom action "$label" on $node');
  }
  node.owner!.performAction(
    node.id,
    SemanticsAction.customAction,
    CustomSemanticsAction.getIdentifier(action),
  );
}

/// The labels of [node]'s custom semantics actions.
List<String> customActionLabels(SemanticsNode node) => [
      for (final id
          in node.getSemanticsData().customSemanticsActionIds ?? const <int>[])
        ?CustomSemanticsAction.getAction(id)?.label,
    ];
