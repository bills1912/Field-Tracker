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
      print('\n📱 Loading user from storage...');
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString('token');

      if (_token != null) {
        print('✓ Token found in storage');
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
            createdAt: DateTime.now(),
          );
          print('✅ User loaded: ${_user!.username} (${_user!.role.name})');
          notifyListeners();
        } else {
          print('⚠️ Incomplete user data in storage');
        }
      } else {
        print('ℹ️ No token in storage - user not logged in');
      }
    } catch (e) {
      print('❌ Error loading user from storage: $e');
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

  Future<bool> login(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      print('\n' + '='*60);
      print('🔐 AUTH PROVIDER - LOGIN START');
      print('='*60);
      print('📧 Email: $email');
      print('🌐 Calling ApiService.instance.login()...');

      // CRITICAL: Call API service
      final response = await ApiService.instance.login(email, password);

      print('\n📦 API RESPONSE RECEIVED:');
      print(response.toString());
      print('');

      // Check if response is valid
      if (response == null) {
        throw Exception('API mengembalikan response null');
      }

      // PENTING: Periksa berbagai format response yang mungkin
      bool success = false;

      // Check for success field
      if (response.containsKey('success')) {
        success = response['success'] == true;
        print('✓ Found success field: $success');
      }

      // Check for token - jika ada token, anggap berhasil
      if (response.containsKey('access_token') && response['access_token'] != null) {
        success = true;
        print('✓ Found token field');
      }

      print('');
      print('📊 ANALYSIS:');
      print('  - Success status: $success');
      print('  - Has token: ${response.containsKey('access_token')}');
      print('  - Has user: ${response.containsKey('user')}');
      print('');

      if (success) {
        // Extract token
        _token = response['access_token']?.toString();

        if (_token == null || _token!.isEmpty) {
          throw Exception('Token tidak ditemukan dalam response API');
        }

        print('🔑 Token extracted: ${_token!.substring(0, min(20, _token!.length))}...');

        // Extract user data
        dynamic userData = response['user'];

        if (userData == null) {
          // Try alternative key
          userData = response['data'];
        }

        if (userData == null) {
          throw Exception('Data user tidak ditemukan dalam response API');
        }

        print('👤 User data found:');
        print('   $userData');
        print('');

        // Create User object
        _user = User(
          id: (userData['id'] ?? userData['_id'] ?? email).toString(),
          username: (userData['username'] ?? userData['name'] ?? email.split('@')[0]).toString(),
          email: (userData['email'] ?? email).toString(),
          role: _parseUserRole(userData['role']?.toString()),
          createdAt: userData['created_at'] != null
              ? DateTime.tryParse(userData['created_at'].toString()) ?? DateTime.now()
              : DateTime.now(),
        );

        print('✅ User object created:');
        print('   ID: ${_user!.id}');
        print('   Username: ${_user!.username}');
        print('   Email: ${_user!.email}');
        print('   Role: ${_user!.role.name}');
        print('');

        // Save to SharedPreferences
        print('💾 Saving to SharedPreferences...');
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('token', _token!);
        await prefs.setString('user_id', _user!.id);
        await prefs.setString('username', _user!.username);
        if (_user!.email != null) {
          await prefs.setString('email', _user!.email!);
        }
        await prefs.setString('role', _user!.role.name);

        print('✅ Data saved to storage');
        print('='*60);
        print('🎉 LOGIN SUCCESS');
        print('='*60 + '\n');

        _isLoading = false;
        notifyListeners();
        return true;
      } else {
        // Login failed
        _error = response['message']?.toString() ??
            response['error']?.toString() ??
            'Login gagal. Periksa email dan password Anda.';

        print('❌ LOGIN FAILED:');
        print('   Error: $_error');
        print('='*60 + '\n');

        _isLoading = false;
        notifyListeners();
        return false;
      }
    } catch (e, stackTrace) {
      print('\n' + '='*60);
      print('💥 EXCEPTION in AuthProvider.login()');
      print('='*60);
      print('Error: $e');
      print('');
      print('StackTrace:');
      print(stackTrace);
      print('='*60 + '\n');

      _error = _parseErrorMessage(e.toString());
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  int min(int a, int b) => a < b ? a : b;

  String _parseErrorMessage(String error) {
    if (error.contains('SocketException') || error.contains('No internet')) {
      return 'Tidak ada koneksi internet. Periksa jaringan Anda.';
    } else if (error.contains('TimeoutException') || error.contains('timeout')) {
      return 'Koneksi timeout. Coba lagi.';
    } else if (error.contains('401') || error.contains('Unauthorized')) {
      return 'Email atau password salah.';
    } else if (error.contains('404')) {
      return 'Server tidak ditemukan. Hubungi administrator.';
    } else if (error.contains('500')) {
      return 'Server error. Coba lagi nanti.';
    } else if (error.contains('FormatException')) {
      return 'Format response dari server tidak valid.';
    } else if (error.contains('Token tidak ditemukan')) {
      return 'Server tidak mengirim token. Hubungi administrator.';
    } else if (error.contains('Data user tidak ditemukan')) {
      return 'Server tidak mengirim data user. Hubungi administrator.';
    }
    return 'Error: ${error.length > 100 ? error.substring(0, 100) + "..." : error}';
  }

  Future<void> logout() async {
    try {
      print('\n🚪 LOGOUT START');
      print('User: ${_user?.username}');

      _user = null;
      _token = null;
      _error = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('user_id');
      await prefs.remove('username');
      await prefs.remove('email');
      await prefs.remove('role');

      print('✅ Logout completed\n');

      notifyListeners();
    } catch (e) {
      print('❌ Error during logout: $e\n');
      _error = 'Logout gagal: $e';
      notifyListeners();
    }
  }

  Future<bool> checkAuth() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString('token');
      final userId = prefs.getString('user_id');

      bool isAuth = token != null && token.isNotEmpty && userId != null;
      print('🔍 Auth check: $isAuth');

      return isAuth;
    } catch (e) {
      print('❌ Error checking auth: $e');
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}