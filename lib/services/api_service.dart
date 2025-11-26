// lib/services/api_service.dart
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../models/user.dart';
import '../models/survey.dart';
import '../models/respondent.dart';
import '../models/location_tracking.dart';
import '../models/message.dart';
import '../models/faq.dart';
import '../models/survey_stats.dart';
import 'storage_service.dart';

class ApiService {
  static const String baseUrl = 'https://fieldtrack-15.preview.emergentagent.com/api';

  static ApiService? _instance;
  static ApiService get instance => _instance ??= ApiService._();

  ApiService._();

  Future<Map<String, String>> _getHeaders() async {
    final token = await StorageService.instance.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // ==================== AUTHENTICATION APIs ====================

  /// Login method with extensive debugging
  Future<Map<String, dynamic>> login(String email, String password) async {
    print('\n' + '='*70);
    print('🌐 API SERVICE - LOGIN REQUEST');
    print('='*70);
    print('📍 URL: $baseUrl/auth/login');
    print('📧 Email: $email');
    print('🔑 Password: ${password.replaceAll(RegExp(r'.'), '*')} (${password.length} chars)');

    try {
      print('\n📤 Preparing request...');

      // Prepare request body
      final requestBody = {
        'email': email,
        'password': password,
      };

      print('📦 Request body:');
      print(json.encode(requestBody));

      print('\n🔗 Making HTTP POST request...');
      final startTime = DateTime.now();

      final response = await http.post(
        Uri.parse('$baseUrl/auth/login'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: json.encode(requestBody),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timeout after 30 seconds');
        },
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime);

      print('\n📥 Response received in ${duration.inMilliseconds}ms');
      print('📊 Status Code: ${response.statusCode}');
      print('📋 Headers: ${response.headers}');
      print('📄 Body length: ${response.body.length} bytes');
      print('\n📄 Response Body:');
      print(response.body);
      print('');

      if (response.statusCode == 200 || response.statusCode == 201) {
        print('✅ Success! Parsing response...');

        try {
          final Map<String, dynamic> data = json.decode(response.body);
          print('✓ JSON parsed successfully');
          print('✓ Keys found: ${data.keys.join(", ")}');

          // Check for various success indicators
          if (data.containsKey('success')) {
            print('✓ Has "success" field: ${data['success']}');
          }
          if (data.containsKey('token')) {
            print('✓ Has "token" field: YES (${data['token'].toString().length} chars)');
          }
          if (data.containsKey('access_token')) {
            print('✓ Has "access_token" field: YES');
          }
          if (data.containsKey('user')) {
            print('✓ Has "user" field: YES');
          }
          if (data.containsKey('data')) {
            print('✓ Has "data" field: YES');
          }

          print('='*70);
          print('✅ API LOGIN SUCCESS');
          print('='*70 + '\n');

          return data;

        } catch (e) {
          print('❌ JSON parsing error: $e');
          print('Raw response: ${response.body}');
          throw FormatException('Invalid JSON response from server: $e');
        }

      } else if (response.statusCode == 401) {
        print('❌ Authentication failed (401)');
        final errorBody = json.decode(response.body);
        print('Error response: $errorBody');
        print('='*70 + '\n');

        return {
          'success': false,
          'message': errorBody['message'] ?? 'Email atau password salah',
          'error': 'Unauthorized',
        };

      } else if (response.statusCode == 404) {
        print('❌ Endpoint not found (404)');
        print('='*70 + '\n');
        throw Exception('Login endpoint tidak ditemukan. URL: $baseUrl/auth/login');

      } else if (response.statusCode >= 500) {
        print('❌ Server error (${response.statusCode})');
        print('='*70 + '\n');
        throw Exception('Server error (${response.statusCode}). Coba lagi nanti.');

      } else {
        print('❌ Unexpected status code: ${response.statusCode}');
        print('Response: ${response.body}');
        print('='*70 + '\n');

        try {
          final errorBody = json.decode(response.body);
          throw Exception(errorBody['message'] ?? 'Login failed: ${response.statusCode}');
        } catch (e) {
          throw Exception('Login failed with status ${response.statusCode}');
        }
      }

    } on SocketException catch (e) {
      print('\n💥 SOCKET EXCEPTION');
      print('='*70);
      print('Error: $e');
      print('Kemungkinan:');
      print('1. Tidak ada koneksi internet');
      print('2. Server tidak bisa dijangkau');
      print('3. URL salah: $baseUrl');
      print('='*70 + '\n');
      throw Exception('Tidak ada koneksi internet. Periksa koneksi Anda.');

    } on TimeoutException catch (e) {
      print('\n⏱️ TIMEOUT EXCEPTION');
      print('='*70);
      print('Error: $e');
      print('Request melebihi 30 detik');
      print('='*70 + '\n');
      throw Exception('Request timeout. Koneksi terlalu lambat.');

    } on FormatException catch (e) {
      print('\n📝 FORMAT EXCEPTION');
      print('='*70);
      print('Error: $e');
      print('Response dari server bukan JSON yang valid');
      print('='*70 + '\n');
      rethrow;

    } catch (e, stackTrace) {
      print('\n💥 UNEXPECTED EXCEPTION');
      print('='*70);
      print('Error: $e');
      print('Type: ${e.runtimeType}');
      print('\nStackTrace:');
      print(stackTrace);
      print('='*70 + '\n');
      throw Exception('Login failed: $e');
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    try {
      final response = await http.post(
        Uri.parse('$baseUrl/auth/register'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(userData),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Registration failed');
      }
    } on SocketException {
      throw Exception('No internet connection');
    } on TimeoutException {
      throw Exception('Request timeout');
    } catch (e) {
      throw Exception('Registration failed: $e');
    }
  }

  Future<User> getMe() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/auth/me'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return User.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to get user info: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to get user info: $e');
    }
  }

