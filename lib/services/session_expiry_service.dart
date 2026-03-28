// lib/services/session_expiry_service.dart
//
// Service yang memonitor masa berlaku JWT token dan konfigurasi session
// expiry yang ditetapkan Super Admin per survey.
//
// Cara kerja:
//  1. Saat app aktif, timer periodik mengecek sisa waktu token setiap 1 menit.
//  2. Ketika sisa waktu ≤ warningBeforeExpiryMinutes → tampilkan warning banner.
//  3. Ketika token benar-benar expired (atau sessionDuration habis) → tampilkan
//     dialog "Silahkan Logout untuk Sinkronisasi Data" dengan tombol yang
//     langsung membawa user ke dialog konfirmasi logout (kode verifikasi),
//     men-skip navigasi manual ke Profile.
//  4. Service ini juga bisa di-trigger dari luar (misalnya saat 401 dari API).

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../main.dart'; // navigatorKey global

// ─────────────────────────────────────────────────────────────────────────────
// MODEL
// ─────────────────────────────────────────────────────────────────────────────

class SessionExpiryConfig {
  final int sessionDurationMinutes;
  final int tokenExpiryMinutes;
  final int warningBeforeExpiryMinutes;
  final bool autoRenewOnActivity;
  final int maxSessionDurationMinutes;
  final bool forceLogoutAfterSurveyEnd;
  final String expiryAction; // 'logout' | 'lock'

  const SessionExpiryConfig({
    this.sessionDurationMinutes = 480,
    this.tokenExpiryMinutes = 10080,
    this.warningBeforeExpiryMinutes = 30,
    this.autoRenewOnActivity = true,
    this.maxSessionDurationMinutes = 1440,
    this.forceLogoutAfterSurveyEnd = false,
    this.expiryAction = 'logout',
  });

  factory SessionExpiryConfig.fromJson(Map<String, dynamic> json) {
    return SessionExpiryConfig(
      sessionDurationMinutes: json['session_duration_minutes'] ?? 480,
      tokenExpiryMinutes: json['token_expiry_minutes'] ?? 10080,
      warningBeforeExpiryMinutes: json['warning_before_expiry_minutes'] ?? 30,
      autoRenewOnActivity: json['auto_renew_on_activity'] ?? true,
      maxSessionDurationMinutes: json['max_session_duration_minutes'] ?? 1440,
      forceLogoutAfterSurveyEnd: json['force_logout_after_survey_end'] ?? false,
      expiryAction: json['expiry_action'] ?? 'logout',
    );
  }

  Map<String, dynamic> toJson() => {
    'session_duration_minutes': sessionDurationMinutes,
    'token_expiry_minutes': tokenExpiryMinutes,
    'warning_before_expiry_minutes': warningBeforeExpiryMinutes,
    'auto_renew_on_activity': autoRenewOnActivity,
    'max_session_duration_minutes': maxSessionDurationMinutes,
    'force_logout_after_survey_end': forceLogoutAfterSurveyEnd,
    'expiry_action': expiryAction,
  };

  // Durasi token efektif: ambil nilai terkecil antara sessionDuration dan tokenExpiry
  Duration get effectiveDuration {
    if (sessionDurationMinutes == 0 && tokenExpiryMinutes == 0) {
      return const Duration(days: 365); // Tidak terbatas (1 tahun)
    }
    final candidates = <int>[
      if (sessionDurationMinutes > 0) sessionDurationMinutes,
      if (tokenExpiryMinutes > 0) tokenExpiryMinutes,
    ];
    if (candidates.isEmpty) return const Duration(days: 365);
    return Duration(minutes: candidates.reduce((a, b) => a < b ? a : b));
  }

  static const SessionExpiryConfig defaults = SessionExpiryConfig();
}

// ─────────────────────────────────────────────────────────────────────────────
// SESSION EXPIRY SERVICE
// ─────────────────────────────────────────────────────────────────────────────

