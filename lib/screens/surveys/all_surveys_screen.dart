import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/survey_provider.dart';
import '../../providers/network_provider.dart';
import '../../models/survey.dart';
import 'survey_detail_screen.dart';

class AllSurveysScreen extends StatefulWidget {
  const AllSurveysScreen({super.key});

  @override
  State<AllSurveysScreen> createState() => _AllSurveysScreenState();
}

class _AllSurveysScreenState extends State<AllSurveysScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

    // Show feedback
    final isPinned = surveyProvider.isPinned(survey.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                isPinned ? Icons.push_pin : Icons.push_pin_outlined,
                color: Colors.white,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  isPinned
                      ? 'Survey pinned to home'
                      : 'Survey unpinned from home',
                ),
              ),
            ],
          ),
          backgroundColor: isPinned
              ? const Color(0xFF4CAF50)
              : Colors.grey[700],
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final surveyProvider = context.watch<SurveyProvider>();
    final networkProvider = context.watch<NetworkProvider>();

    // Filter surveys based on search query
    final filteredSurveys = _searchQuery.isEmpty
        ? surveyProvider.surveys
        : surveyProvider.surveys.where((survey) {
      return survey.title.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          survey.regionName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (survey.description?.toLowerCase().contains(_searchQuery.toLowerCase()) ?? false);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('All Surveys'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: networkProvider.isConnected ? _loadSurveys : null,
          ),
        ],
      ),
      body: Column(
        children: [
          // Search bar
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.white,
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Cari survei...',
                prefixIcon: const Icon(Icons.search, color: Color(0xFF2196F3)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
                    : null,
                filled: true,
                fillColor: const Color(0xFFF5F5F5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),

          // Survey count indicator
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: const Color(0xFFF8F9FA),
            child: Row(
              children: [
                Icon(
                  Icons.list_alt,
                  size: 20,
                  color: Colors.grey[700],
                ),
                const SizedBox(width: 8),
                Text(
                  '${filteredSurveys.length} surveys',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Text(
                  '${surveyProvider.pinnedSurveys.length} pinned',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Color(0xFF2196F3),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          // Surveys list
          Expanded(
            child: surveyProvider.isLoading
                ? const Center(child: CircularProgressIndicator())
                : filteredSurveys.isEmpty
                ? _buildEmptyState()
                : RefreshIndicator(
              onRefresh: _loadSurveys,
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: filteredSurveys.length,
                itemBuilder: (context, index) {
                  final survey = filteredSurveys[index];
                  final stats = surveyProvider.surveyStats[survey.id];
                  final isSelected =
                      surveyProvider.selectedSurveyId == survey.id;
                  final isPinned = surveyProvider.isPinned(survey.id);

                  return _buildSurveyCard(
                    survey,
                    stats,
                    isSelected,
                    surveyProvider,
                    isPinned: isPinned,
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            _searchQuery.isEmpty ? Icons.poll_outlined : Icons.search_off,
            size: 64,
            color: Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            _searchQuery.isEmpty
                ? 'No surveys available'
                : 'No surveys found',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          if (_searchQuery.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Try different keywords',
              style: TextStyle(fontSize: 14, color: Colors.grey[400]),
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
                      const SizedBox(width: 48), // Space for pin button
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
                          _buildStatItem(
                            'Total',
                            stats.totalRespondents.toString(),
                            const Color(0xFF333333),
                          ),
                          _buildStatItem(
                            'Progress',
                            stats.inProgress.toString(),
                            const Color(0xFFFF9800),
                          ),
                          _buildStatItem(
                            'Done',
                            stats.completed.toString(),
                            const Color(0xFF4CAF50),
                          ),
                          _buildStatItem(
                            'Rate',
                            '${stats.completionRate.toStringAsFixed(0)}%',
                            const Color(0xFF2196F3),
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
                      border: Border.all(
                        color: isPinned
                            ? const Color(0xFF2196F3)
                            : Colors.grey[300]!,
                        width: 2,
                      ),
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
                      color: isPinned ? Colors.white : Colors.grey[600],
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