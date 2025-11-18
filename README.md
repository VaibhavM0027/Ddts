# Driver Drowsiness Tracking System (DDTS)

A Flutter-based mobile application that acts as a driver alert and safety system to prevent drowsy driving. The app uses Google MLKit Face Detection to monitor the driver's eyes in real-time and sends alerts to an ESP32 microcontroller when drowsiness is detected.

## Features

- Real-time face detection using front camera
- Eye closure monitoring for drowsiness detection
- Visual status indicators (🟢 Awake / 🔴 Drowsy)
- HTTP communication with ESP32 for physical alerts
- Cross-platform support (Android, iOS)

## Prerequisites

- Flutter SDK 3.3.0 or higher
- Android/iOS device with front-facing camera
- ESP32 microcontroller configured to receive HTTP requests

## Setup

1. Clone the repository
2. Run `flutter pub get` to install dependencies
3. Update the ESP32 IP address in `lib/services/camera_service.dart`:
   ```dart
   static const String ESP32_IP = 'YOUR_ESP32_IP_ADDRESS';
   ```
4. Connect an Android/iOS device
5. Run the app with `flutter run`

## How It Works

1. The app accesses the device's front camera
2. Google MLKit Face Detection continuously monitors facial features
3. Eye openness probabilities are analyzed in real-time
4. If both eyes are closed for more than 2 seconds, drowsiness is detected
5. The app sends an HTTP GET request to the ESP32 at `http://<ESP32_IP>/alert`
6. The ESP32 triggers physical alerts (motor, buzzer, LED)

## Dependencies

- camera: ^0.10.5+5
- google_mlkit_face_detection: ^0.10.0
- permission_handler: ^11.0.1
- http: ^1.2.1
- provider: ^6.1.2

## Folder Structure

```
lib/
├── main.dart
├── screens/
│   └── camera_screen.dart
├── providers/
│   └── driver_provider.dart
└── services/
    └── camera_service.dart
```