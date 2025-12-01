class SurveyAllocation {
  final String region;
  final String supervisorId;
  final String enumeratorId;

  SurveyAllocation({
    required this.region,
    required this.supervisorId,
    required this.enumeratorId,
  });

  factory SurveyAllocation.fromJson(Map<String, dynamic> json) {
    return SurveyAllocation(
      region: json['region'] ?? '',
      supervisorId: json['supervisorId'] ?? '',
      enumeratorId: json['enumeratorId'] ?? '',
    );
  }
}

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
  final String? geojsonPath; // Path to GeoJSON file in assets
  final String? geojsonFilterField; // Field name to filter regions (e.g., "ADM3_EN")
  final String? geojsonUniqueCodeField;
  final List<SurveyAllocation> allocations;

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
    this.geojsonPath,
    this.geojsonFilterField,
    this.geojsonUniqueCodeField,
    this.allocations = const [],
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
      geojsonPath: json['geojson_path'],
      geojsonFilterField: json['geojson_filter_field'],
      geojsonUniqueCodeField: json['geojson_unique_code_field'],
      allocations: (json['allocations'] as List?)
          ?.map((e) => SurveyAllocation.fromJson(e))
          .toList() ?? [],
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
      'geojson_path': geojsonPath,
      'geojson_filter_field': geojsonFilterField,
      'geojson_unique_code_field': geojsonUniqueCodeField,
    };
  }
}