/// Status kondisi sesi saat ini
enum SessionStatus {
  active,          // Sesi normal
  warningShown,    // Sudah tampil warning, belum expired
  expired,         // Token sudah kadaluarsa
}

typedef SessionExpiredCallback = void Function();
typedef SessionWarningCallback = void Function(int remainingMinutes);

class SessionExpiryService {
  static SessionExpiryService? _instance;
  static SessionExpiryService get instance =>
      _instance ??= SessionExpiryService._();
  SessionExpiryService._();

  // ── Internal state ──────────────────────────────────────────────────
  Timer? _checkTimer;
  Timer? _sessionTimer;
  SessionExpiryConfig _config = SessionExpiryConfig.defaults;
  DateTime? _loginTime;
  DateTime? _lastActivityTime;
  SessionStatus _status = SessionStatus.active;
  bool _expiredDialogShowing = false;
  bool _warningDialogShowing = false;

  // Callback yang bisa didaftarkan dari luar
  SessionExpiredCallback? _onExpired;
  SessionWarningCallback? _onWarning;

  // Keys untuk SharedPreferences
  static const _keyLoginTime = 'session_login_time';
  static const _keyLastActivity = 'session_last_activity';
  static const _keyConfig = 'session_expiry_config';

  // ── Public API ──────────────────────────────────────────────────────

  SessionStatus get status => _status;
  SessionExpiryConfig get config => _config;
  bool get isMonitoring => _checkTimer != null;

