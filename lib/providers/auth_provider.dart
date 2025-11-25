import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _user != null;

  AuthProvider() {
    _loadUserFromStorage();
  }

  Future<void> _loadUserFromStorage() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');

      if (_token != null) {
        final userId = prefs.getString('user_id');
        final username = prefs.getString('username');
        final email = prefs.getString('email');
        final roleStr = prefs.getString('role');

        if (userId != null && username != null) {
          _user = User(
            id: userId,
            username: username,
            email: email,
            role: _parseUserRole(roleStr),
            createdAt: DateTime.now(), // Default value since we don't store it
          );
          notifyListeners();
        }
      }
    } catch (e) {
      print('Error loading user from storage: $e');
    }
  }

  UserRole _parseUserRole(String? roleStr) {
    switch (roleStr?.toLowerCase()) {
      case 'admin':
        return UserRole.admin;
      case 'supervisor':
        return UserRole.supervisor;
      case 'enumerator':
        return UserRole.enumerator;
      default:
        return UserRole.enumerator;
    }
  }

  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await ApiService.instance.login(username, password);

      if (response['success'] == true) {
        _token = response['token'] as String?;

        final userData = response['user'] as Map<String, dynamic>?;
        if (userData != null) {
          _user = User(
            id: userData['id']?.toString() ?? '',
            username: userData['username']?.toString() ?? username,
            email: userData['email']!.toString(),
            role: _parseUserRole(userData['role']?.toString()),
            createdAt: userData['created_at'] != null
                ? DateTime.tryParse(userData['created_at'].toString()) ?? DateTime.now()
                : DateTime.now(),
          );

          // Save to SharedPreferences
          final prefs = await SharedPreferences.getInstance();
          if (_token != null) {
            await prefs.setString('token', _token!);
          }
          await prefs.setString('user_id', _user!.id);
          await prefs.setString('username', _user!.username);
          if (_user!.email != null) {
            await prefs.setString('email', _user!.email!);
          }
          await prefs.setString('role', _user!.role.toString().split('.').last);
        }

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        _error = response['message']?.toString() ?? 'Login failed';
        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> logout() async {
    try {
      _user = null;
      _token = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('user_id');
      await prefs.remove('username');
      await prefs.remove('email');
      await prefs.remove('role');

      notifyListeners();
    } catch (e) {
      print('Error during logout: $e');
    }
  }

  Future<bool> checkAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      return token != null && token.isNotEmpty;
    } catch (e) {
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}