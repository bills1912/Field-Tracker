// lib/widgets/fasih_launch_button.dart
//
// Widget tombol "Mulai Pendataan di Fasih".
// Tersedia dalam dua ukuran:
//   compact: true  → chip kecil untuk list & popup marker peta
//   compact: false → tombol penuh untuk modal detail responden

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/respondent.dart';
import '../providers/auth_provider.dart';
import '../providers/survey_provider.dart';
import '../services/fasih_integration_service.dart';
import '../services/api_service.dart';

class FasihLaunchButton extends StatefulWidget {
  final Respondent respondent;

  /// Dipanggil setelah status responden berubah (IN_PROGRESS atau COMPLETED).
  final Function(RespondentStatus newStatus)? onStatusChanged;

  /// true  = chip kecil (list / marker popup)
  /// false = tombol lebar penuh (modal detail)
  final bool compact;

  const FasihLaunchButton({
    super.key,
    required this.respondent,
    this.onStatusChanged,
    this.compact = false,
  });

  @override
  State<FasihLaunchButton> createState() => _FasihLaunchButtonState();
}

class _FasihLaunchButtonState extends State<FasihLaunchButton> {
  bool _isLoading = false;
  FasihSession? _session;

  @override
  void initState() {
    super.initState();
    _session = FasihIntegrationService.instance
        .getActiveSession(widget.respondent.id);
    FasihIntegrationService.instance.registerStatusCallback(
      widget.respondent.id,
      _onStatusChanged,
    );
  }

