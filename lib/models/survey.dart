class Survey {
  final String id;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  final String regionLevel;
  final String regionName;
  final List<String> supervisorIds;
  final List<String> enumeratorIds;
  final String createdBy;
  final DateTime createdAt;
  final bool isActive;

  Survey({
    required this.id,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.regionLevel,
    required this.regionName,
    required this.supervisorIds,
    required this.enumeratorIds,
    required this.createdBy,
    required this.createdAt,
    this.isActive = true,
  });

  factory Survey.fromJson(Map<String, dynamic> json) {
    return Survey(
      id: json['id'],
      title: json['title'],
      description: json['description'],
      startDate: DateTime.parse(json['start_date']),
      endDate: DateTime.parse(json['end_date']),
      regionLevel: json['region_level'],
      regionName: json['region_name'],
      supervisorIds: List<String>.from(json['supervisor_ids'] ?? []),
      enumeratorIds: List<String>.from(json['enumerator_ids'] ?? []),
      createdBy: json['created_by'],
      createdAt: DateTime.parse(json['created_at']),
      isActive: json['is_active'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'description': description,
      'start_date': startDate.toIso8601String(),
      'end_date': endDate.toIso8601String(),
      'region_level': regionLevel,
      'region_name': regionName,
      'supervisor_ids': supervisorIds,
      'enumerator_ids': enumeratorIds,
      'created_by': createdBy,
      'created_at': createdAt.toIso8601String(),
      'is_active': isActive,
    };
  }
}