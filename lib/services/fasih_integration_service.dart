// lib/services/fasih_integration_service.dart
//
// Service integrasi dengan aplikasi Fasih (BPS).
// Mengelola sesi pendataan, deep link ke Fasih,
// dan polling/webhook status penyelesaian.
//
// ⚠️  MOCK — ganti konstanta yang ditandai [MOCK] dengan
//     endpoint / skema URL Fasih yang sesungguhnya.

import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:http/http.dart' as http;
import 'storage_service.dart';

// ─────────────────────────────────────────────────────────────
// ENUM & MODEL
// ─────────────────────────────────────────────────────────────

enum FasihSyncStatus { pending, inProgress, completed, failed }

class FasihSession {
  final String sessionId;
  final String respondentId;
  final String surveyId;
  final String enumeratorId;
  final DateTime createdAt;
  FasihSyncStatus status;
  DateTime? completedAt;

  FasihSession({
    required this.sessionId,
    required this.respondentId,
    required this.surveyId,
    required this.enumeratorId,
    required this.createdAt,
    this.status = FasihSyncStatus.pending,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    'session_id': sessionId,
    'respondent_id': respondentId,
    'survey_id': surveyId,
    'enumerator_id': enumeratorId,
    'created_at': createdAt.toIso8601String(),
    'status': status.name,
    'completed_at': completedAt?.toIso8601String(),
  };

  factory FasihSession.fromJson(Map<String, dynamic> json) => FasihSession(
    sessionId: json['session_id'],
    respondentId: json['respondent_id'],
    surveyId: json['survey_id'],
    enumeratorId: json['enumerator_id'],
    createdAt: DateTime.parse(json['created_at']),
    status: FasihSyncStatus.values.firstWhere(
          (e) => e.name == json['status'],
      orElse: () => FasihSyncStatus.pending,
    ),
    completedAt: json['completed_at'] != null
        ? DateTime.parse(json['completed_at'])
        : null,
  );
}

class FasihLaunchResult {
  final bool success;
  final FasihSession? session;
  final bool appLaunched; // true = app native, false = browser
  final String message;

  FasihLaunchResult({
    required this.success,
    this.session,
    this.appLaunched = false,
    required this.message,
  });
}

// ─────────────────────────────────────────────────────────────
// SERVICE
// ─────────────────────────────────────────────────────────────

class FasihIntegrationService {
  static FasihIntegrationService? _instance;
  static FasihIntegrationService get instance =>
      _instance ??= FasihIntegrationService._();
  FasihIntegrationService._();

  // ── [MOCK] Konfigurasi ─────────────────────────────────────
  // Ganti ketiga konstanta ini dengan nilai asli dari tim Fasih.
  static const String _apiBaseUrl =
      'https://api-mock.fasih.bps.go.id'; // [MOCK] endpoint Fasih
  static const String _deepLinkScheme =
      'fasih://survey'; // [MOCK] deep-link scheme app Fasih
  static const String _webFallback =
      'https://fasih.bps.go.id/survey'; // [MOCK] fallback browser
  // ──────────────────────────────────────────────────────────

  final Map<String, FasihSession> _sessions = {};
  final Map<String, Function(String, FasihSyncStatus)> _callbacks = {};
  final Map<String, Timer> _pollingTimers = {};

  // ── Public API ────────────────────────────────────────────

  /// Mulai sesi pendataan: simpan sesi → ubah status → buka Fasih.
  Future<FasihLaunchResult> startDataCollection({
    required String respondentId,
    required String surveyId,
    required String enumeratorId,
    required String respondentName,
    String? regionCode,
    Map<String, dynamic>? additionalData,
  }) async {
    try {
      debugPrint('🚀 FasihIntegration: starting session for $respondentId');

      final session = await _createSession(
        respondentId: respondentId,
        surveyId: surveyId,
        enumeratorId: enumeratorId,
        respondentName: respondentName,
        regionCode: regionCode,
        additionalData: additionalData,
      );

      _sessions[respondentId] = session;
      _startPolling(respondentId, session.sessionId);

      final launched = await _launchFasih(
        sessionId: session.sessionId,
        surveyId: surveyId,
        respondentId: respondentId,
        respondentName: respondentName,
      );

      return FasihLaunchResult(
        success: true,
        session: session,
        appLaunched: launched,
        message: launched
            ? 'Aplikasi Fasih berhasil dibuka'
            : 'Fasih dibuka di browser (aplikasi tidak terdeteksi)',
      );
    } catch (e) {
      debugPrint('❌ FasihIntegration error: $e');
      return FasihLaunchResult(
        success: false,
        message: 'Gagal memulai pendataan: $e',
      );
    }
  }

  /// Daftarkan callback perubahan status untuk satu responden.
  void registerStatusCallback(
      String respondentId,
      Function(String, FasihSyncStatus) callback,
      ) {
    _callbacks[respondentId] = callback;
  }

  void unregisterStatusCallback(String respondentId) {
    _callbacks.remove(respondentId);
    _pollingTimers[respondentId]?.cancel();
    _pollingTimers.remove(respondentId);
  }

  FasihSession? getActiveSession(String respondentId) =>
      _sessions[respondentId];

