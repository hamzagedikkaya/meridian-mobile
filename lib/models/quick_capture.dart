/// POST /quick_captures → the parsed record it turned into.
class QuickCaptureResult {
  /// "transaction" | "habit_log" | "todo" | "event_suggestion".
  final String capturedType;
  final int? recordId;
  final String summary;

  const QuickCaptureResult({
    required this.capturedType,
    this.recordId,
    required this.summary,
  });

  factory QuickCaptureResult.fromJson(Map<String, dynamic> json) =>
      QuickCaptureResult(
        capturedType: (json['captured_type'] as String?) ?? '',
        recordId: (json['record_id'] as num?)?.toInt(),
        summary: (json['summary'] as String?) ?? '',
      );
}
