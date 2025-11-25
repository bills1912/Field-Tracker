class LocationTracking {
  final String? id;
  final String userId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? accuracy;
  final int? batteryLevel;
  final bool isSynced;

  LocationTracking({
    this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.accuracy,
    this.batteryLevel,
    this.isSynced = false,
  });

  factory LocationTracking.fromJson(Map<String, dynamic> json) {
    return LocationTracking(
      id: json['id'],
      userId: json['user_id'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      timestamp: DateTime.parse(json['timestamp']),
      accuracy: json['accuracy']?.toDouble(),
      batteryLevel: json['battery_level'],
      isSynced: json['is_synced'] ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      if (id != null) 'id': id,
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'accuracy': accuracy,
      'battery_level': batteryLevel,
      'is_synced': isSynced,
    };
  }
}