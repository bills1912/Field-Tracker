// lib/providers/session_expiry_provider.dart
//
// Provider yang membungkus SessionExpiryService dan mengekspos state
// ke widget tree. Diinisialisasi dari main.dart bersamaan dengan
// provider lainnya.

import 'package:flutter/foundation.dart';
import '../services/session_expiry_service.dart';

class SessionExpiryProvider with ChangeNotifier {
  final SessionExpiryService _service = SessionExpiryService.instance;

  SessionStatus get status => _service.status;
  SessionExpiryConfig get config => _service.config;
  bool get isExpired => _service.status == SessionStatus.expired;
  bool get isWarning => _service.status == SessionStatus.warningShown;
  bool get isMonitoring => _service.isMonitoring;

  SessionExpiryProvider() {
    // Daftarkan callback agar provider bisa notify listeners
    _service.setCallbacks(
      onExpired: () {
        debugPrint('📣 SessionExpiryProvider: session expired — notifying');
        notifyListeners();
      },
      onWarning: (remaining) {
        debugPrint('📣 SessionExpiryProvider: warning $remaining mnt');
        notifyListeners();
      },
    );
  }

  /// Muat config dari SharedPreferences (dipanggil dari main.dart saat startup)
  Future<void> initialize() async {
    await _service.loadConfig();
    // Jika user sudah login sebelumnya (auto-login), langsung mulai monitoring
    _service.startMonitoring();
    notifyListeners();
  }

  /// Dipanggil setelah login sukses dari AuthProvider
  Future<void> onLoginSuccess({SessionExpiryConfig? config}) async {
    await _service.onLoginSuccess(config: config);
    notifyListeners();
  }

  /// Dipanggil saat logout
  Future<void> onLogout() async {
    await _service.resetState();
    notifyListeners();
  }

  /// Catat aktivitas pengguna — dipanggil dari gesture detector di root app
  Future<void> recordActivity() async {
    await _service.recordActivity();
  }

  /// Paksa session expired (misalnya dari 401 response)
  void forceExpire({String? reason}) {
    _service.forceExpire(reason: reason);
    notifyListeners();
  }

  /// Update config dari survey yang di-fetch
  Future<void> updateConfig(SessionExpiryConfig config) async {
    await _service.saveConfig(config);
    notifyListeners();
  }

  @override
  void dispose() {
    _service.stopMonitoring();
    super.dispose();
  }
}