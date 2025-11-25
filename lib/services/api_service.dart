// lib/services/api_service.dart
import 'dart:convert';
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
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  // Authentication APIs
  Future<Map<String, dynamic>> login(String email, String password) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Login failed: ${response.body}');
    }
  }

  Future<Map<String, dynamic>> register(Map<String, dynamic> userData) async {
    final response = await http.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: json.encode(userData),
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Registration failed: ${response.body}');
    }
  }

  Future<User> getMe() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return User.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to get user info');
    }
  }

  // Survey APIs
  Future<List<Survey>> getSurveys() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/surveys'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Survey.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load surveys');
    }
  }

  Future<Survey> getSurvey(String surveyId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/surveys/$surveyId'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return Survey.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load survey');
    }
  }

  Future<SurveyStats> getSurveyStats(String surveyId) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/surveys/$surveyId/stats'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return SurveyStats.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load survey stats');
    }
  }

  Future<Survey> createSurvey(Map<String, dynamic> surveyData) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/surveys'),
      headers: headers,
      body: json.encode(surveyData),
    );

    if (response.statusCode == 200) {
      return Survey.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create survey');
    }
  }

  // Respondent APIs
  Future<List<Respondent>> getRespondents({String? surveyId}) async {
    final headers = await _getHeaders();
    final uri = surveyId != null
        ? Uri.parse('$baseUrl/respondents').replace(queryParameters: {'survey_id': surveyId})
        : Uri.parse('$baseUrl/respondents');
        
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Respondent.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load respondents');
    }
  }

  Future<Respondent> getRespondent(String id) async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/respondents/$id'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return Respondent.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to load respondent');
    }
  }

  Future<Respondent> createRespondent(Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/respondents'),
      headers: headers,
      body: json.encode(data),
    );

    if (response.statusCode == 200) {
      return Respondent.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create respondent');
    }
  }

  Future<Respondent> updateRespondent(String id, Map<String, dynamic> data) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/respondents/$id'),
      headers: headers,
      body: json.encode(data),
    );

    if (response.statusCode == 200) {
      return Respondent.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to update respondent');
    }
  }

  // Location APIs
  Future<LocationTracking> createLocation(LocationTracking location) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/locations'),
      headers: headers,
      body: json.encode(location.toJson()),
    );

    if (response.statusCode == 200) {
      return LocationTracking.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create location');
    }
  }

  Future<void> createLocationsBatch(List<LocationTracking> locations) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/locations/batch'),
      headers: headers,
      body: json.encode({
        'locations': locations.map((loc) => loc.toJson()).toList(),
      }),
    );

    if (response.statusCode != 200) {
      throw Exception('Failed to create locations batch');
    }
  }

  Future<List<LocationTracking>> getLocations({String? userId}) async {
    final headers = await _getHeaders();
    final uri = userId != null
        ? Uri.parse('$baseUrl/locations').replace(queryParameters: {'user_id': userId})
        : Uri.parse('$baseUrl/locations');
        
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => LocationTracking.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load locations');
    }
  }

  Future<List<LocationTracking>> getLatestLocations() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/locations/latest'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => LocationTracking.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load latest locations');
    }
  }

  // Message APIs
  Future<Message> createMessage(Message message) async {
    final headers = await _getHeaders();
    final response = await http.post(
      Uri.parse('$baseUrl/messages'),
      headers: headers,
      body: json.encode(message.toJson()),
    );

    if (response.statusCode == 200) {
      return Message.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to create message');
    }
  }

  Future<List<Message>> getMessages({String? messageType}) async {
    final headers = await _getHeaders();
    final uri = messageType != null
        ? Uri.parse('$baseUrl/messages').replace(queryParameters: {'message_type': messageType})
        : Uri.parse('$baseUrl/messages');
        
    final response = await http.get(uri, headers: headers);

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => Message.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load messages');
    }
  }

  Future<Message> respondToMessage(String messageId, String responseText) async {
    final headers = await _getHeaders();
    final response = await http.put(
      Uri.parse('$baseUrl/messages/$messageId/respond'),
      headers: headers,
      body: json.encode({'response': responseText}),
    );

    if (response.statusCode == 200) {
      return Message.fromJson(json.decode(response.body));
    } else {
      throw Exception('Failed to respond to message');
    }
  }

  // FAQ APIs
  Future<List<FAQ>> getFAQs() async {
    final response = await http.get(
      Uri.parse('$baseUrl/faqs'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((json) => FAQ.fromJson(json)).toList();
    } else {
      throw Exception('Failed to load FAQs');
    }
  }

  // Dashboard APIs
  Future<Map<String, dynamic>> getDashboardStats() async {
    final headers = await _getHeaders();
    final response = await http.get(
      Uri.parse('$baseUrl/dashboard/stats'),
      headers: headers,
    );

    if (response.statusCode == 200) {
      return json.decode(response.body);
    } else {
      throw Exception('Failed to load dashboard stats');
    }
  }
}