import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class CameraService {
  CameraController? _cameraController;
  bool _isProcessingFrame = false;
  int _frameCount = 0; // For debug logging
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableLandmarks: true,
      enableClassification: true,
      enableTracking: true, // Enable tracking for better performance
      performanceMode: FaceDetectorMode.fast, // Try fast mode for better compatibility
      minFaceSize: 0.05, // Very small minimum face size for maximum sensitivity
    ),
  );
  
  Future<void> initializeCamera(Function(CameraController) onInitialized) async {
    final cameras = await availableCameras();
    final frontCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.front,
      orElse: () => cameras.first,
    );
    
    _cameraController = CameraController(
      frontCamera,
      ResolutionPreset.high, // High resolution for better detection (veryHigh might be too much)
      imageFormatGroup: ImageFormatGroup.yuv420,
      enableAudio: false,
    );
    
    await _cameraController!.initialize();
    onInitialized(_cameraController!);
  }
  
  void startDetection(DetectionCallback onDetectionResult) {
    final controller = _cameraController;
    if (controller == null) return;
    
    controller.startImageStream((CameraImage image) async {
      if (_isProcessingFrame) {
        return;
      }
      _isProcessingFrame = true;
      try {
        // Get rotation from camera sensor orientation
        final sensorOrientation = controller.description.sensorOrientation;
        final rotation = InputImageRotationValue.fromRawValue(sensorOrientation) ??
            InputImageRotation.rotation0deg;
        
        // Debug rotation info occasionally
        if (_frameCount % 60 == 0) {
          debugPrint('Sensor orientation: $sensorOrientation, Rotation: $rotation');
          debugPrint('Image size: ${image.width}x${image.height}, Format: ${image.format.group}');
        }
        
        final inputImage = _inputImageFromCameraImage(image, rotation);
        if (inputImage == null) {
          _isProcessingFrame = false;
          return;
        }
        
        final faces = await _faceDetector.processImage(inputImage);
        
        // Debug logging (only log occasionally to avoid spam)
        _frameCount++;
        if (_frameCount % 30 == 0) { // Log every 30 frames (~1 second at 30fps)
          debugPrint('Face detection: ${faces.length} face(s) found');
          if (faces.isNotEmpty) {
            final face = faces.first;
            debugPrint('Face bounds: ${face.boundingBox}');
            debugPrint('Left eye open: ${face.leftEyeOpenProbability}, Right eye open: ${face.rightEyeOpenProbability}');
          } else {
            debugPrint('No faces detected - check image format and rotation');
          }
        }
        
        final isDrowsy = _checkForDrowsiness(faces);
        final bothEyesClosed = _areBothEyesClosed(faces);
        final leftEyePercent = faces.isNotEmpty
            ? ((faces.first.leftEyeOpenProbability ?? 0).clamp(0.0, 1.0) * 100)
            : 0.0;
        final rightEyePercent = faces.isNotEmpty
            ? ((faces.first.rightEyeOpenProbability ?? 0).clamp(0.0, 1.0) * 100)
            : 0.0;
        
        onDetectionResult(
          FaceDetectionResult(
            faces: faces,
            isDrowsy: isDrowsy,
            bothEyesClosed: bothEyesClosed,
            imageSize: Size(image.width.toDouble(), image.height.toDouble()),
            rotation: rotation,
            cameraLensDirection: controller.description.lensDirection,
            leftEyeOpenPercent: leftEyePercent,
            rightEyeOpenPercent: rightEyePercent,
          ),
        );
      } catch (e, stackTrace) {
        debugPrint('Detection error: $e');
        debugPrint('Stack trace: $stackTrace');
        // Reset processing flag on error to prevent blocking
        _isProcessingFrame = false;
      } finally {
        _isProcessingFrame = false;
      }
    });
  }
  
  InputImage? _inputImageFromCameraImage(
    CameraImage image,
    InputImageRotation rotation,
  ) {
    try {
      if (image.planes.isEmpty) {
        debugPrint('Error: Image planes are empty');
        return null;
      }
      
      final size = Size(image.width.toDouble(), image.height.toDouble());
      
      // For YUV420 format, combine all planes into a single byte array
      // Calculate total size needed
      int totalBytes = 0;
      for (final Plane plane in image.planes) {
        totalBytes += plane.bytes.length;
      }
      
      final bytes = Uint8List(totalBytes);
      int offset = 0;
      for (final Plane plane in image.planes) {
        bytes.setRange(offset, offset + plane.bytes.length, plane.bytes);
        offset += plane.bytes.length;
      }
      
      // Determine the correct image format from raw value
      final imageFormat = InputImageFormatValue.fromRawValue(image.format.raw) ??
          InputImageFormat.nv21;
      
      // Get bytesPerRow from the first plane (Y plane for YUV420)
      // This is critical for proper image interpretation
      final bytesPerRow = image.planes[0].bytesPerRow;
      
      final metadata = InputImageMetadata(
        size: size,
        rotation: rotation,
        format: imageFormat,
        bytesPerRow: bytesPerRow,
      );
      
      return InputImage.fromBytes(
        bytes: bytes,
        metadata: metadata,
      );
    } catch (e, stackTrace) {
      debugPrint('Error converting image: $e');
      debugPrint('Stack trace: $stackTrace');
      return null;
    }
  }
  
  bool _checkForDrowsiness(List<Face> faces) {
    if (faces.isEmpty) return false;
    
    final face = faces.first;
    
    // More accurate thresholds with better handling of edge cases
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    
    // Both eyes closed - most reliable indicator
    final bothEyesClosed = leftEyeOpen < 0.25 && rightEyeOpen < 0.25;
    
    // One eye significantly more closed than the other (winking or squinting)
    final oneEyeClosed = (leftEyeOpen < 0.2 && rightEyeOpen < 0.4) ||
        (leftEyeOpen < 0.4 && rightEyeOpen < 0.2);
    
    // Both eyes partially closed (drowsy state)
    final bothEyesPartiallyClosed = leftEyeOpen < 0.3 && rightEyeOpen < 0.3;
    
    return bothEyesClosed || oneEyeClosed || bothEyesPartiallyClosed;
  }
  
  bool _areBothEyesClosed(List<Face> faces) {
    if (faces.isEmpty) return false;
    
    final face = faces.first;
    final leftEyeOpen = face.leftEyeOpenProbability ?? 1.0;
    final rightEyeOpen = face.rightEyeOpenProbability ?? 1.0;
    
    // More strict threshold for "both eyes closed" detection
    // Using 0.25 threshold for better accuracy
    return leftEyeOpen < 0.25 && rightEyeOpen < 0.25;
  }
  
  void stop() {
    try {
      _cameraController?.stopImageStream();
    } catch (_) {}
    _isProcessingFrame = false;
  }
  
  void dispose() {
    stop();
    _cameraController?.dispose();
    _faceDetector.close();
  }
  
  CameraController? get controller => _cameraController;
}

typedef DetectionCallback = void Function(FaceDetectionResult result);

class FaceDetectionResult {
  FaceDetectionResult({
    required this.faces,
    required this.isDrowsy,
    required this.bothEyesClosed,
    required this.imageSize,
    required this.rotation,
    required this.cameraLensDirection,
    required this.leftEyeOpenPercent,
    required this.rightEyeOpenPercent,
  });
  
  final List<Face> faces;
  final bool isDrowsy;
  final bool bothEyesClosed;
  final Size imageSize;
  final InputImageRotation rotation;
  final CameraLensDirection cameraLensDirection;
  final double leftEyeOpenPercent;
  final double rightEyeOpenPercent;
}