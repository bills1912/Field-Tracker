class Respondent {
  final String id;
  final String name;
  final String? phone;
  final String? address;
  final double latitude;
  final double longitude;
  final RespondentStatus status;
  final String surveyId;
  final String? enumeratorId;
  final Map<String, dynamic>? surveyData;
  final DateTime createdAt;
  final DateTime updatedAt;

  Respondent({
    required this.id,
    required this.name,
    this.phone,
    this.address,
    required this.latitude,
    required this.longitude,
    required this.status,
    required this.surveyId,
    this.enumeratorId,
    this.surveyData,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Respondent.fromJson(Map<String, dynamic> json) {
    return Respondent(
      id: json['id'],
      name: json['name'],
      phone: json['phone'],
      address: json['address'],
      latitude: (json['location']?['latitude'] ?? json['latitude']).toDouble(),
      longitude: (json['location']?['longitude'] ?? json['longitude']).toDouble(),
      status: RespondentStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => RespondentStatus.pending,
      ),
      surveyId: json['survey_id'],
      enumeratorId: json['enumerator_id'],
      surveyData: json['survey_data'],
      createdAt: DateTime.parse(json['created_at']),
      updatedAt: DateTime.parse(json['updated_at']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'phone': phone,
      'address': address,
      'location': {
        'latitude': latitude,
        'longitude': longitude,
      },
      'status': status.name,
      'survey_id': surveyId,
      'enumerator_id': enumeratorId,
      'survey_data': surveyData,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  Respondent copyWith({
    String? id,
    String? name,
    String? phone,
    String? address,
    double? latitude,
    double? longitude,
    RespondentStatus? status,
    String? surveyId,
    String? enumeratorId,
    Map<String, dynamic>? surveyData,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return Respondent(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      surveyId: surveyId ?? this.surveyId,
      enumeratorId: enumeratorId ?? this.enumeratorId,
      surveyData: surveyData ?? this.surveyData,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

enum RespondentStatus { pending, in_progress, completed }