  @override
  void dispose() {
    FasihIntegrationService.instance
        .unregisterStatusCallback(widget.respondent.id);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────
  // Callback dari FasihIntegrationService
  // ─────────────────────────────────────────────────────────

  void _onStatusChanged(String id, FasihSyncStatus status) {
    if (!mounted) return;
    if (status == FasihSyncStatus.completed) _markCompleted();
  }

  Future<void> _markCompleted() async {
    try {
      await ApiService.instance.updateRespondent(
        widget.respondent.id,
        {'status': RespondentStatus.completed.name},
      );
      if (!mounted) return;
      widget.onStatusChanged?.call(RespondentStatus.completed);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${widget.respondent.name} — Pendataan selesai!',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          backgroundColor: const Color(0xFF4CAF50),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('❌ Failed to mark respondent completed: $e');
    }
  }

  // ─────────────────────────────────────────────────────────
  // Aksi utama: mulai / lanjutkan pendataan
  // ─────────────────────────────────────────────────────────

  Future<void> _start() async {
    if (_isLoading) return;

    final user = context.read<AuthProvider>().user;
    final survey = context.read<SurveyProvider>().selectedSurvey;

    if (user == null) {
      _snack('Sesi tidak valid. Silakan login ulang.', Colors.red);
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1 ─ Ubah status ke IN_PROGRESS di backend
      await ApiService.instance.updateRespondent(
        widget.respondent.id,
        {'status': RespondentStatus.in_progress.name},
      );
      widget.onStatusChanged?.call(RespondentStatus.in_progress);

      // 2 ─ Buat sesi Fasih + buka aplikasi
      final result =
      await FasihIntegrationService.instance.startDataCollection(
        respondentId: widget.respondent.id,
        surveyId: widget.respondent.surveyId,
        enumeratorId: user.id,
        respondentName: widget.respondent.name,
        regionCode: widget.respondent.region_code,
        additionalData: {
          'survey_title': survey?.title,
          'address': widget.respondent.address,
          'phone': widget.respondent.phone,
          'latitude': widget.respondent.latitude,
          'longitude': widget.respondent.longitude,
        },
      );

      if (!mounted) return;
      setState(() => _session = result.session);

      if (result.success) {
        _showFasihDialog(result);
      } else {
        _snack(result.message, Colors.orange);
      }
    } catch (e) {
      if (!mounted) return;
      _snack('Gagal memulai pendataan: $e', Colors.red);
      // Rollback UI jika gagal
      widget.onStatusChanged?.call(RespondentStatus.pending);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────
  // Dialog konfirmasi setelah Fasih terbuka
  // ─────────────────────────────────────────────────────────

  void _showFasihDialog(FasihLaunchResult result) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFE3F2FD),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.assignment_outlined,
                  color: Color(0xFF1976D2), size: 26),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Pendataan Dimulai',
                  style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status badge
            _badge(
              icon: Icons.hourglass_top,
              label: 'Status: Sedang Berlangsung',
              bg: const Color(0xFFFFF3E0),
              fg: const Color(0xFFE65100),
            ),
            const SizedBox(height: 14),
            _row(Icons.person_outline, 'Responden',
                widget.respondent.name),
            if (result.session != null)
              _row(Icons.tag, 'Session ID',
                  result.session!.sessionId.split('-').last),
            const SizedBox(height: 10),
            // Status buka Fasih
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: result.appLaunched
                    ? const Color(0xFFE8F5E9)
                    : const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    result.appLaunched
                        ? Icons.smartphone
                        : Icons.open_in_browser,
                    size: 18,
                    color: result.appLaunched
                        ? const Color(0xFF2E7D32)
                        : const Color(0xFFF57F17),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      result.appLaunched
                          ? 'Aplikasi Fasih berhasil dibuka.'
                          : 'Fasih dibuka di browser.\nInstal aplikasi Fasih untuk pengalaman terbaik.',
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.4,
                        color: result.appLaunched
                            ? const Color(0xFF1B5E20)
                            : const Color(0xFFE65100),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Text(
              'Status akan otomatis menjadi SELESAI setelah data disubmit di Fasih.',
              style: TextStyle(
                  fontSize: 12, color: Colors.grey[600], height: 1.4),
            ),
          ],
        ),
        actions: [
          // Tombol demo — hapus di production
          TextButton.icon(
            icon: const Icon(Icons.science_outlined, size: 16),
            label: const Text('Simulasi Selesai'),
            style: TextButton.styleFrom(foregroundColor: Colors.grey[600]),
            onPressed: () {
              Navigator.pop(ctx);
              FasihIntegrationService.instance
                  .simulateCompletion(widget.respondent.id);
            },
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Build
  // ─────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isCompleted =
        widget.respondent.status == RespondentStatus.completed;
    final isInProgress =
        widget.respondent.status == RespondentStatus.in_progress;

    return widget.compact
        ? _buildChip(isCompleted, isInProgress)
        : _buildWide(isCompleted, isInProgress);
  }

  // ── Chip kecil ────────────────────────────────────────────
  Widget _buildChip(bool isCompleted, bool isInProgress) {
    if (isCompleted) {
      return _chipContainer(
        color: const Color(0xFFE8F5E9),
        border: const Color(0xFF4CAF50),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 13, color: Color(0xFF4CAF50)),
            SizedBox(width: 4),
            Text('Selesai',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E7D32))),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    return GestureDetector(
      onTap: _start,
      child: _chipContainer(
        color: isInProgress
            ? const Color(0xFFFFF3E0)
            : const Color(0xFF1976D2),
        border: isInProgress
            ? const Color(0xFFFF9800)
            : const Color(0xFF1565C0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isInProgress ? Icons.open_in_new : Icons.assignment_ind,
              size: 13,
              color: isInProgress
                  ? const Color(0xFFE65100)
                  : Colors.white,
            ),
            const SizedBox(width: 5),
            Text(
              isInProgress ? 'Lanjutkan di Fasih' : 'Mulai di Fasih',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isInProgress
                    ? const Color(0xFFE65100)
                    : Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tombol lebar ──────────────────────────────────────────
  Widget _buildWide(bool isCompleted, bool isInProgress) {
    if (isCompleted) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFF4CAF50)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 20),
            SizedBox(width: 8),
            Text('Pendataan Selesai di Fasih',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2E7D32))),
          ],
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _isLoading ? null : _start,
        icon: _isLoading
            ? const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
              strokeWidth: 2, color: Colors.white),
        )
            : const Icon(Icons.assignment_outlined, size: 20),
        label: Text(
          _isLoading
              ? 'Membuka Fasih...'
              : isInProgress
              ? 'Lanjutkan Pendataan di Fasih'
              : 'Mulai Pendataan di Fasih',
          style:
          const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isInProgress
              ? const Color(0xFFFF9800)
              : const Color(0xFF1976D2),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          elevation: 2,
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Helper builders
  // ─────────────────────────────────────────────────────────

  Widget _chipContainer({
    required Color color,
    required Color border,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: child,
    );
  }

  Widget _badge({
    required IconData icon,
    required String label,
    required Color bg,
    required Color fg,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ],
      ),
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Text('$label: ',
              style: TextStyle(fontSize: 13, color: Colors.grey[600])),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w600),
                overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
    ));
  }
}