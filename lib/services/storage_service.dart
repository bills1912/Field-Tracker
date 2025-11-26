import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/user.dart';
import '../models/location_tracking.dart';
import '../models/respondent.dart';
import '../models/message.dart';

class StorageService {
  static StorageService? _instance;
  static StorageService get instance => _instance ??= StorageService._();
  static const String _keyOnboardingCompleted = 'onboarding_completed';

  StorageService._();

  SharedPreferences? _prefs;
  Database? _database;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _database = await _initDatabase();
  }

  Future<Database> _initDatabase() async {
    final databasesPath = await getDatabasesPath();
    final path = join(databasesPath, 'field_tracker.db');

    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        // Pending locations table
        await db.execute('''
          CREATE TABLE pending_locations (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id TEXT NOT NULL,
            latitude REAL NOT NULL,
            longitude REAL NOT NULL,
            timestamp TEXT NOT NULL,
            accuracy REAL,
            battery_level INTEGER,
            created_at TEXT NOT NULL
          )
        ''');

        // Pending respondents table
        await db.execute('''
          CREATE TABLE pending_respondents (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        // Pending messages table
        await db.execute('''
          CREATE TABLE pending_messages (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');

        // Cached FAQs table
        await db.execute('''
          CREATE TABLE cached_faqs (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            cached_at TEXT NOT NULL
          )
        ''');
      },
    );
  }

  // Token Management
  Future<void> saveToken(String token) async {
    await _prefs?.setString('token', token);
  }

  Future<String?> getToken() async {
    return _prefs?.getString('token');
  }

  Future<void> removeToken() async {
    await _prefs?.remove('token');
  }

  /// Check if onboarding is completed
  Future<bool> isOnboardingCompleted() async {
    return _prefs?.getBool(_keyOnboardingCompleted) ?? false;
  }

  /// Set onboarding as completed
  Future<void> setOnboardingCompleted(bool completed) async {
    await _prefs?.setBool(_keyOnboardingCompleted, completed);
    debugPrint('✅ Onboarding status set to: $completed');
  }

  /// Clear onboarding status (for logout)
  Future<void> clearOnboardingStatus() async {
    await _prefs?.remove(_keyOnboardingCompleted);
    debugPrint('✅ Onboarding status cleared');
  }

  // User Management
  Future<void> saveUser(User user) async {
    await _prefs?.setString('user', json.encode(user.toJson()));
  }

  Future<User?> getUser() async {
    final userJson = _prefs?.getString('user');
    if (userJson != null) {
      return User.fromJson(json.decode(userJson));
    }
    return null;
  }

  Future<void> removeUser() async {
    await _prefs?.remove('user');
  }

  // Pending Locations
  Future<void> savePendingLocation(LocationTracking location) async {
    await _database?.insert(
      'pending_locations',
      {
        'user_id': location.userId,
        'latitude': location.latitude,
        'longitude': location.longitude,
        'timestamp': location.timestamp.toIso8601String(),
        'accuracy': location.accuracy,
        'battery_level': location.batteryLevel,
        'created_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<List<LocationTracking>> getPendingLocations() async {
    final List<Map<String, dynamic>> maps = await _database?.query('pending_locations') ?? [];

    return maps.map((map) {
      return LocationTracking(
        userId: map['user_id'],
        latitude: map['latitude'],
        longitude: map['longitude'],
        timestamp: DateTime.parse(map['timestamp']),
        accuracy: map['accuracy'],
        batteryLevel: map['battery_level'],
        isSynced: false,
      );
    }).toList();
  }

  Future<void> clearPendingLocations() async {
    await _database?.delete('pending_locations');
  }

  // Pending Respondents
  Future<void> savePendingRespondent(Respondent respondent) async {
    await _database?.insert(
      'pending_respondents',
      {
        'id': respondent.id,
        'data': json.encode(respondent.toJson()),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Respondent>> getPendingRespondents() async {
    final List<Map<String, dynamic>> maps = await _database?.query('pending_respondents') ?? [];

    return maps.map((map) {
      return Respondent.fromJson(json.decode(map['data']));
    }).toList();
  }

  Future<void> clearPendingRespondents() async {
    await _database?.delete('pending_respondents');
  }

  // Pending Messages
  Future<void> savePendingMessage(Message message) async {
    await _database?.insert(
      'pending_messages',
      {
        'id': message.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        'data': json.encode(message.toJson()),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<Message>> getPendingMessages() async {
    final List<Map<String, dynamic>> maps = await _database?.query('pending_messages') ?? [];

    return maps.map((map) {
      return Message.fromJson(json.decode(map['data']));
    }).toList();
  }

  Future<void> clearPendingMessages() async {
    await _database?.delete('pending_messages');
  }

  // Cached FAQs
  Future<void> cacheFAQs(List<Map<String, dynamic>> faqs) async {
    await _database?.delete('cached_faqs');

    for (var faq in faqs) {
      await _database?.insert('cached_faqs', {
        'id': faq['id'],
        'data': json.encode(faq),
        'cached_at': DateTime.now().toIso8601String(),
      });
    }
  }

  Future<List<Map<String, dynamic>>> getCachedFAQs() async {
    final List<Map<String, dynamic>> maps = await _database?.query('cached_faqs') ?? [];

    return maps.map((map) => json.decode(map['data']) as Map<String, dynamic>).toList();
  }

  // Selected Survey
  Future<void> saveSelectedSurvey(String surveyId, Map<String, dynamic> surveyData) async {
    await _prefs?.setString('selected_survey_id', surveyId);
    await _prefs?.setString('selected_survey_data', json.encode(surveyData));
  }

  Future<String?> getSelectedSurveyId() async {
    return _prefs?.getString('selected_survey_id');
  }

  Future<Map<String, dynamic>?> getSelectedSurveyData() async {
    final data = _prefs?.getString('selected_survey_data');
    if (data != null) {
      return json.decode(data);
    }
    return null;
  }

  Future<void> clearSelectedSurvey() async {
    await _prefs?.remove('selected_survey_id');
    await _prefs?.remove('selected_survey_data');
  }

  // ==================== PINNED SURVEYS ====================

  /// Save pinned survey IDs
  Future<void> savePinnedSurveys(Set<String> surveyIds) async {
    final List<String> idsList = surveyIds.toList();
    await _prefs?.setString('pinned_surveys', json.encode(idsList));
  }

  /// Get pinned survey IDs
  Future<Set<String>> getPinnedSurveys() async {
    final data = _prefs?.getString('pinned_surveys');
    if (data != null) {
      final List<dynamic> idsList = json.decode(data);
      return Set<String>.from(idsList);
    }
    return {};
  }

  /// Add a survey to pinned list
  Future<void> pinSurvey(String surveyId) async {
    final pinnedSurveys = await getPinnedSurveys();
    pinnedSurveys.add(surveyId);
    await savePinnedSurveys(pinnedSurveys);
  }

  /// Remove a survey from pinned list
  Future<void> unpinSurvey(String surveyId) async {
    final pinnedSurveys = await getPinnedSurveys();
    pinnedSurveys.remove(surveyId);
    await savePinnedSurveys(pinnedSurveys);
  }

  /// Check if a survey is pinned
  Future<bool> isSurveyPinned(String surveyId) async {
    final pinnedSurveys = await getPinnedSurveys();
    return pinnedSurveys.contains(surveyId);
  }

  /// Clear all pinned surveys
  Future<void> clearPinnedSurveys() async {
    await _prefs?.remove('pinned_surveys');
  }

  // ========================================================

  // Pending Count
  Future<int> getPendingCount() async {
    final locations = await getPendingLocations();
    final respondents = await getPendingRespondents();
    final messages = await getPendingMessages();

    return locations.length + respondents.length + messages.length;
  }
}