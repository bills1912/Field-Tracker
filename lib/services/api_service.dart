// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../models/survey.dart';
import '../models/respondent.dart';
import '../models/location_tracking.dart';
import '../models/message.dart';
import '../models/faq.dart';
import '../models/survey_stats.dart';
import 'storage_service.dart';
import 'sensor_collector_service.dart';
import '../models/sensor_data.dart';
import '../main.dart';
import '../screens/auth/onboarding_screen.dart';

/// API Service dengan dukungan offline-first
class ApiService {
  static const String baseUrl = 'https://survey-enum-tracker-1.onrender.com/api';

  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();

  ApiService._();

  // Timeout settings
  static const Duration _defaultTimeout = Duration(seconds: 30);
  static const Duration _shortTimeout = Duration(seconds: 10);

  void _handleAuthError(http.Response response) {
    if (response.statusCode == 401) {
      final body = json.decode(response.body);

      // Jika pesan errornya spesifik tentang device lain
      if (body['detail'].toString().contains('logged in on another device') ||
          body['detail'].toString().contains('Session expired')) {

        debugPrint('⛔ Session Expired: Logged in elsewhere. Forcing logout...');

        // Bersihkan data lokal
        StorageService.instance.removeToken();
        StorageService.instance.removeUser();
        StorageService.instance.clearOnboardingStatus();

        // Paksa pindah ke halaman Login
        navigatorKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    }
  }

  Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.instance.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  /// Check if we have network connectivity
  Future<bool> hasConnectivity() async {
    try {
      final result = await InternetAddress.lookup('google.com')
          .timeout(const Duration(seconds: 5));
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  // ==================== AUTHENTICATION APIs ====================

  Future<Map<String, dynamic>> login(String email, String password) async {
    debugPrint('\n' + '='*70);
    debugPrint('🌐 API SERVICE - LOGIN REQUEST');

    Map<String, dynamic>? deviceInfoData;
    try {
      final securityInfo = await SensorCollectorService.instance.getDeviceSecurityInfo();
      // Ubah nama key agar sesuai dengan snake_case yang diharapkan backend Python
      deviceInfoData = securityInfo.toJson();
      debugPrint('📱 Device Info collected: ${securityInfo.deviceModel}');
    } catch (e) {
      debugPrint('⚠️ Gagal mengambil info device: $e');
    }

    debugPrint('='*70);
    debugPrint('📍 URL: $baseUrl/auth/login');
    debugPrint('📧 Email: $email');

    try {
      final requestBody = {
        'email': email,
        'password': password,
        if (deviceInfoData != null) 'device_info': deviceInfoData,
      };

      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      ).timeout(_defaultTimeout);

      debugPrint('📥 Status Code: ${response.statusCode}');

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final Map<String, dynamic> data = json.decode(response.body);

        // Save user data for offline access
        if (data['user'] != null) {
          final user = User.fromJson(data['user']);
          await StorageService.instance.saveUser(user);
        }

        return data;
      } else if (response.statusCode == 401) {
        final errorBody = json.decode(response.body);
        return {
          'success': false,
          'message': errorBody['message'] ?? 'Email atau password salah',
        };
      } else {
        throw Exception('Login failed: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('Tidak ada koneksi internet. Periksa koneksi Anda.');
    } on TimeoutException {
      throw Exception('Request timeout. Koneksi terlalu lambat.');
    } catch (e) {
      throw Exception('Login failed: $e');
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(userData),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Registration failed');
      }
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<void> syncDeviceInfo() async {
    try {
      // 1. Ambil data sensor terbaru
      final securityInfo = await SensorCollectorService.instance.getDeviceSecurityInfo();
      final deviceInfoJson = securityInfo.toJson();

      // 2. Kirim ke endpoint baru
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/auth/device-sync'),
        headers: headers,
        body: json.encode(deviceInfoJson),
      ).timeout(_shortTimeout); // Timeout pendek agar tidak memblokir UI

      if (response.statusCode == 200) {
        debugPrint('✅ Device Info Updated: ${securityInfo.deviceModel}');
      } else {
        debugPrint('⚠️ Device Sync Failed: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Failed to sync device info on auto-login: $e');
      // Jangan throw exception, karena ini proses background
    }
  }

  Future<User> getMe() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: headers,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final user = User.fromJson(json.decode(response.body));
        await StorageService.instance.saveUser(user);
        syncDeviceInfo();
        return user;
      } else {
        throw Exception('Failed to get user info: ${response.statusCode}');
      }
    } catch (e) {
      // Try to get cached user
      final cachedUser = await StorageService.instance.getUser();
      if (cachedUser != null) {
        debugPrint('📱 Using cached user data');
        return cachedUser;
      }
      throw Exception('Failed to get user info: $e');
    }
  }

  // ==================== SURVEY APIs (OFFLINE SUPPORTED) ====================

  /// Get surveys with offline support
  Future<List<Survey>> getSurveys() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/surveys'),
        headers: headers,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final surveys = data.map((json) => Survey.fromJson(json)).toList();

        // Cache surveys for offline use
        await StorageService.instance.cacheSurveys(surveys);
        debugPrint('✅ Loaded ${surveys.length} surveys from API and cached');

        return surveys;
      } else {
        throw Exception('Failed to load surveys: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ API error, trying cache: $e');

      // OFFLINE FALLBACK: Return cached surveys
      final cachedSurveys = await StorageService.instance.getCachedSurveys();
      if (cachedSurveys.isNotEmpty) {
        debugPrint('📱 Using ${cachedSurveys.length} cached surveys');
        return cachedSurveys;
      }

      throw Exception('Failed to load surveys: $e');
    }
  }

  Future<Survey> getSurvey(String surveyId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/surveys/$surveyId'),
        headers: headers,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return Survey.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load survey: ${response.statusCode}');
      }
    } catch (e) {
      // OFFLINE FALLBACK
      final cachedSurvey = await StorageService.instance.getCachedSurvey(surveyId);
      if (cachedSurvey != null) {
        debugPrint('📱 Using cached survey');
        return cachedSurvey;
      }
      throw Exception('Failed to load survey: $e');
    }
  }

  /// Get survey stats with offline support
  Future<SurveyStats> getSurveyStats(String surveyId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/surveys/$surveyId/stats'),
        headers: headers,
      ).timeout(_shortTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final stats = SurveyStats.fromJson(json.decode(response.body));

        // Cache stats for offline use
        await StorageService.instance.cacheSurveyStats(surveyId, stats);

        return stats;
      } else {
        throw Exception('Failed to load survey stats: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ API error for stats, trying cache: $e');

      // OFFLINE FALLBACK
      final cachedStats = await StorageService.instance.getCachedSurveyStats(surveyId);
      if (cachedStats != null) {
        debugPrint('📱 Using cached stats');
        return cachedStats;
      }

      // Return empty stats if no cache
      return SurveyStats(
        surveyId: surveyId,
        totalRespondents: 0,
        pending: 0,
        inProgress: 0,
        completed: 0,
        completionRate: 0,
      );
    }
  }

  Future<Survey> createSurvey(Map<String, dynamic> surveyData) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/surveys'),
        headers: headers,
        body: json.encode(surveyData),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return Survey.fromJson(json.decode(response.body));
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to create survey');
      }
    } catch (e) {
      throw Exception('Failed to create survey: $e');
    }
  }

  // ==================== RESPONDENT APIs (OFFLINE SUPPORTED) ====================

  /// Get respondents with offline support
  Future<List<Respondent>> getRespondents({String? surveyId}) async {
    try {
      final headers = await _getHeaders();
      final uri = surveyId != null
          ? Uri.parse('$baseUrl/respondents').replace(queryParameters: {'survey_id': surveyId})
          : Uri.parse('$baseUrl/respondents');

      final response = await http.get(uri, headers: headers).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final respondents = data.map((json) => Respondent.fromJson(json)).toList();

        // Cache respondents for offline use
        if (surveyId != null) {
          await StorageService.instance.cacheRespondents(surveyId, respondents);
        }
        debugPrint('✅ Loaded ${respondents.length} respondents from API');

        return respondents;
      } else {
        throw Exception('Failed to load respondents: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ API error for respondents, trying cache: $e');

      // OFFLINE FALLBACK
      final cachedRespondents = await StorageService.instance.getCachedRespondents(surveyId: surveyId);
      if (cachedRespondents.isNotEmpty) {
        debugPrint('📱 Using ${cachedRespondents.length} cached respondents');
        return cachedRespondents;
      }

      // Also include pending (locally created) respondents
      final pendingRespondents = await StorageService.instance.getPendingRespondents();
      if (pendingRespondents.isNotEmpty) {
        debugPrint('📱 Including ${pendingRespondents.length} pending respondents');
        return pendingRespondents;
      }

      return []; // Return empty list instead of throwing
    }
  }

  Future<Respondent> getRespondent(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/respondents/$id'),
        headers: headers,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return Respondent.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load respondent: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load respondent: $e');
    }
  }

  /// Create respondent with offline support
  Future<Respondent> createRespondent(Map<String, dynamic> data) async {
    debugPrint('📤 Creating respondent...');

    if (data['latitude'] == null && data['location'] != null) {
      if (data['location'] is Map) {
        data['latitude'] = data['location']['latitude'];
        data['longitude'] = data['location']['longitude'];
      }
    }

    if (data['phone'] == null || data['phone'].toString().isEmpty) data['phone'] = "-";
    if (data['address'] == null || data['address'].toString().isEmpty) data['address'] = "-";
    if (data['region_code'] == null || data['region_code'].toString().isEmpty) data['region_code'] = "UNKNOWN";

    // Validate required fields
    if (data['name'] == null || (data['name'] as String).trim().isEmpty) {
      throw Exception('Name is required');
    }
    if (data['latitude'] == null || data['longitude'] == null) {
      throw Exception('Location coordinates are required');
    }
    if (data['survey_id'] == null) {
      throw Exception('Survey ID is required');
    }

    // Parsing aman untuk koordinat (handle String atau Number)
    final double lat = (data['latitude'] is String)
        ? double.parse(data['latitude'])
        : (data['latitude'] as num).toDouble();

    final double lng = (data['longitude'] is String)
        ? double.parse(data['longitude'])
        : (data['longitude'] as num).toDouble();

    // Create a temporary respondent object
    final tempId = 'temp_${DateTime.now().millisecondsSinceEpoch}';
    final respondent = Respondent(
      id: tempId,
      name: data['name'],
      phone: data['phone'],
      address: data['address'],
      latitude: lat,
      longitude: lng,
      status: RespondentStatus.pending,
      surveyId: data['survey_id'],
      enumeratorId: data['enumerator_id'],
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
      region_code: data['region_code'],
    );

    try {
      final headers = await _getHeaders();

      if (data['location'] == null) {
        data['location'] = {
          'latitude': lat,
          'longitude': lng,
        };
      }

      final response = await http.post(
        Uri.parse('$baseUrl/respondents'),
        headers: headers,
        body: json.encode(data),
      ).timeout(_shortTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        debugPrint('✅ Respondent created on server');
        return Respondent.fromJson(responseData);
      } else {
        throw Exception('Server error: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ API failed, saving locally: $e');

      // OFFLINE FALLBACK: Save locally
      await StorageService.instance.savePendingRespondent(respondent);
      debugPrint('💾 Respondent saved locally for later sync');

      // Return the local respondent
      return respondent;
    }
  }

  Future<Respondent> updateRespondent(String id, Map<String, dynamic> data) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/respondents/$id'),
        headers: headers,
        body: json.encode(data),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return Respondent.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to update respondent');
      }
    } catch (e) {
      debugPrint('⚠️ Update failed, will sync later: $e');
      throw Exception('Failed to update respondent: $e');
    }
  }

  // ==================== LOCATION APIs (OFFLINE FIRST) ====================

  /// Create location - always saves locally first, then tries API
  Future<LocationTracking> createLocation(LocationTracking location) async {
    // Always save locally first
    await StorageService.instance.savePendingLocation(location);

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/locations'),
        headers: headers,
        body: json.encode(location.toJson()),
      ).timeout(_shortTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200 || response.statusCode == 201) {
        debugPrint('✅ Location synced to server');
        return LocationTracking.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create location: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Location will sync later: $e');
      // Return the local location - it's already saved
      return location;
    }
  }

  Future<void> createLocationsBatch(List<LocationTracking> locations) async {
    if (locations.isEmpty) return;

    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/locations/batch'),
        headers: headers,
        body: json.encode({
          'locations': locations.map((loc) => loc.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        debugPrint('✅ Batch of ${locations.length} locations synced');
      } else {
        throw Exception('Failed to create locations batch: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('⚠️ Batch sync failed: $e');
      throw Exception('Failed to create locations batch: $e');
    }
  }

  Future<List<LocationTracking>> getLocations({String? userId}) async {
    try {
      final headers = await _getHeaders();
      final uri = userId != null
          ? Uri.parse('$baseUrl/locations').replace(queryParameters: {'user_id': userId})
          : Uri.parse('$baseUrl/locations');

      final response = await http.get(uri, headers: headers).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => LocationTracking.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load locations: ${response.statusCode}');
      }
    } catch (e) {
      // Return pending locations if API fails
      return await StorageService.instance.getPendingLocations();
    }
  }

  Future<List<LocationTracking>> getLatestLocations() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/locations/latest'),
        headers: headers,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => LocationTracking.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load latest locations: ${response.statusCode}');
      }
    } catch (e) {
      return await StorageService.instance.getPendingLocations();
    }
  }

  // ==================== MESSAGE APIs ====================

  Future<Message> createMessage(Message message) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/messages'),
        headers: headers,
        body: json.encode(message.toJson()),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return Message.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create message: ${response.statusCode}');
      }
    } catch (e) {
      // Save locally for offline
      await StorageService.instance.savePendingMessage(message);
      throw Exception('Failed to create message: $e');
    }
  }

  Future<List<Message>> getMessages({String? messageType}) async {
    try {
      final headers = await _getHeaders();
      final uri = messageType != null
          ? Uri.parse('$baseUrl/messages').replace(queryParameters: {'message_type': messageType})
          : Uri.parse('$baseUrl/messages');

      final response = await http.get(uri, headers: headers).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      // Return pending messages if offline
      return await StorageService.instance.getPendingMessages();
    }
  }

  Future<Message> respondToMessage(String messageId, String responseText) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/messages/$messageId/respond'),
        headers: headers,
        body: json.encode({'response': responseText}),
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return Message.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to respond to message: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to respond to message: $e');
    }
  }

  // ==================== FAQ APIs ====================

  Future<List<FAQ>> getFAQs() async {
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/faqs'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        final faqs = data.map((json) => FAQ.fromJson(json)).toList();

        // Cache FAQs
        await StorageService.instance.cacheFAQs(
          data.map((d) => d as Map<String, dynamic>).toList(),
        );

        return faqs;
      } else {
        throw Exception('Failed to load FAQs: ${response.statusCode}');
      }
    } catch (e) {
      // Return cached FAQs
      final cached = await StorageService.instance.getCachedFAQs();
      if (cached.isNotEmpty) {
        return cached.map((json) => FAQ.fromJson(json)).toList();
      }
      return [];
    }
  }

  // ==================== DASHBOARD APIs ====================

  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/dashboard/stats'),
        headers: headers,
      ).timeout(_defaultTimeout);

      if (response.statusCode == 401) {
        _handleAuthError(response);
        throw Exception('Session expired');
      }

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load dashboard stats: ${response.statusCode}');
      }
    } catch (e) {
      // Return empty stats for offline
      return {
        'total_surveys': 0,
        'total_respondents': 0,
        'pending': 0,
        'completed': 0,
      };
    }
  }
}