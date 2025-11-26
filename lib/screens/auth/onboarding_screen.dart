import 'package:flutter/material.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'login_method_screen.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

  final List<OnboardingContent> _onboardingData = [
    OnboardingContent(
      image: 'assets/images/onboarding1.png',
      title: 'Selamat Datang di SINTONG',
      description:
      'Aplikasi pengumpulan data resmi milik Badan Pusat Statistik. Satu platform terpadu untuk berbagai kebutuhan survei dan sensus nasional.',
    ),
    OnboardingContent(
      image: 'assets/images/onboarding2.png',
      title: 'Pemantauan Real-time & Akurat',
      description:
      'Data hasil wawancara dapat dipantau secara langsung dengan tingkat akurasi tinggi. Proses validasi otomatis memastikan kualitas data terbaik.',
    ),
    OnboardingContent(
      image: 'assets/images/onboarding3.png',
      title: 'Fleksibel Online & Offline',
      description:
      'Aplikasi dapat beroperasi dalam mode online maupun offline. Data tersimpan aman di perangkat dan dapat dikirim saat terhubung kembali ke internet.',
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                onPageChanged: (index) {
                  setState(() => _currentPage = index);
                },
                itemCount: _onboardingData.length,
                itemBuilder: (context, index) {
                  return _buildOnboardingPage(_onboardingData[index]);
                },
              ),
            ),

            // Page Indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: SmoothPageIndicator(
                controller: _pageController,
                count: _onboardingData.length,
                effect: const ExpandingDotsEffect(
                  activeDotColor: Color(0xFF2196F3),
                  dotColor: Color(0xFFE0E0E0),
                  dotHeight: 8,
                  dotWidth: 8,
                  expansionFactor: 3,
                  spacing: 8,
                ),
              ),
            ),

            // Bottom Section with Login Button and Privacy Link
            Padding(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                bottom: 24 + MediaQuery.of(context).padding.bottom,
              ),
              child: Column(
                children: [
                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const LoginMethodScreen(),
                          ),
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0B6BA8),
                        foregroundColor: Colors.white,
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Login Sekarang',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Privacy Policy Link
                  RichText(
                    textAlign: TextAlign.center,
                    text: TextSpan(
                      text: 'Dengan melakukan login, anda setuju dengan',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                      children: [
                        TextSpan(
                          text: 'Kebijakan Privasikami',
                          style: TextStyle(
                            fontSize: 12,
                            color: const Color(0xFF0B6BA8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
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

  Widget _buildOnboardingPage(OnboardingContent content) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Illustration Image
          Container(
            width: 300,
            height: 300,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(24),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Image.asset(
              content.image,
              fit: BoxFit.contain,
              errorBuilder: (context, error, stackTrace) {
                // Fallback icon if image not found
                return _buildFallbackIllustration(content);
              },
            ),
          ),

          const SizedBox(height: 48),

          // Title
          Text(
            content.title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF212121),
            ),
          ),

          const SizedBox(height: 16),

          // Description
          Text(
            content.description,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              height: 1.5,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFallbackIllustration(OnboardingContent content) {
    IconData icon;
    Color color;

    if (content.title.contains('Selamat Datang')) {
      icon = Icons.assignment_outlined;
      color = const Color(0xFF2196F3);
    } else if (content.title.contains('Real-time')) {
      icon = Icons.check_circle_outline;
      color = const Color(0xFF4CAF50);
    } else {
      icon = Icons.cloud_sync_outlined;
      color = const Color(0xFF00BCD4);
    }

    return Center(
      child: Container(
        width: 120,
        height: 120,
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          size: 64,
          color: color,
        ),
      ),
    );
  }
}

class OnboardingContent {
  final String image;
  final String title;
  final String description;

  OnboardingContent({
    required this.image,
    required this.title,
    required this.description,
  });
}