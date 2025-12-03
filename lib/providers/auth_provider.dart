import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import 'location_provider.dart';
import 'fraud_detection_provider.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  // 🆕 NEW: References ke provider lain untuk auto-start
  LocationProvider? _locationProvider;
  FraudDetectionProvider? _fraudDetectionProvider;

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _user != null;

  AuthProvider() {
    _loadUserFromStorage();
  }

  /// 🆕 NEW: Set provider references untuk auto-start
  /// Dipanggil dari main.dart atau HomeScreen
  void setProviders({
    required LocationProvider locationProvider,
    required FraudDetectionProvider fraudDetectionProvider,
  }) {
    _locationProvider = locationProvider;
    _fraudDetectionProvider = fraudDetectionProvider;
    debugPrint('✅ AuthProvider: Providers linked');
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

          // 🆕 NEW: Auto-start services setelah load dari storage
          // Akan dipanggil dari HomeScreen karena providers belum tersedia di sini

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

        // 🆕 NEW: Auto-start tracking dan fraud detection
        print('🚀 Auto-starting tracking services...');
        await _autoStartServices();

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

  /// 🆕 NEW: Auto-start semua services setelah login
  Future<void> _autoStartServices() async {
    if (_user == null) {
      debugPrint('⚠️ Cannot auto-start services: no user');
      return;
    }

    final userId = _user!.id;

    try {
      debugPrint('🚀 Auto-starting all services for user: $userId');

      // Start fraud detection monitoring
      if (_fraudDetectionProvider != null) {
        if (!_fraudDetectionProvider!.isMonitoring) {
          await _fraudDetectionProvider!.startMonitoring();
          debugPrint('✅ Fraud detection monitoring started');
        }
      } else {
        debugPrint('⚠️ FraudDetectionProvider not available - will start from HomeScreen');
      }

      // Start location tracking with fraud detection
      if (_locationProvider != null) {
        if (!_locationProvider!.isTracking) {
          await _locationProvider!.startTrackingWithFraudDetection(userId);
          debugPrint('✅ Location tracking started');
        }
      } else {
        debugPrint('⚠️ LocationProvider not available - will start from HomeScreen');
      }

      debugPrint('✅ Auto-start services completed');
    } catch (e) {
      debugPrint('⚠️ Some services failed to auto-start: $e');
      // Jangan throw error, biarkan app tetap berjalan
      // Services akan di-start dari HomeScreen
    }
  }

  /// 🆕 NEW: Public method untuk start services (dipanggil dari HomeScreen)
  Future<void> ensureServicesStarted() async {
    if (_user == null) return;
    await _autoStartServices();
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

      // 🆕 NEW: Stop all services before logout
      await _stopAllServices();

      _user = null;
      _token = null;
      _error = null;

      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('token');
      await prefs.remove('user_id');
      await prefs.remove('username');
      await prefs.remove('email');
      await prefs.remove('role');

      // 🔧 FIX: Clear onboarding status so it shows again after logout
      await prefs.remove('onboarding_completed');

      print('✅ Logout completed - redirecting to onboarding\n');

      notifyListeners();
    } catch (e) {
      print('❌ Error during logout: $e\n');
      _error = 'Logout gagal: $e';
      notifyListeners();
    }
  }

  /// 🆕 NEW: Stop all services saat logout
  Future<void> _stopAllServices() async {
    try {
      debugPrint('🛑 Stopping all services...');

      // Stop location tracking
      if (_locationProvider != null && _locationProvider!.isTracking) {
        await _locationProvider!.stopTracking();
        debugPrint('✅ Location tracking stopped');
      }

      // Stop fraud detection monitoring
      if (_fraudDetectionProvider != null && _fraudDetectionProvider!.isMonitoring) {
        await _fraudDetectionProvider!.stopMonitoring();
        debugPrint('✅ Fraud detection monitoring stopped');
      }

      debugPrint('✅ All services stopped');
    } catch (e) {
      debugPrint('⚠️ Error stopping services: $e');
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