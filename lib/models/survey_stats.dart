class SurveyStats {
  final String surveyId;
  final int totalRespondents;
  final int pending;
  final int inProgress;
  final int completed;
  final double completionRate;

  SurveyStats({
    required this.surveyId,
    required this.totalRespondents,
    required this.pending,
    required this.inProgress,
    required this.completed,
    required this.completionRate,
  });

  factory SurveyStats.fromJson(Map<String, dynamic> json) {
    return SurveyStats(
      surveyId: json['survey_id'],
      totalRespondents: json['total_respondents'],
      pending: json['pending'],
      inProgress: json['in_progress'],
      completed: json['completed'],
      completionRate: (json['completion_rate'] ?? 0).toDouble(),
    );
  }
}