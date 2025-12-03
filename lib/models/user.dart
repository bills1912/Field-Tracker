import 'sensor_data.dart';

class User {
  final String id;
  final String username;
  final String? email;
  final UserRole role;
  final String? supervisorId;
  final DateTime createdAt;
  final DeviceSecurityInfo? lastDeviceInfo;

  User({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    this.supervisorId,
    required this.createdAt,
    this.lastDeviceInfo
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'],
      username: json['username'],
      email: json['email'],
      role: UserRole.values.firstWhere(
        (e) => e.name == json['role'],
        orElse: () => UserRole.enumerator,
      ),
      supervisorId: json['supervisor_id'],
      createdAt: DateTime.parse(json['created_at']),
      lastDeviceInfo: json['last_device_info'] != null
          ? DeviceSecurityInfo.fromJson(json['last_device_info'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'email': email,
      'role': role.name,
      'supervisor_id': supervisorId,
      'created_at': createdAt.toIso8601String(),
      'last_device_info': lastDeviceInfo?.toJson(),
    };
  }
}

enum UserRole { admin, supervisor, enumerator }