import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:camera/camera.dart';
import '../services/camera_service.dart';

class DriverProvider extends ChangeNotifier {
  final FlutterTts tts = FlutterTts();
  bool _isAwake = true;
  bool _isLoading = true;
  bool _isDrowsy = false;
  String _statusMessage = 'Initializing...';
  List<Face> _faces = [];
  Size? _imageSize;
  CameraLensDirection? _cameraLensDirection;
  double _leftEyeOpenPercent = 0;
  double _rightEyeOpenPercent = 0;
  InputImageRotation? _imageRotation;
  CameraService? _cameraService;
  bool _alertPlaying = false;
  int _drowsyCounter = 0; // Track consecutive drowsy detections
  int _awakeCounter = 0; // Track consecutive awake detections
  
  // Eye closure tracking
  DateTime? _eyesClosedStartTime;
  bool _showAlertDialog = false;
  Timer? _alertCheckTimer;

  bool get isAwake => _isAwake;
  bool get isLoading => _isLoading;
  bool get isDrowsy => _isDrowsy;
  String get statusMessage => _statusMessage;
  List<Face> get faces => _faces;
  Size? get imageSize => _imageSize;
  CameraLensDirection? get cameraLensDirection => _cameraLensDirection;
  double get leftEyeOpenPercent => _leftEyeOpenPercent;
  double get rightEyeOpenPercent => _rightEyeOpenPercent;
  CameraService? get cameraService => _cameraService;
  InputImageRotation? get imageRotation => _imageRotation;
  bool get showAlertDialog => _showAlertDialog;

  set isAwake(bool value) {
    _isAwake = value;
    notifyListeners();
  }

  void setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  void setDrowsy(bool value, {bool bothEyesClosed = false}) {
    _isDrowsy = value;
    
    // Track eye closure duration
    if (bothEyesClosed) {
      // Eyes are closed - start or continue tracking
      if (_eyesClosedStartTime == null) {
        _eyesClosedStartTime = DateTime.now();
      } else {
        // Check if eyes have been closed for more than 2 seconds
        final duration = DateTime.now().difference(_eyesClosedStartTime!);
        if (duration.inMilliseconds >= 2000 && !_showAlertDialog) {
          _showAlertDialog = true;
          _statusMessage = '🚨 ALERT: EYES CLOSED FOR ${duration.inSeconds} SECONDS!';
          _triggerAlert();
          notifyListeners();
          return;
        } else if (duration.inMilliseconds >= 2000) {
          // Update message with current duration
          _statusMessage = '🚨 ALERT: EYES CLOSED FOR ${duration.inSeconds} SECONDS!';
        }
      }
    } else {
      // Eyes are open - reset tracking
      if (_eyesClosedStartTime != null) {
        _eyesClosedStartTime = null;
        _showAlertDialog = false;
      }
    }
    
    // Update status message based on drowsiness
    if (value) {
      _drowsyCounter++;
      _awakeCounter = 0; // Reset awake counter
      
      // Only trigger alert after 3 consecutive drowsy detections to reduce false positives
      if (_drowsyCounter >= 3 && !_showAlertDialog) {
        _statusMessage = '🔴 DRIVER IS DROWSY!';
        _triggerAlert();
      } else if (!_showAlertDialog) {
        _statusMessage = '⚠️ Drowsiness detected';
      }
    } else {
      _drowsyCounter = 0; // Reset counter when not drowsy
      _awakeCounter++; // Increment awake counter
      
      // Only set to awake after 5 consecutive awake detections
      if (_awakeCounter >= 5) {
        _statusMessage = '🟢 Driver is awake';
      }
    }
    notifyListeners();
  }
  
  void dismissAlert() {
    _showAlertDialog = false;
    _eyesClosedStartTime = null;
    _statusMessage = '🟢 Driver is awake';
    notifyListeners();
  }

  void setStatusMessage(String message) {
    _statusMessage = message;
    notifyListeners();
  }

  void updateFaceData({
    required List<Face> faces,
    required Size imageSize,
    required CameraLensDirection lensDirection,
    required InputImageRotation rotation,
    required double leftEyePercent,
    required double rightEyePercent,
  }) {
    _faces = faces;
    _imageSize = imageSize;
    _cameraLensDirection = lensDirection;
    _imageRotation = rotation;
    _leftEyeOpenPercent = leftEyePercent;
    _rightEyeOpenPercent = rightEyePercent;
    notifyListeners();
  }

  void initializeCameraService() {
    _cameraService = CameraService();
  }

  void disposeCameraService() {
    _cameraService?.dispose();
  }

  void _triggerAlert() {
    // Play alert sound only once per drowsy event
    if (!_alertPlaying) {
      _alertPlaying = true;
      tts.setSpeechRate(0.9);
      tts.setVolume(1.0);
      tts.setPitch(1.2);
      tts.speak("ALERT! Your eyes have been closed for more than 2 seconds! Wake up immediately and take a break!");
      
      // Reset alert flag after delay
      Future.delayed(const Duration(seconds: 6), () {
        _alertPlaying = false;
      });
    }
  }
  
  @override
  void dispose() {
    _alertCheckTimer?.cancel();
    tts.stop();
    super.dispose();
  }
}