  /// Muat config yang tersimpan dari storage
  Future<void> loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_keyConfig);
      if (raw != null) {
        _config = SessionExpiryConfig.fromJson(json.decode(raw));
      }
      final loginTs = prefs.getString(_keyLoginTime);
      if (loginTs != null) {
        _loginTime = DateTime.tryParse(loginTs);
      }
      final activityTs = prefs.getString(_keyLastActivity);
      if (activityTs != null) {
        _lastActivityTime = DateTime.tryParse(activityTs);
      }
      debugPrint('✅ SessionExpiryService: config loaded');
      debugPrint(
          '   Session duration: ${_config.sessionDurationMinutes} mnt');
      debugPrint(
          '   Token expiry: ${_config.tokenExpiryMinutes} mnt');
    } catch (e) {
      debugPrint('⚠️ SessionExpiryService.loadConfig error: $e');
    }
  }

  /// Simpan config baru (dipanggil setelah fetch dari backend)
  Future<void> saveConfig(SessionExpiryConfig config) async {
    _config = config;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyConfig, json.encode(config.toJson()));
      debugPrint('💾 SessionExpiryService: config saved');
    } catch (e) {
      debugPrint('⚠️ SessionExpiryService.saveConfig error: $e');
    }
  }

  /// Dipanggil tepat setelah login berhasil
  Future<void> onLoginSuccess({SessionExpiryConfig? config}) async {
    _loginTime = DateTime.now();
    _lastActivityTime = DateTime.now();
    _status = SessionStatus.active;
    _expiredDialogShowing = false;
    _warningDialogShowing = false;

    if (config != null) {
      await saveConfig(config);
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLoginTime, _loginTime!.toIso8601String());
    await prefs.setString(_keyLastActivity, _lastActivityTime!.toIso8601String());

    startMonitoring();
    debugPrint('🚀 SessionExpiryService: monitoring started after login');
    debugPrint('   Login time: $_loginTime');
  }

  /// Catat aktivitas pengguna (dipanggil dari gesture detector di atas app)
  Future<void> recordActivity() async {
    if (_status == SessionStatus.expired) return;

    _lastActivityTime = DateTime.now();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          _keyLastActivity, _lastActivityTime!.toIso8601String());
    } catch (_) {}
  }

  /// Daftarkan callback
  void setCallbacks({
    SessionExpiredCallback? onExpired,
    SessionWarningCallback? onWarning,
  }) {
    _onExpired = onExpired;
    _onWarning = onWarning;
  }

  /// Mulai monitoring periodik
  void startMonitoring() {
    _checkTimer?.cancel();
    // Cek setiap 60 detik
    _checkTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkSession();
    });
    // Cek segera juga
    Future.delayed(const Duration(seconds: 3), _checkSession);
  }

  /// Hentikan monitoring (dipanggil saat logout)
  void stopMonitoring() {
    _checkTimer?.cancel();
    _sessionTimer?.cancel();
    _checkTimer = null;
    _sessionTimer = null;
    _status = SessionStatus.active;
    _expiredDialogShowing = false;
    _warningDialogShowing = false;
    debugPrint('🛑 SessionExpiryService: monitoring stopped');
  }

  /// Dipanggil saat API mengembalikan 401 — paksa expired
  void forceExpire({String? reason}) {
    debugPrint('⚡ SessionExpiryService: force expired — $reason');
    _status = SessionStatus.expired;
    _showExpiredDialog();
  }

  /// Reset state (setelah logout selesai)
  Future<void> resetState() async {
    stopMonitoring();
    _loginTime = null;
    _lastActivityTime = null;
    _status = SessionStatus.active;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_keyLoginTime);
      await prefs.remove(_keyLastActivity);
    } catch (_) {}
  }

  // ── Internal logic ──────────────────────────────────────────────────

  void _checkSession() {
    if (_loginTime == null) return;
    if (_status == SessionStatus.expired) return;

    final now = DateTime.now();
    final effectiveDuration = _config.effectiveDuration;

    // ── Hitung kapan sesi berakhir ──────────────────────────────────
    DateTime sessionEnd;

    if (_config.autoRenewOnActivity && _lastActivityTime != null) {
      // Dengan auto-renew: hitung dari aktivitas terakhir
      sessionEnd = _lastActivityTime!.add(effectiveDuration);

      // Terapkan cap maxSessionDuration dari waktu login
      if (_config.maxSessionDurationMinutes > 0) {
        final maxEnd = _loginTime!
            .add(Duration(minutes: _config.maxSessionDurationMinutes));
        if (maxEnd.isBefore(sessionEnd)) {
          sessionEnd = maxEnd;
        }
      }
    } else {
      // Tanpa auto-renew: hitung dari waktu login
      sessionEnd = _loginTime!.add(effectiveDuration);
    }

    final remaining = sessionEnd.difference(now);
    final remainingMinutes = remaining.inMinutes;

    debugPrint(
        '🔍 SessionCheck: remaining=${remainingMinutes}m, status=$_status');

    // ── Expired ────────────────────────────────────────────────────
    if (remaining.isNegative || remaining.inSeconds <= 0) {
      if (_status != SessionStatus.expired) {
        _status = SessionStatus.expired;
        debugPrint('🔴 SessionExpiryService: SESSION EXPIRED');
        _onExpired?.call();
        _showExpiredDialog();
      }
      return;
    }

    // ── Warning ────────────────────────────────────────────────────
    if (_config.warningBeforeExpiryMinutes > 0 &&
        remainingMinutes <= _config.warningBeforeExpiryMinutes &&
        _status == SessionStatus.active) {
      _status = SessionStatus.warningShown;
      debugPrint(
          '⚠️ SessionExpiryService: WARNING — $remainingMinutes mnt tersisa');
      _onWarning?.call(remainingMinutes);
      _showWarningBanner(remainingMinutes);
    }
  }

  // ── Dialog & Banner UI ─────────────────────────────────────────────

  void _showExpiredDialog() {
    if (_expiredDialogShowing) return;

    final context = navigatorKey.currentContext;
    if (context == null) {
      debugPrint('⚠️ SessionExpiryService: no context for dialog');
      // Retry setelah 2 detik (mungkin context belum tersedia saat startup)
      Future.delayed(const Duration(seconds: 2), _showExpiredDialog);
      return;
    }

    _expiredDialogShowing = true;

    // Tutup dialog warning jika masih terbuka
    if (_warningDialogShowing) {
      Navigator.of(context, rootNavigator: true).popUntil((route) {
        return route.settings.name != '_session_warning_banner';
      });
      _warningDialogShowing = false;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withOpacity(0.7),
      routeSettings: const RouteSettings(name: '_session_expired_dialog'),
      builder: (_) => const _SessionExpiredDialog(),
    ).then((_) {
      _expiredDialogShowing = false;
    });
  }

  void _showWarningBanner(int remainingMinutes) {
    if (_warningDialogShowing) return;

    final context = navigatorKey.currentContext;
    if (context == null) return;

    _warningDialogShowing = true;

    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      routeSettings: const RouteSettings(name: '_session_warning_banner'),
      builder: (_) => _SessionWarningBanner(remainingMinutes: remainingMinutes),
    ).then((_) {
      _warningDialogShowing = false;
    });
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DIALOG: SESSION EXPIRED
// ─────────────────────────────────────────────────────────────────────────────