  // ==================== SURVEY APIs ====================

  Future<List<Survey>> getSurveys() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/surveys'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Survey.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load surveys: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load surveys: $e');
    }
  }

  Future<Survey> getSurvey(String surveyId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/surveys/$surveyId'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return Survey.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load survey: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load survey: $e');
    }
  }

  Future<SurveyStats> getSurveyStats(String surveyId) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/surveys/$surveyId/stats'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return SurveyStats.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load survey stats: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load survey stats: $e');
    }
  }

  Future<Survey> createSurvey(Map<String, dynamic> surveyData) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/surveys'),
        headers: headers,
        body: json.encode(surveyData),
      ).timeout(const Duration(seconds: 30));

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

  // ==================== RESPONDENT APIs ====================

  Future<List<Respondent>> getRespondents({String? surveyId}) async {
    try {
      final headers = await _getHeaders();
      final uri = surveyId != null
          ? Uri.parse('$baseUrl/respondents').replace(queryParameters: {'survey_id': surveyId})
          : Uri.parse('$baseUrl/respondents');

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Respondent.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load respondents: ${response.statusCode}');
      }
    } on SocketException {
      throw Exception('No internet connection');
    } on TimeoutException {
      throw Exception('Request timeout');
    } catch (e) {
      throw Exception('Failed to load respondents: $e');
    }
  }

  Future<Respondent> getRespondent(String id) async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/respondents/$id'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return Respondent.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to load respondent: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load respondent: $e');
    }
  }

  Future<Respondent> createRespondent(Map<String, dynamic> data) async {
    try {
      print('📤 Creating respondent...');
      print('📦 Data: ${json.encode(data)}');

      if (data['name'] == null || (data['name'] as String).trim().isEmpty) {
        throw Exception('Name is required');
      }
      if (data['latitude'] == null || data['longitude'] == null) {
        throw Exception('Location coordinates are required');
      }
      if (data['survey_id'] == null) {
        throw Exception('Survey ID is required');
      }

      final headers = await _getHeaders();
      print('🔑 Headers: $headers');

      final response = await http.post(
        Uri.parse('$baseUrl/respondents'),
        headers: headers,
        body: json.encode(data),
      ).timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          throw TimeoutException('Request timed out after 30 seconds');
        },
      );

      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        print('✅ Respondent created successfully');
        return Respondent.fromJson(responseData);
      } else {
        String errorMessage = 'Failed to create respondent';
        try {
          final errorBody = json.decode(response.body);
          errorMessage = errorBody['message'] ?? errorBody['error'] ?? errorMessage;
        } catch (e) {
          errorMessage = 'Server error: ${response.statusCode}';
        }
        print('❌ Error: $errorMessage');
        throw Exception(errorMessage);
      }
    } on SocketException catch (e) {
      print('❌ No internet connection: $e');
      throw Exception('No internet connection. Data will be saved locally and synced later.');
    } on TimeoutException catch (e) {
      print('❌ Request timeout: $e');
      throw Exception('Request timeout. Please check your connection and try again.');
    } on FormatException catch (e) {
      print('❌ Invalid response format: $e');
      throw Exception('Invalid response from server');
    } catch (e) {
      print('❌ Unexpected error: $e');
      throw Exception('Failed to create respondent: $e');
    }
  }

  Future<Respondent> updateRespondent(String id, Map<String, dynamic> data) async {
    try {
      print('📤 Updating respondent: $id');
      print('📦 Data: ${json.encode(data)}');

      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/respondents/$id'),
        headers: headers,
        body: json.encode(data),
      ).timeout(const Duration(seconds: 30));

      print('📥 Response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        print('✅ Respondent updated successfully');
        return Respondent.fromJson(json.decode(response.body));
      } else {
        final errorBody = json.decode(response.body);
        throw Exception(errorBody['message'] ?? 'Failed to update respondent');
      }
    } on SocketException {
      throw Exception('No internet connection');
    } on TimeoutException {
      throw Exception('Request timeout');
    } catch (e) {
      throw Exception('Failed to update respondent: $e');
    }
  }

  // ==================== LOCATION APIs ====================

  Future<LocationTracking> createLocation(LocationTracking location) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/locations'),
        headers: headers,
        body: json.encode(location.toJson()),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200 || response.statusCode == 201) {
        return LocationTracking.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create location: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to create location: $e');
    }
  }

  Future<void> createLocationsBatch(List<LocationTracking> locations) async {
    try {
      final headers = await _getHeaders();
      final response = await http.post(
        Uri.parse('$baseUrl/locations/batch'),
        headers: headers,
        body: json.encode({
          'locations': locations.map((loc) => loc.toJson()).toList(),
        }),
      ).timeout(const Duration(seconds: 45));

      if (response.statusCode != 200) {
        throw Exception('Failed to create locations batch: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to create locations batch: $e');
    }
  }

  Future<List<LocationTracking>> getLocations({String? userId}) async {
    try {
      final headers = await _getHeaders();
      final uri = userId != null
          ? Uri.parse('$baseUrl/locations').replace(queryParameters: {'user_id': userId})
          : Uri.parse('$baseUrl/locations');

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => LocationTracking.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load locations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load locations: $e');
    }
  }

  Future<List<LocationTracking>> getLatestLocations() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/locations/latest'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => LocationTracking.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load latest locations: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load latest locations: $e');
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
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return Message.fromJson(json.decode(response.body));
      } else {
        throw Exception('Failed to create message: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to create message: $e');
    }
  }

  Future<List<Message>> getMessages({String? messageType}) async {
    try {
      final headers = await _getHeaders();
      final uri = messageType != null
          ? Uri.parse('$baseUrl/messages').replace(queryParameters: {'message_type': messageType})
          : Uri.parse('$baseUrl/messages');

      final response = await http.get(uri, headers: headers).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => Message.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load messages: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load messages: $e');
    }
  }

  Future<Message> respondToMessage(String messageId, String responseText) async {
    try {
      final headers = await _getHeaders();
      final response = await http.put(
        Uri.parse('$baseUrl/messages/$messageId/respond'),
        headers: headers,
        body: json.encode({'response': responseText}),
      ).timeout(const Duration(seconds: 30));

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
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final List<dynamic> data = json.decode(response.body);
        return data.map((json) => FAQ.fromJson(json)).toList();
      } else {
        throw Exception('Failed to load FAQs: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load FAQs: $e');
    }
  }

  // ==================== DASHBOARD APIs ====================

  Future<Map<String, dynamic>> getDashboardStats() async {
    try {
      final headers = await _getHeaders();
      final response = await http.get(
        Uri.parse('$baseUrl/dashboard/stats'),
        headers: headers,
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        return json.decode(response.body);
      } else {
        throw Exception('Failed to load dashboard stats: ${response.statusCode}');
      }
    } catch (e) {
      throw Exception('Failed to load dashboard stats: $e');
    }
  }
}