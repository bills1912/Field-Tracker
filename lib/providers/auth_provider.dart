import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

class AuthProvider with ChangeNotifier {
  User? _user;
  bool _isLoading = false;
  bool _isAuthenticated = false;

  User? get user => _user;
  bool get isLoading => _isLoading;
  bool get isAuthenticated => _isAuthenticated;

  AuthProvider() {
    _checkAuth();
  }

  Future<void> _checkAuth() async {
    _isLoading = true;
    notifyListeners();

    try {
      final token = await StorageService.instance.getToken();
      final savedUser = await StorageService.instance.getUser();

      if (token != null && savedUser != null) {
        _user = savedUser;
        _isAuthenticated = true;
      }
    } catch (e) {
      print('Auth check error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> login(String email, String password) async {
    _isLoading = true;
    notifyListeners();

    try {
      final response = await ApiService.instance.login(email, password);
      
      final token = response['access_token'];
      final userData = response['user'];
      
      await StorageService.instance.saveToken(token);
      _user = User.fromJson(userData);
      await StorageService.instance.saveUser(_user!);
      
      _isAuthenticated = true;
    } catch (e) {
      rethrow;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await StorageService.instance.removeToken();
    await StorageService.instance.removeUser();
    _user = null;
    _isAuthenticated = false;
    notifyListeners();
  }
}