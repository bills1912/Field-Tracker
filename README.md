# Field Tracker - Smart Census Data Collection System

<div align="center">
  <img src="assets/icons/icon.png" alt="Field Tracker Logo" width="120"/>

[![Flutter](https://img.shields.io/badge/Flutter-3.10.1+-02569B?style=for-the-badge&logo=flutter)](https://flutter.dev)
[![Dart](https://img.shields.io/badge/Dart-3.10.1+-0175C2?style=for-the-badge&logo=dart)](https://dart.dev)
[![License](https://img.shields.io/badge/License-MIT-green?style=for-the-badge)](LICENSE)

**Real-time GPS Tracking & Fraud Detection for Field Survey Enumerators**

[Features](#features) • [Installation](#installation) • [Architecture](#architecture) • [Documentation](#documentation)
</div>

---

## 📋 Overview

Field Tracker is an advanced Flutter mobile application designed for census and survey data collection in the field. The app provides real-time GPS tracking, intelligent fraud detection, offline-first capabilities, and AI-powered assistance for field enumerators (petugas lapangan). Built specifically for the Indonesian statistical field operations, it ensures data integrity and authenticity through comprehensive location monitoring and sensor-based fraud prevention.

### Key Highlights

- 📍 **Real-time GPS Tracking** - Automatic location tracking every 2 minutes with offline support
- 🛡️ **Advanced Fraud Detection** - ML-powered detection of fake GPS, emulators, and suspicious patterns
- 🤖 **AI Assistant (Gemini)** - Context-aware help for survey definitions and field operations
- 🗺️ **Offline Maps** - Download map tiles for offline fieldwork
- 📊 **Survey Management** - Multi-survey support with respondent tracking
- 💬 **Real-time Communication** - Chat system between enumerators, supervisors, and admins
- 🌙 **Offline-First Architecture** - Works seamlessly without internet connection
- 🔐 **Automatic Security** - Location tracking and fraud detection cannot be disabled

---

## ✨ Features

### 🎯 Core Features

#### 1. **Real-time GPS Tracking**
- Automatic location capture every 2 minutes
- Background tracking with WorkManager
- Real-time location streaming
- Battery-efficient tracking
- Offline location caching with auto-sync
- Location history with timestamps

#### 2. **Advanced Fraud Detection System**
- **Device Security Checks**
    - Mock location / Fake GPS detection
    - Root/Jailbreak detection
    - Emulator detection
    - Known fake GPS apps scanning

- **Movement Pattern Analysis**
    - Impossible speed detection (teleportation)
    - Zigzag pattern detection
    - Location jumping detection
    - Stationary time monitoring

- **Sensor Consistency Validation**
    - Accelerometer data analysis
    - Gyroscope consistency checks
    - Movement vs GPS correlation

- **Contextual Validation**
    - Working hours compliance
    - Weekend activity detection
    - Altitude consistency checks
    - GPS accuracy anomaly detection

- **Trust Score System**
    - Real-time trust score (0-1)
    - Risk level classification (Low/Medium/High/Critical)
    - Detailed fraud flags with severity ratings
    - Historical fraud tracking

#### 3. **AI-Powered Assistant (Gemini)**
- Survey definition explanations
- Data validation logic checks
- Technical field problem solving
- Context-aware responses
- Offline-ready FAQ system
- Professional survey terminology

#### 4. **Survey & Respondent Management**
- Multi-survey support with GeoJSON boundaries
- Respondent status tracking (Pending/In Progress/Completed)
- Pin favorite surveys for quick access
- Survey statistics dashboard
- Region-based survey allocation
- Supervisor and enumerator assignment

#### 5. **Offline-First Architecture**
- **Offline Maps**
    - Download map tiles for specific regions
    - Support for OSM and Google satellite imagery
    - Cache management with size tracking
    - On-the-fly tile caching

- **Offline Data Sync**
    - Local SQLite database
    - Automatic background sync when online
    - Pending data counter
    - Batch sync operations
    - Conflict resolution

- **Cached Data**
    - Surveys and respondent lists
    - Location history
    - Messages and chat history
    - Survey statistics
    - FAQ database

#### 6. **Communication System**
- **AI Chat**
    - Gemini-powered survey assistant
    - Definition lookups
    - Field problem solutions

- **Supervisor Messages**
    - Two-way messaging with supervisors
    - Message read receipts
    - Answered/Unanswered tracking
    - Conversation preview

- **Admin Broadcasts**
    - Mass announcements
    - Role-based targeting
    - Survey-specific messages

### 🔒 Security & Compliance

- **Mandatory Tracking** - Cannot be disabled by users
- **Auto-start on Login** - Tracking begins automatically
- **Session Management** - Single active session per device
- **Device Fingerprinting** - Track active devices
- **Fraud Alerts** - Real-time suspicious activity detection

### 🗺️ Map Features

- Interactive map with respondent markers
- User location indicator
- GeoJSON polygon overlay for survey regions
- Distance calculation to respondents
- Multiple base map options (OSM, Satellite, Hybrid)
- Offline map tile storage

### 👤 User Roles

1. **Enumerator**
    - Add and manage respondents
    - View assigned surveys
    - Chat with AI and supervisor
    - View own location history

2. **Supervisor**
    - View all enumerator locations
    - Respond to enumerator messages
    - Monitor survey progress
    - Access fraud detection reports

3. **Admin**
    - Create and manage surveys
    - Assign surveys to supervisors/enumerators
    - Send broadcast messages
    - View comprehensive fraud analytics
    - Manage all users

---

## 🏗️ Architecture

### Tech Stack

#### Frontend (Flutter)
```
field_tracker/
├── lib/
│   ├── models/              # Data models
│   │   ├── user.dart
│   │   ├── survey.dart
│   │   ├── respondent.dart
│   │   ├── location_tracking.dart
│   │   ├── sensor_data.dart
│   │   ├── location_fraud_result.dart
│   │   └── message.dart
│   ├── providers/           # State management (Provider)
│   │   ├── auth_provider.dart
│   │   ├── survey_provider.dart
│   │   ├── location_provider.dart
│   │   ├── fraud_detection_provider.dart
│   │   └── network_provider.dart
│   ├── services/            # Business logic
│   │   ├── api_service.dart
│   │   ├── location_service.dart
│   │   ├── enhanced_location_service.dart
│   │   ├── location_fraud_detection_service.dart
│   │   ├── sensor_collector_service.dart
│   │   ├── gemini_ai_service.dart
│   │   ├── storage_service.dart
│   │   ├── sync_service.dart
│   │   └── offline_map_service.dart
│   ├── screens/             # UI screens
│   │   ├── auth/
│   │   │   ├── login_screen.dart
│   │   │   └── onboarding_screen.dart
│   │   ├── home/
│   │   │   └── home_screen.dart
│   │   ├── respondent/
│   │   │   ├── add_respondent_screen.dart
│   │   │   └── respondent_list_screen.dart
│   │   ├── chat/
│   │   │   ├── chat_router.dart
│   │   │   ├── ai_chat_screen.dart
│   │   │   └── supervisor_chat_screen.dart
│   │   ├── profile/
│   │   │   └── profile_screen.dart
│   │   └── splash_screen.dart
│   ├── widgets/             # Reusable components
│   │   └── fraud_detection_widgets.dart
│   └── main.dart
```

#### Backend Integration
- **API Base URL**: `https://survey-enum-tracker-1.onrender.com/api`
- **Authentication**: JWT Bearer tokens
- **Data Format**: JSON
- **Storage**: SQLite + SharedPreferences + Secure Storage

### State Management

The app uses **Provider** for state management with multiple specialized providers:

1. **AuthProvider** - User authentication and session
2. **SurveyProvider** - Survey selection and caching
3. **LocationProvider** - GPS tracking and location data
4. **FraudDetectionProvider** - Fraud monitoring and analysis
5. **NetworkProvider** - Connectivity and auto-sync

### Data Models

#### Core Models
```dart
- User                    # User account with role
- Survey                  # Survey configuration with GeoJSON
- Respondent              # Survey respondent data
- LocationTracking        # Basic GPS location
- EnhancedLocationTracking # Location + sensors + fraud score
- SensorData              # Accelerometer, gyroscope, magnetometer
- LocationFraudResult     # Fraud analysis result
- DeviceSecurityInfo      # Device security status
- Message                 # Chat messages
- ChatSession             # Message grouping
- FAQ                     # Frequently asked questions
```

#### Enums
```dart
- UserRole               # admin, supervisor, enumerator
- RespondentStatus       # pending, in_progress, completed
- MessageType            # ai, supervisor, broadcast
- FraudType              # mockLocation, impossibleSpeed, etc.
- RiskLevel              # low, medium, high, critical
- MovementPattern        # normal, stationary, walking, driving, etc.
```

---

## 🚀 Installation

### Prerequisites

- Flutter SDK 3.10.1 or higher
- Dart SDK 3.10.1 or higher
- Android Studio / VS Code with Flutter extensions
- Physical Android device (for GPS and sensor testing)
- Gemini API Key (for AI assistant)

### Setup Steps

1. **Clone the repository**
   ```bash
   git clone <repository-url>
   cd field_tracker
   ```

2. **Install dependencies**
   ```bash
   flutter pub get
   ```

3. **Configure Environment Variables**

   Create a `.env` file in the project root:
   ```env
   GEMINI_API_KEY=your_gemini_api_key_here
   ```

4. **Configure Backend URL** (if needed)

   Update `lib/services/api_service.dart`:
   ```dart
   static const String baseUrl = 'YOUR_BACKEND_URL/api';
   ```

5. **Run the app**
   ```bash
   # Debug mode
   flutter run
   
   # Release mode
   flutter run --release
   ```

### Building for Production

**Android APK:**
```bash
flutter build apk --release
```

**Android App Bundle:**
```bash
flutter build appbundle --release
```

**iOS:**
```bash
flutter build ios --release
```

---

## 🔧 Configuration

### API Configuration

The app connects to the backend API at:
```
https://survey-enum-tracker-1.onrender.com/api
```

Update in `lib/services/api_service.dart` if needed.

### Fraud Detection Configuration

Customize fraud detection thresholds in `lib/services/location_fraud_detection_service.dart`:

```dart
FraudDetectionConfig(
  maxPossibleSpeedKmh: 200.0,      // Teleportation threshold
  maxRealisticSpeedKmh: 120.0,     // Suspicious speed threshold
  minRealisticAccuracy: 1.0,       // Fake GPS threshold
  maxAcceptableAccuracy: 100.0,    // Poor signal threshold
  zigzagThreshold: 0.7,            // Movement pattern threshold
  maxAllowedJumps: 2,              // Location jump threshold
  maxStationaryMinutes: 120,       // Max stationary time
  workingHoursStart: 6,            // 6 AM
  workingHoursEnd: 22,             // 10 PM
  fraudThreshold: 0.5,             // Trust score threshold
)
```

### Tracking Intervals

Adjust in `lib/services/enhanced_location_service.dart`:

```dart
// Real-time UI updates
interval: 5000,        // 5 seconds
distanceFilter: 5,     // 5 meters

// Periodic tracking
Duration(minutes: 2)   // Every 2 minutes
```

### Gemini AI Configuration

Initialize in `lib/services/gemini_ai_service.dart`:

```dart
void initialize() {
  final String apiKey = dotenv.env['GEMINI_API_KEY'] ?? "";
  _model = GenerativeModel(
    model: 'gemini-2.5-flash',
    apiKey: apiKey,
  );
}
```

---

## 📱 Screenshots

<div align="center">
  <img src="screenshots/splash.png" width="200" alt="Splash Screen"/>
  <img src="screenshots/login.png" width="200" alt="Login Screen"/>
  <img src="screenshots/home.png" width="200" alt="Home Dashboard"/>
  <img src="screenshots/map.png" width="200" alt="Map View"/>
</div>

<div align="center">
  <img src="screenshots/respondent.png" width="200" alt="Add Respondent"/>
  <img src="screenshots/chat.png" width="200" alt="AI Chat"/>
  <img src="screenshots/fraud.png" width="200" alt="Fraud Detection"/>
  <img src="screenshots/profile.png" width="200" alt="Profile"/>
</div>

---

## 📌 API Integration

### Authentication Endpoints

```
POST   /api/auth/login              # Email/password login
POST   /api/auth/register           # User registration
GET    /api/auth/me                 # Get current user
POST   /api/auth/device-sync        # Sync device info
POST   /api/auth/logout             # User logout
```

### Survey Endpoints

```
GET    /api/surveys                 # Get all surveys (filtered by role)
GET    /api/surveys/{id}            # Get specific survey
GET    /api/surveys/{id}/stats      # Get survey statistics
POST   /api/surveys                 # Create survey (admin only)
```

### Respondent Endpoints

```
GET    /api/respondents             # Get respondents (filterable by survey)
GET    /api/respondents/{id}        # Get specific respondent
POST   /api/respondents             # Create respondent
PUT    /api/respondents/{id}        # Update respondent
```

### Location Endpoints

```
POST   /api/locations               # Create location tracking
POST   /api/locations/batch         # Batch create locations
GET    /api/locations               # Get locations (filterable by user)
GET    /api/locations/latest        # Get latest locations
```

### Message Endpoints

```
POST   /api/messages                # Send message
GET    /api/messages                # Get messages (filterable)
GET    /api/messages/history        # Get message history
PUT    /api/messages/{id}           # Update message
DELETE /api/messages/{id}           # Delete message
PUT    /api/messages/{id}/respond   # Respond to message
PUT    /api/messages/{id}/read      # Mark as read
```

### Supervisor Endpoints

```
GET    /api/supervisor/conversations # Get all conversations
GET    /api/supervisor/messages/{id} # Get enumerator messages
GET    /api/supervisor/unanswered    # Get unanswered messages
```

### Admin Endpoints

```
GET    /api/admin/all-messages      # Get all messages
GET    /api/admin/chat-stats        # Get chat statistics
POST   /api/admin/broadcast         # Send broadcast message
```

### FAQ Endpoints

```
GET    /api/faqs                    # Get all FAQs
```

### Dashboard Endpoints

```
GET    /api/dashboard/stats         # Get dashboard statistics
```

---

## 🧪 Testing

### Run Unit Tests
```bash
flutter test
```

### Run Integration Tests
```bash
flutter test integration_test
```

### Test on Physical Device
```bash
# GPS and sensors require physical device
flutter run --release
```

### Test Offline Mode
1. Enable airplane mode on device
2. Add respondent (saved locally)
3. Disable airplane mode
4. Data syncs automatically

### Test Fraud Detection
1. Enable mock location app
2. App should detect and flag
3. Trust score drops
4. Fraud flags appear in analysis

---

## 📦 Dependencies

### Core Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `flutter` | SDK | Framework |
| `provider` | ^6.1.1 | State management |
| `http` | ^1.1.2 | HTTP client |
| `dio` | ^5.4.0 | Advanced HTTP client |
| `location` | ^8.0.1 | GPS location |
| `geolocator` | ^10.1.0 | Location utilities |
| `flutter_map` | ^6.1.0 | Map widget |
| `latlong2` | ^0.9.0 | Lat/Lng calculations |
| `sensors_plus` | ^4.0.2 | Device sensors |
| `device_info_plus` | ^12.2.0 | Device information |
| `workmanager` | ^0.9.0+3 | Background tasks |
| `sqflite` | ^2.3.0 | SQLite database |
| `shared_preferences` | ^2.2.2 | Key-value storage |
| `flutter_secure_storage` | ^9.0.0 | Secure storage |
| `connectivity_plus` | ^5.0.2 | Network status |
| `google_generative_ai` | ^0.4.7 | Gemini AI |
| `flutter_dotenv` | ^6.0.0 | Environment variables |
| `flutter_map_geojson` | ^1.0.8 | GeoJSON support |
| `google_fonts` | ^6.1.0 | Typography |
| `fl_chart` | ^0.65.0 | Charts (future use) |

See `pubspec.yaml` for complete dependency list.

---

## 🛠️ Development

### Project Structure

```
lib/
├── main.dart                    # App entry point
├── models/                      # Data models
│   ├── user.dart
│   ├── survey.dart
│   ├── respondent.dart
│   ├── location_tracking.dart
│   ├── sensor_data.dart
│   ├── location_fraud_result.dart
│   ├── message.dart
│   ├── faq.dart
│   └── survey_stats.dart
├── providers/                   # State management
│   ├── auth_provider.dart
│   ├── survey_provider.dart
│   ├── location_provider.dart
│   ├── fraud_detection_provider.dart
│   ├── network_provider.dart
│   └── offline_tile_provider.dart
├── services/                    # Business logic
│   ├── api_service.dart
│   ├── storage_service.dart
│   ├── location_service.dart
│   ├── enhanced_location_service.dart
│   ├── location_fraud_detection_service.dart
│   ├── sensor_collector_service.dart
│   ├── gemini_ai_service.dart
│   ├── sync_service.dart
│   ├── offline_map_service.dart
│   └── background_service.dart
├── screens/                     # UI screens
│   ├── auth/
│   │   ├── login_screen.dart
│   │   └── onboarding_screen.dart
│   ├── home/
│   │   └── home_screen.dart
│   ├── respondent/
│   │   ├── add_respondent_screen.dart
│   │   └── respondent_list_screen.dart
│   ├── chat/
│   │   ├── chat_router.dart
│   │   ├── ai_chat_screen.dart
│   │   ├── supervisor_chat_screen.dart
│   │   ├── admin_chat_screen.dart
│   │   └── broadcast_screen.dart
│   ├── profile/
│   │   └── profile_screen.dart
│   └── splash_screen.dart
└── widgets/                     # Reusable components
    └── fraud_detection_widgets.dart
```

### Code Style

The project follows Flutter's official style guide:
- Use `flutter_lints` for linting
- Follow effective Dart guidelines
- Document public APIs
- Use meaningful variable names
- Keep functions focused and small

### Git Workflow

```bash
# Create feature branch
git checkout -b feature/your-feature-name

# Commit changes
git add .
git commit -m "feat: add your feature description"

# Push to remote
git push origin feature/your-feature-name

# Create Pull Request
```

### Commit Message Convention

```
feat: Add new feature
fix: Bug fix
docs: Documentation update
style: Code style update
refactor: Code refactoring
test: Add tests
chore: Maintenance tasks
```

---

## 🤝 Contributing

We welcome contributions! Please follow these steps:

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'feat: Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

### Coding Standards

- Write clear, self-documenting code
- Add comments for complex logic
- Follow Flutter best practices
- Write tests for new features
- Update documentation
- Test on physical devices for GPS/sensor features

### Testing Guidelines

- Test offline functionality
- Test fraud detection with various scenarios
- Test on different Android versions
- Verify background tracking works
- Check battery consumption

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👥 Team

### Development Team
- **Project Lead**: Bill Van Ricardo Zalukhu
- **Flutter Developer**: Bill Van Ricardo Zalukhu
- **Backend Developer**: Bill Van Ricardo Zalukhu
- **ML Engineer**: Bill Van Ricardo Zalukhu
- **UI/UX Designer**: Bill Van Ricardo Zalukhu

---

## 📞 Support

### Contact

- **Email**: support@fieldtracker.id
- **Website**: [https://fieldtracker.id](https://fieldtracker.id)
- **Documentation**: [docs.fieldtracker.id](https://docs.fieldtracker.id)

### Reporting Issues

Please report bugs and issues through:
1. GitHub Issues
2. Email support for urgent matters
3. In-app feedback (future feature)

### Common Issues

**Q: Location not updating?**
A: Check GPS is enabled, app has location permissions, and is not in battery saver mode.

**Q: Offline sync not working?**
A: Ensure internet connection is stable. Check pending sync counter. Try manual sync.

**Q: Fraud detection showing false positives?**
A: This may occur in areas with poor GPS signal. Contact admin to review thresholds.

---

## 🗺️ Roadmap

### Version 1.1 (Current)
- [x] Real-time GPS tracking
- [x] Fraud detection system
- [x] Offline maps
- [x] AI chat assistant
- [x] Multi-survey support

### Version 1.2 (Planned)
- [ ] Enhanced fraud ML models
- [ ] Advanced analytics dashboard
- [ ] Export location history to KML/GPX
- [ ] Multi-language support (English/Indonesian)
- [ ] Voice input for AI chat

### Version 2.0 (Future)
- [ ] Image capture with location stamping
- [ ] Facial recognition for respondents
- [ ] Advanced route planning
- [ ] Offline voice AI
- [ ] Real-time collaboration features
- [ ] Push notifications

---

## 🙏 Acknowledgments

- Flutter Team for the amazing framework
- Google for Gemini AI capabilities
- OpenStreetMap contributors for map data
- Indonesian Statistics Agency (BPS) for domain knowledge
- All contributors and field testers

---

## 📚 Additional Resources

- [Flutter Documentation](https://docs.flutter.dev/)
- [Provider Package](https://pub.dev/packages/provider)
- [Flutter Map Documentation](https://docs.fleaflet.dev/)
- [Gemini API Documentation](https://ai.google.dev/docs)
- [Material Design Guidelines](https://material.io/design)
- [Flutter Best Practices](https://dart.dev/guides/language/effective-dart)

---

## 🔒 Security & Privacy

### Data Collection
- GPS coordinates (every 2 minutes)
- Sensor data (accelerometer, gyroscope, magnetometer)
- Device information (model, OS version, unique ID)
- Survey responses
- Chat messages

### Data Storage
- Local: SQLite database (encrypted)
- Remote: Backend server with TLS/SSL
- Secure: JWT tokens in Flutter Secure Storage

### Privacy Measures
- Device ID anonymization
- No personal data in GPS logs
- End-to-end message encryption (planned)
- GDPR compliance (planned)

### User Rights
- Access own data
- Request data deletion (admin only)
- Export location history
- Opt-in for analytics (future)

---

## ⚠️ Important Notes

### For Enumerators
1. **Always keep GPS enabled** - Automatic tracking requires GPS
2. **Charge your device** - Background tracking uses battery
3. **Enable high accuracy** - For better location precision
4. **Don't use fake GPS apps** - Will be detected and flagged
5. **Work during designated hours** - Outside hours triggers warnings

### For Supervisors
1. **Monitor fraud alerts** - Check enumerator trust scores regularly
2. **Respond to messages** - Enumerators rely on your guidance
3. **Review suspicious patterns** - Investigate low trust scores

### For Admins
1. **Set realistic boundaries** - Define survey regions accurately
2. **Monitor system health** - Check backend status regularly
3. **Adjust fraud thresholds** - Based on field conditions
4. **Regular data backups** - Prevent data loss

---

<div align="center">

**Built with ❤️ using Flutter**

© 2026 Field Tracker. All Rights Reserved.

</div>