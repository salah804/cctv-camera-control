
<div align="center">

<img src="assets/app_icon.png" width="130" alt="CCTV Camera Control Logo">

# CCTV Camera Control

### Smart CCTV Monitoring & Surveillance Management

A Flutter-based CCTV application featuring live camera
streaming, recorded video playback, secure authentication,
and a modern dark-themed interface.

**Flutter • Dart • PHP • MySQL • RTSP • VLC**

</div>

---

## About the Project

CCTV Camera Control is a mobile application designed
to simplify IP camera monitoring and management.

The application combines Flutter with a PHP/MySQL
backend to provide secure account management,
live video streaming, and recorded video playback.

## Features

### Authentication & Account Management
- Secure login and registration
- Google Sign-In
- Stay signed in using session authentication
- Forgot password and password reset
- Change password
- Logout and session management

### User Profile
- View and update profile information
- Upload and remove profile pictures
- Optimized image uploads
- Fast profile reopening with memory caching

### CCTV Monitoring
- Add and manage IP cameras
- RTSP live streaming using VLC
- Camera selection and management
- Date-based recording playback
- Playback controls
- Offline demonstration cameras and videos

### User Interface
- Modern dark and futuristic design
- Cyan accent colors
- Custom application launcher icon
- Mobile-friendly Flutter interface

## Technology Stack

| Category | Technologies |
|---|---|
| Mobile | Flutter, Dart |
| Backend | PHP, REST APIs |
| Database | MySQL / MariaDB |
| Authentication | Google Sign-In, Session Tokens |
| Video Streaming | RTSP, VLC |
| Video Playback | flutter_vlc_player, video_player |
| Local Storage | SharedPreferences |
| Secure Storage | FlutterSecureStorage |
| Hosting | HelioHost |
| Version Control | Git, GitHub |

## Project Structure

```text
camera/
├── android/
├── ios/
├── lib/
│   ├── main.dart
│   ├── login.dart
│   ├── register.dart
│   ├── home.dart
│   ├── profile.dart
│   ├── RecordingScreen.dart
│   ├── playback_screen.dart
│   └── demo_screen.dart
├── backend/
│   ├── login.php
│   ├── register.php
│   ├── google_login.php
│   ├── check_session.php
│   ├── logout.php
│   ├── change_password.php
│   ├── request_password_reset.php
│   ├── reset_password.php
│   ├── getUserDetails.php
│   ├── update_profile.php
│   └── profile_auth.php
├── assets/
│   ├── app_icon.png
│   └── videos/
└── pubspec.yaml
```

## Getting Started

### Requirements

- Flutter SDK
- Android Studio or VS Code
- Android emulator or physical Android device
- PHP/MySQL backend for account features
- Compatible IP camera for real RTSP playback

### Installation

Clone the repository:

```bash
git clone https://github.com/salah804/cctv-camera-control.git
cd cctv-camera-control
```

Install dependencies:

```bash
flutter pub get
```

Run the application:

```bash
flutter run
```

### Backend Configuration

The PHP source is located in the `backend/` folder.

Configure your own PHP hosting, MySQL database,
email service, and authentication settings.

The repository intentionally excludes production
database passwords, private configuration files,
and other credentials.

The provided configuration examples are templates.
A complete database migration is not currently included.

## Security Notes

- Passwords are stored using secure password hashing.
- Authenticated profile requests use Bearer tokens.
- Sensitive production configuration is excluded.
- Do not publish private RTSP camera credentials.
- Camera configuration is stored locally; additional
  protection may be needed for sensitive deployments.

## Screenshots

Screenshots of the application interface will be added
to demonstrate the dashboard, camera monitoring,
profile management, and playback features.

## Developer

**Salah Ayash**

Full-Stack, Mobile & Cloud Developer

GitHub: https://github.com/salah804

---

Built with Flutter, PHP and MySQL.