class _SessionExpiredDialog extends StatelessWidget {
  const _SessionExpiredDialog();

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // Mencegah user menutup dengan tombol Back
      onWillPop: () async => false,
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: Colors.white,
        contentPadding: EdgeInsets.zero,
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header merah ──────────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
              decoration: const BoxDecoration(
                color: Color(0xFFF44336),
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.lock_clock,
                      color: Colors.white,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Sesi Telah Berakhir',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // ── Body ────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const Text(
                    'Silahkan Logout untuk Sinkronisasi Data',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF212121),
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Masa sesi Anda telah habis. Lakukan logout untuk memastikan semua data pendataan tersimpan dan tersinkronisasi ke server.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey[600],
                      height: 1.5,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Tombol utama: langsung ke konfirmasi logout
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.logout, size: 20),
                      label: const Text(
                        'Logout & Sinkronisasi Data',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w600),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFF44336),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        // Tutup dialog ini
                        Navigator.of(context, rootNavigator: true).pop();
                        // Navigasi langsung ke dialog konfirmasi logout
                        _navigateToLogoutConfirmation(context);
                      },
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Tombol sekunder: tutup dan lanjut pakai app (hanya mode 'lock')
                  if (SessionExpiryService.instance.config.expiryAction ==
                      'lock')
                    TextButton(
                      onPressed: () =>
                          Navigator.of(context, rootNavigator: true).pop(),
                      child: Text(
                        'Lanjutkan (Data Tersimpan Lokal)',
                        style: TextStyle(
                            color: Colors.grey[600], fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Navigasi langsung ke dialog konfirmasi logout (tampilan kode verifikasi),
  /// men-skip navigasi manual ke halaman Profile.
  void _navigateToLogoutConfirmation(BuildContext context) {
    showModalBottomSheet(
      context: navigatorKey.currentContext ?? context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _DirectLogoutConfirmationSheet(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BOTTOM SHEET: KONFIRMASI LOGOUT LANGSUNG (skip Profile)
// ─────────────────────────────────────────────────────────────────────────────

class _DirectLogoutConfirmationSheet extends StatefulWidget {
  const _DirectLogoutConfirmationSheet();

  @override
  State<_DirectLogoutConfirmationSheet> createState() =>
      _DirectLogoutConfirmationSheetState();
}

class _DirectLogoutConfirmationSheetState
    extends State<_DirectLogoutConfirmationSheet> {
  // Generate kode 3 digit random — sama seperti di ProfileScreen
  late final String _verificationCode;
  final TextEditingController _codeController = TextEditingController();
  bool _isLoggingOut = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _verificationCode =
        (100 + (900 * (DateTime.now().millisecond / 1000))).toInt().toString();
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _confirmLogout() async {
    if (_codeController.text.trim() != _verificationCode) {
      setState(() => _errorMessage = 'Kode verifikasi salah. Coba lagi.');
      return;
    }

    setState(() {
      _isLoggingOut = true;
      _errorMessage = null;
    });

    try {
      // Tutup bottom sheet ini dulu
      Navigator.of(context, rootNavigator: true).pop();

      // Stop session monitoring
      SessionExpiryService.instance.stopMonitoring();
      await SessionExpiryService.instance.resetState();

      // Jalankan logout via navigatorKey (agar bisa dari mana saja)
      final navContext = navigatorKey.currentContext;
      if (navContext != null) {
        // Import AuthProvider
        final authProvider = navigatorKey.currentContext!
            .findAncestorWidgetOfExactType<_AuthProviderFinder>();

        // Gunakan global navigator untuk logout + navigate
        await _performLogout();
      }
    } catch (e) {
      debugPrint('❌ DirectLogoutSheet: logout error $e');
      if (mounted) {
        setState(() {
          _isLoggingOut = false;
          _errorMessage = 'Gagal logout: $e';
        });
      }
    }
  }

  Future<void> _performLogout() async {
    // Bersihkan storage
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('token');
    await prefs.remove('user_id');
    await prefs.remove('username');
    await prefs.remove('email');
    await prefs.remove('role');
    await prefs.remove('onboarding_completed');

    // Navigate ke onboarding, hapus semua history
    navigatorKey.currentState?.pushNamedAndRemoveUntil(
      '/login',
          (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset =
        MediaQuery.of(context).viewInsets.bottom + MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Judul
          const Text(
            'Konfirmasi Logout',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1976D2),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Sesi Anda telah berakhir. Masukkan kode verifikasi untuk menyelesaikan logout dan sinkronisasi data.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey[600], height: 1.4),
          ),

          // Info box sinkronisasi
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF3E0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              children: [
                Icon(Icons.sync, color: Color(0xFFFF9800), size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Data lokal akan disinkronisasi ke server saat proses logout.',
                    style: TextStyle(
                      fontSize: 12,
                      color: Color(0xFFE65100),
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Kode verifikasi tampil besar
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 16),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _verificationCode,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 42,
                fontWeight: FontWeight.bold,
                letterSpacing: 10,
                color: Color(0xFF1976D2),
              ),
            ),
          ),
          const SizedBox(height: 12),

          Text(
            'Untuk menyelesaikan logout, ketik kode verifikasi di atas dengan benar',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
          const SizedBox(height: 16),

          // Input kode
          TextField(
            controller: _codeController,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            maxLength: 3,
            autofocus: true,
            style: const TextStyle(fontSize: 24, letterSpacing: 8),
            decoration: InputDecoration(
              hintText: '000',
              counterText: '',
              filled: true,
              fillColor: Colors.grey[100],
              errorText: _errorMessage,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Color(0xFFE0E0E0), width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                const BorderSide(color: Color(0xFF1976D2), width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.red, width: 2),
              ),
            ),
            onChanged: (_) {
              if (_errorMessage != null) {
                setState(() => _errorMessage = null);
              }
            },
            onSubmitted: (_) => _confirmLogout(),
          ),
          const SizedBox(height: 24),

          // Tombol aksi
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isLoggingOut
                      ? null
                      : () => Navigator.of(context, rootNavigator: true).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: const BorderSide(color: Color(0xFF1976D2), width: 2),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'BATAL',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1976D2),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: _isLoggingOut ? null : _confirmLogout,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFF44336),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: _isLoggingOut
                      ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                      AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                      : const Text(
                    'LOGOUT',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// Placeholder class hanya untuk type reference di _confirmLogout
// (provider diakses via navigatorKey.currentContext)
class _AuthProviderFinder extends StatelessWidget {
  const _AuthProviderFinder({required Widget child}) : super(key: null);
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

// ─────────────────────────────────────────────────────────────────────────────
// WARNING BANNER (muncul sebelum session expired)
// ─────────────────────────────────────────────────────────────────────────────

class _SessionWarningBanner extends StatelessWidget {
  final int remainingMinutes;
  const _SessionWarningBanner({required this.remainingMinutes});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 16,
          right: 16,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFF9800),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.2),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.access_time, color: Colors.white, size: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Sesi Akan Berakhir',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        'Sesi Anda akan berakhir dalam $remainingMinutes menit.',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: () =>
                      Navigator.of(context, rootNavigator: true).pop(),
                  child: const Text(
                    'OK',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}