import 'package:flutter/material.dart';
import 'dart:math' as math;
import '../models/location_fraud_result.dart';
import '../models/sensor_data.dart';

/// Widget untuk menampilkan trust score dalam bentuk gauge
class TrustScoreGauge extends StatelessWidget {
  final double trustScore;
  final double size;
  final bool showLabel;
  final bool animated;

  const TrustScoreGauge({
    super.key,
    required this.trustScore,
    this.size = 120,
    this.showLabel = true,
    this.animated = true,
  });

  Color get _scoreColor {
    if (trustScore >= 0.8) return const Color(0xFF4CAF50);
    if (trustScore >= 0.6) return const Color(0xFFFF9800);
    if (trustScore >= 0.4) return const Color(0xFFF44336);
    return const Color(0xFF9C27B0);
  }

  String get _riskLabel {
    if (trustScore >= 0.8) return 'Terpercaya';
    if (trustScore >= 0.6) return 'Perlu Perhatian';
    if (trustScore >= 0.4) return 'Mencurigakan';
    return 'Sangat Mencurigakan';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: animated
              ? TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: trustScore),
            duration: const Duration(milliseconds: 1000),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) {
              return _buildGauge(value);
            },
          )
              : _buildGauge(trustScore),
        ),
        if (showLabel) ...[
          const SizedBox(height: 8),
          Text(
            _riskLabel,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: _scoreColor,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildGauge(double value) {
    return CustomPaint(
      painter: _GaugePainter(
        score: value,
        color: _scoreColor,
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${(value * 100).toInt()}',
              style: TextStyle(
                fontSize: size * 0.25,
                fontWeight: FontWeight.bold,
                color: _scoreColor,
              ),
            ),
            Text(
              'Trust',
              style: TextStyle(
                fontSize: size * 0.1,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double score;
  final Color color;

  _GaugePainter({required this.score, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 10;

    // Background arc
    final backgroundPaint = Paint()
      ..color = Colors.grey[200]!
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5,
      false,
      backgroundPaint,
    );

    // Score arc
    final scorePaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      math.pi * 0.75,
      math.pi * 1.5 * score,
      false,
      scorePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _GaugePainter oldDelegate) {
    return oldDelegate.score != score || oldDelegate.color != color;
  }
}

/// Widget untuk menampilkan badge risk level
class RiskLevelBadge extends StatelessWidget {
  final RiskLevel riskLevel;
  final bool showIcon;
  final double fontSize;

  const RiskLevelBadge({
    super.key,
    required this.riskLevel,
    this.showIcon = true,
    this.fontSize = 12,
  });

  Color get _backgroundColor {
    switch (riskLevel) {
      case RiskLevel.low:
        return const Color(0xFFE8F5E9);
      case RiskLevel.medium:
        return const Color(0xFFFFF3E0);
      case RiskLevel.high:
        return const Color(0xFFFFEBEE);
      case RiskLevel.critical:
        return const Color(0xFFF3E5F5);
    }
  }

  Color get _textColor {
    switch (riskLevel) {
      case RiskLevel.low:
        return const Color(0xFF4CAF50);
      case RiskLevel.medium:
        return const Color(0xFFFF9800);
      case RiskLevel.high:
        return const Color(0xFFF44336);
      case RiskLevel.critical:
        return const Color(0xFF9C27B0);
    }
  }

  IconData get _icon {
    switch (riskLevel) {
      case RiskLevel.low:
        return Icons.check_circle;
      case RiskLevel.medium:
        return Icons.warning;
      case RiskLevel.high:
        return Icons.error;
      case RiskLevel.critical:
        return Icons.dangerous;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: _backgroundColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(_icon, size: fontSize + 4, color: _textColor),
            const SizedBox(width: 6),
          ],
          Text(
            riskLevel.displayName,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w600,
              color: _textColor,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget untuk menampilkan fraud flag item
class FraudFlagItem extends StatelessWidget {
  final FraudFlag flag;
  final bool expanded;
  final VoidCallback? onTap;

  const FraudFlagItem({
    super.key,
    required this.flag,
    this.expanded = false,
    this.onTap,
  });

  Color get _severityColor {
    if (flag.severity >= 0.8) return const Color(0xFFF44336);
    if (flag.severity >= 0.5) return const Color(0xFFFF9800);
    return const Color(0xFFFFC107);
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: _severityColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      flag.type.displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: _severityColor.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(flag.severity * 100).toInt()}%',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _severityColor,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                flag.description,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[700],
                ),
              ),
              if (expanded && flag.metadata != null) ...[
                const SizedBox(height: 8),
                const Divider(),
                const SizedBox(height: 4),
                ...flag.metadata!.entries.map((entry) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(
                          '${entry.key}: ',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Expanded(
                          child: Text(
                            '${entry.value}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[800],
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Widget untuk menampilkan summary fraud analysis
class FraudAnalysisSummary extends StatelessWidget {
  final LocationFraudResult result;
  final bool compact;

  const FraudAnalysisSummary({
    super.key,
    required this.result,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompactView();
    }
    return _buildFullView(context);
  }

  Widget _buildCompactView() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: result.isFraudulent
            ? const Color(0xFFFFEBEE)
            : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: result.isFraudulent
              ? const Color(0xFFF44336)
              : const Color(0xFF4CAF50),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            result.isFraudulent
                ? Icons.warning_amber_rounded
                : Icons.verified_rounded,
            color: result.isFraudulent
                ? const Color(0xFFF44336)
                : const Color(0xFF4CAF50),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.isFraudulent ? 'Lokasi Mencurigakan' : 'Lokasi Valid',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: result.isFraudulent
                        ? const Color(0xFFF44336)
                        : const Color(0xFF4CAF50),
                  ),
                ),
                Text(
                  'Trust Score: ${(result.trustScore * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          if (result.flags.isNotEmpty)
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
              ),
              child: Text(
                '${result.flags.length}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: result.isFraudulent
                      ? const Color(0xFFF44336)
                      : const Color(0xFF4CAF50),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFullView(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                TrustScoreGauge(
                  trustScore: result.trustScore,
                  size: 80,
                  showLabel: false,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RiskLevelBadge(riskLevel: result.riskLevel),
                      const SizedBox(height: 8),
                      Text(
                        result.isFraudulent
                            ? '⚠️ Lokasi terdeteksi mencurigakan'
                            : '✅ Lokasi terverifikasi',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${result.flags.length} flag terdeteksi',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            if (result.flags.isNotEmpty) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),
              const Text(
                'Detail Temuan:',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 8),
              ...result.flags.map((flag) => FraudFlagItem(flag: flag)),
            ],

            // Analysis details
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _buildAnalysisDetails(),
          ],
        ),
      ),
    );
  }

  Widget _buildAnalysisDetails() {
    final detail = result.analysisDetail;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Detail Analisis:',
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (detail.speedKmh != null)
              _buildDetailChip(
                'Kecepatan',
                '${detail.speedKmh!.toStringAsFixed(1)} km/jam',
                detail.isSpeedValid ? Colors.green : Colors.red,
              ),
            if (detail.gpsAccuracy != null)
              _buildDetailChip(
                'Akurasi',
                '${detail.gpsAccuracy!.toStringAsFixed(1)}m',
                detail.isAccuracyValid ? Colors.green : Colors.red,
              ),
            if (detail.distanceFromPrevious != null)
              _buildDetailChip(
                'Jarak',
                '${detail.distanceFromPrevious!.toStringAsFixed(0)}m',
                Colors.blue,
              ),
            _buildDetailChip(
              'Jam Kerja',
              detail.isWithinWorkingHours ? 'Ya' : 'Tidak',
              detail.isWithinWorkingHours ? Colors.green : Colors.orange,
            ),
            _buildDetailChip(
              'Hari Kerja',
              detail.isWeekday ? 'Ya' : 'Tidak',
              detail.isWeekday ? Colors.green : Colors.orange,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDetailChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Widget untuk menampilkan device security status
class DeviceSecurityStatus extends StatelessWidget {
  final DeviceSecurityInfo securityInfo;

  const DeviceSecurityStatus({
    super.key,
    required this.securityInfo,
  });

  @override
  Widget build(BuildContext context) {
    final score = securityInfo.securityScore;
    final isSecure = score >= 0.7;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  isSecure ? Icons.security : Icons.warning,
                  color: isSecure
                      ? const Color(0xFF4CAF50)
                      : const Color(0xFFF44336),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isSecure ? 'Perangkat Aman' : 'Perangkat Berisiko',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: isSecure
                              ? const Color(0xFF4CAF50)
                              : const Color(0xFFF44336),
                        ),
                      ),
                      Text(
                        'Security Score: ${(score * 100).toInt()}%',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            _buildCheckItem(
              'Mock Location',
              !securityInfo.isMockLocationEnabled,
              securityInfo.isMockLocationEnabled
                  ? 'Fake GPS terdeteksi aktif'
                  : 'Tidak terdeteksi',
            ),
            _buildCheckItem(
              'Root/Jailbreak',
              !securityInfo.isDeviceRooted,
              securityInfo.isDeviceRooted
                  ? 'Perangkat di-root'
                  : 'Tidak di-root',
            ),
            _buildCheckItem(
              'Emulator',
              !securityInfo.isEmulator,
              securityInfo.isEmulator
                  ? 'Berjalan di emulator'
                  : 'Perangkat fisik',
            ),
            if (securityInfo.deviceModel != null)
              _buildInfoItem('Perangkat', securityInfo.deviceModel!),
            if (securityInfo.osVersion != null)
              _buildInfoItem('OS', securityInfo.osVersion!),
          ],
        ),
      ),
    );
  }

  Widget _buildCheckItem(String label, bool isOk, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            isOk ? Icons.check_circle : Icons.cancel,
            color: isOk ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w500,
                    fontSize: 14,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoItem(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          const SizedBox(width: 32),
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}