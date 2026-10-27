class FieldVisit {
  final String id;
  final Map<String, dynamic> data;

  const FieldVisit(this.id, this.data);

  factory FieldVisit.fromJson(Map<String, dynamic> json) {
    final id = json['surveyId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('The server returned a visit without an ID.');
    }
    return FieldVisit(id, Map.unmodifiable(json));
  }

  String text(String key, [String fallback = '']) =>
      data[key]?.toString() ?? fallback;
  double? reading(String key) => (data[key] as num?)?.toDouble();
  String get farmName => text('farmName', 'Farm visit');
  String get status => text('status');
  bool get canRecord => status == 'approved' || status == 'in_progress';
  String get statusLabel => statusLabels[status] ?? 'Visit status unavailable';

  static const statusLabels = {
    'approved': 'Visit approved',
    'in_progress': 'Visit in progress',
    'awaiting_review': 'Admin reviewing report',
    'completed': 'Recommendation released',
    'rejected': 'Cancelled / rejected',
  };
}

class VisitPage {
  final List<FieldVisit> visits;
  final String? nextCursor;
  const VisitPage(this.visits, this.nextCursor);
}
