import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/survey.dart';
import '../../models/survey_stats.dart';
import '../../models/respondent.dart';
import '../../providers/survey_provider.dart';
import '../../services/api_service.dart';
import '../../providers/network_provider.dart';
import '../map/survey_map_screen.dart';

class SurveyDetailScreen extends StatefulWidget {
  final Survey survey;

  const SurveyDetailScreen({super.key, required this.survey});

  @override
  State<SurveyDetailScreen> createState() => _SurveyDetailScreenState();
}

class _SurveyDetailScreenState extends State<SurveyDetailScreen> {
  SurveyStats? _stats;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    setState(() => _isLoading = true);

    try {
      final stats = await ApiService.instance.getSurveyStats(widget.survey.id);
      setState(() => _stats = stats);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading stats: $e')),
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// Navigate to map with specific filter
  void _navigateToMap({RespondentStatus? statusFilter}) {
    context.read<SurveyProvider>().setSelectedSurvey(widget.survey);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SurveyMapScreen(
          survey: widget.survey,
          statusFilter: statusFilter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final networkProvider = context.watch<NetworkProvider>();
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.survey.title,
          style: const TextStyle(fontSize: 18),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: networkProvider.isConnected ? _loadStats : null,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          // Scrollable content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildInfoCard(),
                  const SizedBox(height: 16),
                  if (_stats != null) _buildStatsGrid(),
                  const SizedBox(height: 16),
                  if (_stats != null) _buildProgressSection(),
                  // Extra padding at bottom for safe scrolling
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
          // Fixed bottom button - always visible
          Container(
            width: double.infinity,
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 12,
              bottom: 12 + bottomPadding,
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: _buildNavigateToMapButton(),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.location_on, color: Color(0xFF2196F3)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.survey.regionLevel.toUpperCase()} - ${widget.survey.regionName}',
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF2196F3),
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            if (widget.survey.description != null) ...[
              const SizedBox(height: 16),
              Text(
                widget.survey.description!,
                style: TextStyle(
                    fontSize: 14, color: Colors.grey[600], height: 1.4),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Start Date',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, y').format(widget.survey.startDate),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('End Date',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[600])),
                      const SizedBox(height: 4),
                      Text(
                        DateFormat('MMM d, y').format(widget.survey.endDate),
                        style: const TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // First row - Total and Pending
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'Total',
                _stats!.totalRespondents.toString(),
                Icons.assignment,
                const Color(0xFF2196F3),
                const Color(0xFFE3F2FD),
                onTap: () => _navigateToMap(),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Pending',
                _stats!.pending.toString(),
                Icons.pending,
                const Color(0xFFF44336),
                const Color(0xFFFFEBEE),
                onTap: () => _navigateToMap(statusFilter: RespondentStatus.pending),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        // Second row - In Progress and Completed
        Row(
          children: [
            Expanded(
              child: _buildStatCard(
                'In Progress',
                _stats!.inProgress.toString(),
                Icons.hourglass_empty,
                const Color(0xFFFF9800),
                const Color(0xFFFFF3E0),
                onTap: () => _navigateToMap(statusFilter: RespondentStatus.in_progress),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatCard(
                'Completed',
                _stats!.completed.toString(),
                Icons.check_circle,
                const Color(0xFF4CAF50),
                const Color(0xFFE8F5E9),
                onTap: () => _navigateToMap(statusFilter: RespondentStatus.completed),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatCard(
      String label,
      String value,
      IconData icon,
      Color iconColor,
      Color bgColor, {
        VoidCallback? onTap,
      }) {
    return Card(
      color: bgColor,
      elevation: 0,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 28, color: iconColor),
              const SizedBox(height: 8),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF333333),
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      label,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.touch_app,
                    size: 12,
                    color: Colors.grey[500],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Survey Progress',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: _stats!.completionRate / 100,
                minHeight: 12,
                backgroundColor: const Color(0xFFE0E0E0),
                valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xFF4CAF50)),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${_stats!.completionRate.toStringAsFixed(1)}% Complete',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavigateToMapButton() {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _navigateToMap(),
        icon: const Icon(Icons.map, size: 24),
        label: const Text(
          'Lihat Lokasi Responden di Map',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF2196F3),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 2,
        ),
      ),
    );
  }
}