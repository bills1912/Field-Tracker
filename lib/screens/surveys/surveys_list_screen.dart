import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/auth_provider.dart';
import '../../providers/survey_provider.dart';
import '../../providers/network_provider.dart';
import '../../models/survey.dart';
import '../../models/user.dart';
import '../../models/respondent.dart';
import 'survey_detail_screen.dart';
import 'all_surveys_screen.dart';
import '../map/survey_map_screen.dart';

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

  Future<void> _togglePin(Survey survey) async {
    final surveyProvider = context.read<SurveyProvider>();
    await surveyProvider.togglePinSurvey(survey.id);
  }

  /// Navigate to map for a specific survey
  void _navigateToMap(Survey survey, {RespondentStatus? statusFilter}) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SurveyMapScreen(
          survey: survey,
          statusFilter: statusFilter,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.watch<AuthProvider>().user;
    final surveyProvider = context.watch<SurveyProvider>();
    final networkProvider = context.watch<NetworkProvider>();

    // Get pinned surveys only
    final pinnedSurveys = surveyProvider.pinnedSurveys;

    return Scaffold(
      body: Column(
        children: [
          // Custom Header
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Hello, ${user?.username ?? ''}! 👋',
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${surveyProvider.surveys.length} Surveys Available',
                            style: const TextStyle(
                              fontSize: 14,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh, color: Colors.white),
                      tooltip: 'Refresh',
                      onPressed:
                      networkProvider.isConnected ? _loadSurveys : null,
                    ),
                  ],
                ),
              ),
            ),
          ),

          // Body Content
          Expanded(
            child: surveyProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : RefreshIndicator(
              onRefresh: _loadSurveys,
              child: pinnedSurveys.isEmpty
                  ? _buildEmptyState(user?.role)
                  : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: pinnedSurveys.length +
                    1, // +1 for "View All" button
                itemBuilder: (context, index) {
                  // Show "View All Surveys" button at the end
                  if (index == pinnedSurveys.length) {
                    return _buildViewAllButton();
                  }

                  final survey = pinnedSurveys[index];
                  final stats =
                  surveyProvider.surveyStats[survey.id];
                  final isSelected =
                      surveyProvider.selectedSurveyId == survey.id;

                  return _buildSurveyCard(
                    survey,
                    stats,
                    isSelected,
                    surveyProvider,
                    isPinned: true,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(UserRole? role) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF2196F3).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.push_pin_outlined,
                size: 64,
                color: Color(0xFF2196F3),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No Pinned Surveys',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Color(0xFF333333),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Pin your favorite surveys to see them here',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              icon: const Icon(Icons.list, size: 24),
              label: const Text(
                'View All Surveys',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2196F3),
                foregroundColor: Colors.white,
                padding:
                const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const AllSurveysScreen(),
                  ),
                );
              },
            ),
            if (role == UserRole.admin || role == UserRole.supervisor) ...[
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Create Survey'),
                style: OutlinedButton.styleFrom(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content:
                      Text('Create survey feature - To be implemented'),
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildViewAllButton() {
    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 16),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AllSurveysScreen(),
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFF2196F3),
              width: 2,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.list,
                color: Color(0xFF2196F3),
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Lihat Semua Survei',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF2196F3),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF2196F3),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Consumer<SurveyProvider>(
                  builder: (context, provider, _) {
                    return Text(
                      '${provider.surveys.length}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSurveyCard(
      Survey survey,
      dynamic stats,
      bool isSelected,
      SurveyProvider provider, {
        required bool isPinned,
      }) {
    return Card(
      elevation: isSelected ? 4 : 2,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? const BorderSide(color: Color(0xFF4CAF50), width: 2)
            : BorderSide.none,
      ),
      child: Column(
        children: [
          // Main card content - tap to go to detail
          InkWell(
            onTap: () {
              provider.setSelectedSurvey(survey);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SurveyDetailScreen(survey: survey),
                ),
              );
            },
            borderRadius:
            const BorderRadius.vertical(top: Radius.circular(12)),
            child: Stack(
              children: [
                Padding(
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
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                      // Stats grid - clickable to filter map
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
                              _buildStatItem(
                                'Total',
                                stats.totalRespondents.toString(),
                                const Color(0xFF333333),
                                onTap: () => _navigateToMap(survey),
                              ),
                              _buildStatItem(
                                'Pending',
                                stats.pending.toString(),
                                const Color(0xFFF44336),
                                onTap: () => _navigateToMap(
                                  survey,
                                  statusFilter: RespondentStatus.pending,
                                ),
                              ),
                              _buildStatItem(
                                'Progress',
                                stats.inProgress.toString(),
                                const Color(0xFFFF9800),
                                onTap: () => _navigateToMap(
                                  survey,
                                  statusFilter: RespondentStatus.in_progress,
                                ),
                              ),
                              _buildStatItem(
                                'Done',
                                stats.completed.toString(),
                                const Color(0xFF4CAF50),
                                onTap: () => _navigateToMap(
                                  survey,
                                  statusFilter: RespondentStatus.completed,
                                ),
                              ),
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
                              const Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.grey,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '${DateFormat('MMM d').format(survey.startDate)} - ${DateFormat('MMM d, y').format(survey.endDate)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                          if (survey.isActive)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 4,
                              ),
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
                // Pin button
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => _togglePin(survey),
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isPinned
                              ? const Color(0xFF2196F3)
                              : Colors.white,
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Icon(
                          isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                          size: 20,
                          color:
                          isPinned ? Colors.white : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),
                ),
                // Selected indicator
                if (isSelected)
                  const Positioned(
                    top: 8,
                    left: 8,
                    child: Icon(
                      Icons.check_circle,
                      color: Color(0xFF4CAF50),
                      size: 24,
                    ),
                  ),
              ],
            ),
          ),
          // Navigate to Map button
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: const Color(0xFF2196F3).withOpacity(0.05),
              borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(12)),
              border: Border(
                top: BorderSide(
                  color: Colors.grey.withOpacity(0.2),
                  width: 1,
                ),
              ),
            ),
            child: InkWell(
              onTap: () => _navigateToMap(survey),
              borderRadius:
              const BorderRadius.vertical(bottom: Radius.circular(12)),
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.map,
                      color: Color(0xFF2196F3),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Lihat Lokasi Responden di Map',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF2196F3),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.arrow_forward_ios,
                      color: Color(0xFF2196F3),
                      size: 14,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(
      String label,
      String value,
      Color valueColor, {
        VoidCallback? onTap,
      }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
                const SizedBox(width: 2),
                Icon(
                  Icons.touch_app,
                  size: 10,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}