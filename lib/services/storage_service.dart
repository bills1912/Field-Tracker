import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/user.dart';
import '../models/location_tracking.dart';
import '../models/respondent.dart';
import '../models/message.dart';
import '../models/survey.dart';
import '../models/survey_stats.dart';

/// Storage Service dengan dukungan offline yang lebih baik
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
      version: 2, // UPDATED: version untuk migrasi
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

        // NEW: Cached surveys table (untuk offline)
        await db.execute('''
          CREATE TABLE cached_surveys (
            id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            cached_at TEXT NOT NULL
          )
        ''');

        // NEW: Cached respondents table (untuk offline)
        await db.execute('''
          CREATE TABLE cached_respondents (
            id TEXT PRIMARY KEY,
            survey_id TEXT NOT NULL,
            data TEXT NOT NULL,
            cached_at TEXT NOT NULL
          )
        ''');

        // NEW: Cached survey stats table (untuk offline)
        await db.execute('''
          CREATE TABLE cached_survey_stats (
            survey_id TEXT PRIMARY KEY,
            data TEXT NOT NULL,
            cached_at TEXT NOT NULL
          )
        ''');

        // Create indexes for better performance
        await db.execute('CREATE INDEX idx_pending_locations_user ON pending_locations(user_id)');
        await db.execute('CREATE INDEX idx_cached_respondents_survey ON cached_respondents(survey_id)');
      },
      onUpgrade: (Database db, int oldVersion, int newVersion) async {
        if (oldVersion < 2) {
          // Migration dari version 1 ke 2
          await db.execute('''
            CREATE TABLE IF NOT EXISTS cached_surveys (
              id TEXT PRIMARY KEY,
              data TEXT NOT NULL,
              cached_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS cached_respondents (
              id TEXT PRIMARY KEY,
              survey_id TEXT NOT NULL,
              data TEXT NOT NULL,
              cached_at TEXT NOT NULL
            )
          ''');

          await db.execute('''
            CREATE TABLE IF NOT EXISTS cached_survey_stats (
              survey_id TEXT PRIMARY KEY,
              data TEXT NOT NULL,
              cached_at TEXT NOT NULL
            )
          ''');

          await db.execute('CREATE INDEX IF NOT EXISTS idx_pending_locations_user ON pending_locations(user_id)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_cached_respondents_survey ON cached_respondents(survey_id)');
        }
      },
    );
  }

  // ==================== TOKEN MANAGEMENT ====================

  Future<void> saveToken(String token) async {
    await _prefs?.setString('token', token);
  }

  Future<String?> getToken() async {
    return _prefs?.getString('token');
  }

  Future<void> removeToken() async {
    await _prefs?.remove('token');
  }

  // ==================== ONBOARDING ====================

  Future<bool> isOnboardingCompleted() async {
    return _prefs?.getBool(_keyOnboardingCompleted) ?? false;
  }

  Future<void> setOnboardingCompleted(bool completed) async {
    await _prefs?.setBool(_keyOnboardingCompleted, completed);
    debugPrint('✅ Onboarding status set to: $completed');
  }

  Future<void> clearOnboardingStatus() async {
    await _prefs?.remove(_keyOnboardingCompleted);
    debugPrint('✅ Onboarding status cleared');
  }

  // ==================== USER MANAGEMENT ====================

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

  // ==================== PENDING LOCATIONS (OFFLINE) ====================

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
    debugPrint('💾 Pending location saved');
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

  Future<int> getPendingLocationsCount() async {
    final result = await _database?.rawQuery('SELECT COUNT(*) as count FROM pending_locations');
    return result?.first['count'] as int? ?? 0;
  }

  Future<void> clearPendingLocations() async {
    await _database?.delete('pending_locations');
    debugPrint('✅ Pending locations cleared');
  }

  Future<void> deletePendingLocations(List<int> ids) async {
    if (ids.isEmpty) return;
    await _database?.delete(
      'pending_locations',
      where: 'id IN (${ids.join(',')})',
    );
  }

  // ==================== CACHED SURVEYS (OFFLINE) ====================

  Future<void> cacheSurveys(List<Survey> surveys) async {
    // Clear old cache first
    await _database?.delete('cached_surveys');

    for (var survey in surveys) {
      await _database?.insert(
        'cached_surveys',
        {
          'id': survey.id,
          'data': json.encode(survey.toJson()),
          'cached_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('💾 Cached ${surveys.length} surveys');
  }

  Future<List<Survey>> getCachedSurveys() async {
    final List<Map<String, dynamic>> maps = await _database?.query('cached_surveys') ?? [];

    return maps.map((map) {
      return Survey.fromJson(json.decode(map['data']));
    }).toList();
  }

  Future<Survey?> getCachedSurvey(String surveyId) async {
    final List<Map<String, dynamic>> maps = await _database?.query(
      'cached_surveys',
      where: 'id = ?',
      whereArgs: [surveyId],
    ) ?? [];

    if (maps.isEmpty) return null;
    return Survey.fromJson(json.decode(maps.first['data']));
  }

  // ==================== CACHED RESPONDENTS (OFFLINE) ====================

  Future<void> cacheRespondents(String surveyId, List<Respondent> respondents) async {
    // Clear old cache for this survey
    await _database?.delete(
      'cached_respondents',
      where: 'survey_id = ?',
      whereArgs: [surveyId],
    );

    for (var respondent in respondents) {
      await _database?.insert(
        'cached_respondents',
        {
          'id': respondent.id,
          'survey_id': surveyId,
          'data': json.encode(respondent.toJson()),
          'cached_at': DateTime.now().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    debugPrint('💾 Cached ${respondents.length} respondents for survey $surveyId');
  }

  Future<List<Respondent>> getCachedRespondents({String? surveyId}) async {
    List<Map<String, dynamic>> maps;

    if (surveyId != null) {
      maps = await _database?.query(
        'cached_respondents',
        where: 'survey_id = ?',
        whereArgs: [surveyId],
      ) ?? [];
    } else {
      maps = await _database?.query('cached_respondents') ?? [];
    }

    return maps.map((map) {
      return Respondent.fromJson(json.decode(map['data']));
    }).toList();
  }

  // ==================== CACHED SURVEY STATS (OFFLINE) ====================

  Future<void> cacheSurveyStats(String surveyId, SurveyStats stats) async {
    await _database?.insert(
      'cached_survey_stats',
      {
        'survey_id': surveyId,
        'data': json.encode({
          'survey_id': stats.surveyId,
          'total_respondents': stats.totalRespondents,
          'pending': stats.pending,
          'in_progress': stats.inProgress,
          'completed': stats.completed,
          'completion_rate': stats.completionRate,
        }),
        'cached_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    debugPrint('💾 Cached stats for survey $surveyId');
  }

  Future<SurveyStats?> getCachedSurveyStats(String surveyId) async {
    final List<Map<String, dynamic>> maps = await _database?.query(
      'cached_survey_stats',
      where: 'survey_id = ?',
      whereArgs: [surveyId],
    ) ?? [];

    if (maps.isEmpty) return null;
    return SurveyStats.fromJson(json.decode(maps.first['data']));
  }

  // ==================== PENDING RESPONDENTS ====================

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
    debugPrint('💾 Pending respondent saved: ${respondent.id}');
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

  Future<void> deletePendingRespondent(String id) async {
    await _database?.delete(
      'pending_respondents',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // ==================== PENDING MESSAGES ====================

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

  // ==================== CACHED FAQs ====================

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

  // ==================== SELECTED SURVEY ====================

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

  Future<void> savePinnedSurveys(Set<String> surveyIds) async {
    final List<String> idsList = surveyIds.toList();
    await _prefs?.setString('pinned_surveys', json.encode(idsList));
  }

  Future<Set<String>> getPinnedSurveys() async {
    final data = _prefs?.getString('pinned_surveys');
    if (data != null) {
      final List<dynamic> idsList = json.decode(data);
      return Set<String>.from(idsList);
    }
    return {};
  }

  Future<void> pinSurvey(String surveyId) async {
    final pinnedSurveys = await getPinnedSurveys();
    pinnedSurveys.add(surveyId);
    await savePinnedSurveys(pinnedSurveys);
  }

  Future<void> unpinSurvey(String surveyId) async {
    final pinnedSurveys = await getPinnedSurveys();
    pinnedSurveys.remove(surveyId);
    await savePinnedSurveys(pinnedSurveys);
  }

  Future<bool> isSurveyPinned(String surveyId) async {
    final pinnedSurveys = await getPinnedSurveys();
    return pinnedSurveys.contains(surveyId);
  }

  Future<void> clearPinnedSurveys() async {
    await _prefs?.remove('pinned_surveys');
  }

  // ==================== PENDING COUNT ====================

  Future<int> getPendingCount() async {
    final locations = await getPendingLocations();
    final respondents = await getPendingRespondents();
    final messages = await getPendingMessages();

    return locations.length + respondents.length + messages.length;
  }

  // ==================== CACHE MANAGEMENT ====================

  /// Clear all cached data (untuk refresh)
  Future<void> clearAllCache() async {
    await _database?.delete('cached_surveys');
    await _database?.delete('cached_respondents');
    await _database?.delete('cached_survey_stats');
    await _database?.delete('cached_faqs');
    debugPrint('✅ All cache cleared');
  }

  /// Get cache age
  Future<DateTime?> getCacheAge(String table) async {
    final result = await _database?.rawQuery(
      'SELECT MIN(cached_at) as oldest FROM $table',
    );
    if (result?.isNotEmpty == true && result!.first['oldest'] != null) {
      return DateTime.parse(result.first['oldest'] as String);
    }
    return null;
  }

  /// Check if cache is stale (older than specified duration)
  Future<bool> isCacheStale(String table, Duration maxAge) async {
    final cacheAge = await getCacheAge(table);
    if (cacheAge == null) return true;
    return DateTime.now().difference(cacheAge) > maxAge;
  }
}