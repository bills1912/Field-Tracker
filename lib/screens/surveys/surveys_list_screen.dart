import 'package:field_tracker/screens/surveys/survey_detail_screen.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/survey_provider.dart';
import '../../providers/network_provider.dart';
import '../../models/survey.dart';
import '../../models/user.dart';

class SurveysListScreen extends StatefulWidget {
  const SurveysListScreen({super.key});

  @override
  State<SurveysListScreen> createState() => _SurveysListScreenState();
}

class _SurveysListScreenState extends State<SurveysListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSurveys();
    });
  }

  Future<void> _loadSurveys() async {
    await context.read<SurveyProvider>().loadSurveys();
  }

  String _getRegionIcon(String regionLevel) {
    switch (regionLevel.toLowerCase()) {
      case 'national':
        return '🌍';
      case 'provincial':
        return '🏛️';
      case 'regency':
        return '🏙️';
      default:
        return '📍';
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return const Color(0xFFF44336);
      case 'in_progress':
        return const Color(0xFFFF9800);
      case 'completed':
        return const Color(0xFF4CAF50);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final surveyProvider = context.watch<SurveyProvider>();
    final networkProvider = context.watch<NetworkProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hello, ${user?.username ?? ''}! 👋'),
            Text(
              '${surveyProvider.surveys.length} Surveys Available',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: networkProvider.isConnected ? _loadSurveys : null,
          ),
        ],
      ),
      body: surveyProvider.isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadSurveys,
              child: surveyProvider.surveys.isEmpty
                  ? _buildEmptyState(user?.role)
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: surveyProvider.surveys.length,
                      itemBuilder: (context, index) {
                        final survey = surveyProvider.surveys[index];
                        final stats = surveyProvider.surveyStats[survey.id];
                        final isSelected =
                            surveyProvider.selectedSurveyId == survey.id;

                        return _buildSurveyCard(
                          survey,
                          stats,
                          isSelected,
                          surveyProvider,
                        );
                      },
                    ),
            ),
    );
  }

  Widget _buildEmptyState(UserRole? role) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.poll, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text(
            'No surveys available',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          if (role == UserRole.admin || role == UserRole.supervisor) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Create First Survey'),
              onPressed: () {
                // Navigate to create survey screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Create survey feature - To be implemented')),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSurveyCard(
    Survey survey,
    dynamic stats,
    bool isSelected,
    SurveyProvider provider,
  ) {
    return Card(
      elevation: isSelected ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Color(0xFF4CAF50), width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: () {
          provider.setSelectedSurvey(survey);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => SurveyDetailScreen(survey: survey),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    _getRegionIcon(survey.regionLevel),
                    style: const TextStyle(fontSize: 32),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          survey.title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${survey.regionLevel.toUpperCase()} - ${survey.regionName}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF2196F3),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (survey.description != null) ...[
                          const SizedBox(height: 4),
                          Text(
                            survey.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle, color: Color(0xFF4CAF50), size: 24),
                ],
              ),
              if (stats != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8F9FA),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildStatItem('Total', stats.totalRespondents.toString(),
                          const Color(0xFF333333)),
                      _buildStatItem('Progress', stats.inProgress.toString(),
                          const Color(0xFFFF9800)),
                      _buildStatItem('Done', stats.completed.toString(),
                          const Color(0xFF4CAF50)),
                      _buildStatItem('Rate', '${stats.completionRate.toStringAsFixed(0)}%',
                          const Color(0xFF2196F3)),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.calendar_today, size: 14, color: Colors.grey),
                      const SizedBox(width: 6),
                      Text(
                        '${DateFormat('MMM d').format(survey.startDate)} - ${DateFormat('MMM d, y').format(survey.endDate)}',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                  if (survey.isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Active',
                        style: TextStyle(
                          fontSize: 12,
                          color: Color(0xFF4CAF50),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color valueColor) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Colors.grey),
        ),
      ],
    );
  }
}