  /// Periksa status sesi secara manual (misal saat resume app).
  Future<FasihSyncStatus?> checkSessionStatus(String respondentId) async {
    final session = _sessions[respondentId];
    if (session == null) return null;

    try {
      final newStatus = await _fetchStatus(session.sessionId);
      if (newStatus != session.status) {
        session.status = newStatus;
        if (newStatus == FasihSyncStatus.completed) {
          session.completedAt = DateTime.now();
        }
        _callbacks[respondentId]?.call(respondentId, newStatus);
      }
      return newStatus;
    } catch (e) {
      return session.status;
    }
  }

  /// [DEMO ONLY] Tandai sesi sebagai selesai tanpa membuka Fasih.
  /// Gunakan untuk testing / demo di emulator.
  Future<void> simulateCompletion(String respondentId) async {
    final session = _sessions[respondentId];
    if (session == null) return;

    session.status = FasihSyncStatus.completed;
    session.completedAt = DateTime.now();
    _callbacks[respondentId]?.call(respondentId, FasihSyncStatus.completed);
    _pollingTimers[respondentId]?.cancel();
    debugPrint('✅ [DEMO] Simulated Fasih completion for: $respondentId');
  }

  void dispose() {
    for (final t in _pollingTimers.values) {
      t.cancel();
    }
    _pollingTimers.clear();
    _callbacks.clear();
  }

  // ── Private helpers ───────────────────────────────────────

  Future<FasihSession> _createSession({
    required String respondentId,
    required String surveyId,
    required String enumeratorId,
    required String respondentName,
    String? regionCode,
    Map<String, dynamic>? additionalData,
  }) async {
    // ── [MOCK] Ganti blok di bawah dengan POST nyata ke Fasih ──
    //
    // final headers = await _headers();
    // final response = await http.post(
    //   Uri.parse('$_apiBaseUrl/api/v1/sessions'),
    //   headers: headers,
    //   body: json.encode({
    //     'respondent_id': respondentId,
    //     'survey_id':     surveyId,
    //     'enumerator_id': enumeratorId,
    //     'respondent_name': respondentName,
    //     'region_code':   regionCode,
    //     'metadata':      additionalData,
    //   }),
    // ).timeout(const Duration(seconds: 10));
    //
    // if (response.statusCode == 201) {
    //   return FasihSession.fromJson(json.decode(response.body));
    // }
    // throw Exception('Fasih API error: ${response.statusCode}');
    // ───────────────────────────────────────────────────────

    await Future.delayed(const Duration(milliseconds: 200)); // simulasi latency
    final id =
        'FASIH-${DateTime.now().millisecondsSinceEpoch}-${respondentId.substring(0, 8).toUpperCase()}';
    debugPrint('📋 [MOCK] Fasih session created: $id');
    return FasihSession(
      sessionId: id,
      respondentId: respondentId,
      surveyId: surveyId,
      enumeratorId: enumeratorId,
      createdAt: DateTime.now(),
      status: FasihSyncStatus.inProgress,
    );
  }

  Future<bool> _launchFasih({
    required String sessionId,
    required String surveyId,
    required String respondentId,
    required String respondentName,
  }) async {
    // Coba deep link ke aplikasi Fasih terlebih dahulu
    final deepLink = Uri.parse(
      '$_deepLinkScheme'
          '?session_id=$sessionId'
          '&survey_id=$surveyId'
          '&respondent_id=$respondentId'
          '&name=${Uri.encodeComponent(respondentName)}',
    );

    try {
      if (await canLaunchUrl(deepLink)) {
        await launchUrl(deepLink, mode: LaunchMode.externalApplication);
        debugPrint('✅ Opened Fasih app (deep link)');
        return true;
      }
    } catch (_) {}

    // Fallback browser
    final webUrl = Uri.parse(
      '$_webFallback'
          '?session_id=$sessionId'
          '&survey_id=$surveyId'
          '&respondent_id=$respondentId',
    );

    try {
      await launchUrl(webUrl, mode: LaunchMode.externalApplication);
      debugPrint('✅ Opened Fasih in browser (deep link unavailable)');
      return false;
    } catch (e) {
      debugPrint('❌ Cannot launch Fasih at all: $e');
      return false;
    }
  }

  Future<FasihSyncStatus> _fetchStatus(String sessionId) async {
    // ── [MOCK] Ganti dengan GET nyata ──────────────────────────
    //
    // final headers = await _headers();
    // final response = await http.get(
    //   Uri.parse('$_apiBaseUrl/api/v1/sessions/$sessionId/status'),
    //   headers: headers,
    // ).timeout(const Duration(seconds: 10));
    //
    // if (response.statusCode == 200) {
    //   final data = json.decode(response.body);
    //   return FasihSyncStatus.values.firstWhere(
    //     (e) => e.name == data['status'],
    //     orElse: () => FasihSyncStatus.inProgress,
    //   );
    // }
    // ───────────────────────────────────────────────────────────
    return FasihSyncStatus.inProgress; // [MOCK]
  }

  void _startPolling(String respondentId, String sessionId) {
    _pollingTimers[respondentId]?.cancel();
    // Poll setiap 30 detik; berhenti otomatis saat selesai/gagal
    _pollingTimers[respondentId] = Timer.periodic(
      const Duration(seconds: 30),
          (timer) async {
        final status = await checkSessionStatus(respondentId);
        if (status == FasihSyncStatus.completed ||
            status == FasihSyncStatus.failed) {
          timer.cancel();
          _pollingTimers.remove(respondentId);
        }
      },
    );
  }

  Future<Map<String, String>> _headers() async {
    final token = await StorageService.instance.getToken();
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }
}