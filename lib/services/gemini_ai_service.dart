import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';

class GeminiAIService {
  // Singleton pattern agar hemat memori
  static GeminiAIService? _instance;
  static GeminiAIService get instance => _instance ??= GeminiAIService._();

  GeminiAIService._();

  late GenerativeModel _model;
  ChatSession? _chatSession;

  // ⚠️ Masukkan API Key
  static const String _apiKey = 'AIzaSyDMCTSiuH-RhLWLrCKz51bmcf0bZQrSJMY';

  /// Inisialisasi Model saat aplikasi mulai
  void initialize() {
    _model = GenerativeModel(
      model: 'gemini-2.5-flash', // Model cepat & hemat untuk mobile
      apiKey: _apiKey,
      // Instruksi agar AI berperan sebagai asisten survei
      systemInstruction: Content.system(
        '''
        Anda adalah asisten AI profesional khusus untuk petugas pendataan lapangan (enumerator) dan sensus statistik.
        
        TUGAS UTAMA ANDA:
        1. Membantu menjelaskan definisi operasional survei (misal: definisi rumah tangga, blok sensus, responden).
        2. Melakukan validasi logika data (misal: "Apakah masuk akal umur 5 tahun sudah menikah?").
        3. Memberikan solusi teknis pendataan lapangan.

        ATURAN PEMBATASAN (GUARDRAILS):
        1. JANGAN menjawab pertanyaan pengetahuan umum, teka-teki, lelucon, resep masakan, atau topik hiburan yang TIDAK berhubungan dengan pekerjaan lapangan.
        2. Jika pengguna bertanya hal di luar konteks survei (seperti "Ikan apa yang bisa terbang?"), tolak dengan sopan menggunakan kalimat baku:
           "Maaf, saya hanya dapat membantu menjawab pertanyaan terkait teknis survei dan sensus."
        3. Jawablah dengan singkat, padat, dan langsung pada inti permasalahan (karena petugas bekerja di lapangan).
      '''
      ),
    );
  }

  /// Memulai sesi chat baru (misalnya saat buka halaman chat)
  void startChat() {
    _chatSession = _model.startChat(
      history: [
        // Opsional: Bisa isi history awal jika perlu
      ],
    );
    debugPrint('✅ Sesi chat baru dimulai');
  }

  /// Mengirim pesan dan mendapatkan balasan
  Future<String> sendMessage(String message) async {
    try {
      // Pastikan sesi chat sudah ada
      if (_chatSession == null) {
        initialize(); // Jaga-jaga jika belum init
        startChat();
      }

      debugPrint('📤 Mengirim: $message');

      // Kirim pesan menggunakan SDK
      final response = await _chatSession!.sendMessage(
        Content.text(message),
      );

      final text = response.text;

      if (text == null) {
        throw Exception('Respon AI kosong');
      }

      debugPrint('📥 Diterima: $text');
      return text;

    } catch (e) {
      debugPrint('❌ Error Gemini SDK: $e');
      if (e.toString().contains('User location is not supported')) {
        return 'Maaf, layanan AI belum tersedia di lokasi/jaringan ini.';
      }
      if (e.toString().contains('API_KEY_INVALID')) {
        return 'Kunci API tidak valid. Mohon periksa konfigurasi.';
      }
      // Error umum (biasanya koneksi internet di lapangan)
      throw Exception('Gagal terhubung ke asisten AI. Periksa sinyal internet.');
    }
  }
}