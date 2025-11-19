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
      enableClassification: true, // Required for eye open/closed detection
      enableTracking: true, // Enable tracking for better performance
      performanceMode: FaceDetectorMode.accurate, // Use accurate mode for better detection
      minFaceSize: 0.15, // Minimum face size (15% of image) - balanced for performance and accuracy
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
      ResolutionPreset.high, // High resolution for better detection
      imageFormatGroup: ImageFormatGroup.yuv420, // YUV420 format for ML Kit
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
        
        final isDrowsy = _checkForDrowsiness(faces);
        final bothEyesClosed = _areBothEyesClosed(faces);
        
        // Calculate eye openness percentage (0-100%)
        // leftEyeOpenProbability: 0.0 = closed, 1.0 = open
        double leftEyePercent = 0.0;
        double rightEyePercent = 0.0;
        
        if (faces.isNotEmpty) {
          final face = faces.first;
          final leftEyeProb = face.leftEyeOpenProbability;
          final rightEyeProb = face.rightEyeOpenProbability;
          
          // Convert probability to percentage
          // If probability is null, assume 100% open (default safe state)
          leftEyePercent = leftEyeProb != null 
              ? (leftEyeProb.clamp(0.0, 1.0) * 100)
              : 100.0;
          rightEyePercent = rightEyeProb != null
              ? (rightEyeProb.clamp(0.0, 1.0) * 100)
              : 100.0;
        }
        
        // Debug logging (only log occasionally to avoid spam)
        _frameCount++;
        if (_frameCount % 60 == 0) { // Log every 60 frames (~2 seconds at 30fps)
          debugPrint('=== Face Detection Debug ===');
          debugPrint('Frame count: $_frameCount');
          debugPrint('Faces detected: ${faces.length}');
          if (faces.isNotEmpty) {
            final face = faces.first;
            debugPrint('Face bounds: ${face.boundingBox}');
            debugPrint('Face size: ${face.boundingBox.width}x${face.boundingBox.height}');
            debugPrint('Left eye open probability: ${face.leftEyeOpenProbability}');
            debugPrint('Right eye open probability: ${face.rightEyeOpenProbability}');
            debugPrint('Is drowsy: $isDrowsy');
            debugPrint('Both eyes closed: $bothEyesClosed');
            debugPrint('Eye percentages - Left: ${leftEyePercent.toStringAsFixed(1)}%, Right: ${rightEyePercent.toStringAsFixed(1)}%');
          } else {
            debugPrint('No faces detected');
            debugPrint('Image size: ${image.width}x${image.height}');
            debugPrint('Image format: ${image.format}');
            debugPrint('Rotation: $rotation');
            debugPrint('Tip: Ensure face is well-lit and centered in frame');
          }
          debugPrint('===========================');
        }
        
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
      
      // Convert YUV_420_888 format to NV21 format for ML Kit
      // YUV_420_888 has 3 planes: Y (luminance), U (chroma), V (chroma)
      if (image.planes.isEmpty) {
        debugPrint('Error: Image planes are empty');
        return null;
      }
      
      final yPlane = image.planes[0];
      final uPlane = image.planes.length > 1 ? image.planes[1] : null;
      final vPlane = image.planes.length > 2 ? image.planes[2] : null;
      
      // For YUV_420_888, we need to convert to NV21 format
      // NV21: Y plane followed by interleaved VU plane
      final yBuffer = yPlane.bytes;
      final yRowStride = yPlane.bytesPerRow;
      final yPixelStride = yPlane.bytesPerPixel ?? 1;
      
      // Calculate image dimensions
      final width = image.width;
      final height = image.height;
      
      // Create NV21 buffer (Y plane + interleaved VU)
      final nv21Size = (width * height * 3 / 2).round();
      final nv21 = Uint8List(nv21Size);
      
      // Copy Y plane - handle pixel stride correctly
      int nv21Index = 0;
      for (int row = 0; row < height; row++) {
        int yStart = row * yRowStride;
        for (int col = 0; col < width; col++) {
          int yPos = yStart + col * yPixelStride;
          if (yPos < yBuffer.length) {
            nv21[nv21Index++] = yBuffer[yPos];
          }
        }
      }
      
      // Convert UV planes to interleaved VU format (NV21)
      if (uPlane != null && vPlane != null) {
        final uBuffer = uPlane.bytes;
        final vBuffer = vPlane.bytes;
        final uvRowStride = uPlane.bytesPerRow;
        final uvPixelStride = uPlane.bytesPerPixel ?? 1;
        
        final uvWidth = width ~/ 2;
        final uvHeight = height ~/ 2;
        
        int uvIndex = width * height; // Start after Y plane
        
        for (int row = 0; row < uvHeight; row++) {
          int uRowStart = row * uvRowStride;
          int vRowStart = row * vPlane.bytesPerRow;
          final vPixelStride = vPlane.bytesPerPixel ?? 1;
          
          for (int col = 0; col < uvWidth; col++) {
            int uPos = uRowStart + col * uvPixelStride;
            int vPos = vRowStart + col * vPixelStride;
            
            // Ensure we don't go out of bounds
            if (vPos < vBuffer.length && uPos < uBuffer.length && uvIndex < nv21.length - 1) {
              // Interleave as VU (NV21 format)
              nv21[uvIndex++] = vBuffer[vPos];
              nv21[uvIndex++] = uBuffer[uPos];
            }
          }
        }
      }
      
      final metadata = InputImageMetadata(
        size: size,
        rotation: rotation,
        format: InputImageFormat.nv21,
        bytesPerRow: width, // For NV21, bytesPerRow is width
      );
      
      return InputImage.fromBytes(
        bytes: nv21,
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
    
    // Get eye open probabilities (0.0 = closed, 1.0 = open)
    // If probability is null, assume eye is open (default)
    final leftEyeOpen = face.leftEyeOpenProbability;
    final rightEyeOpen = face.rightEyeOpenProbability;
    
    // If eye classification is not available, return false
    if (leftEyeOpen == null || rightEyeOpen == null) {
      return false;
    }
    
    // Both eyes closed - most reliable indicator of drowsiness
    final bothEyesClosed = leftEyeOpen < 0.3 && rightEyeOpen < 0.3;
    
    // Both eyes partially closed (drowsy state) - eyes are less than 50% open
    final bothEyesPartiallyClosed = leftEyeOpen < 0.5 && rightEyeOpen < 0.5;
    
    // One eye significantly more closed than the other (winking or squinting)
    final eyeDifference = (leftEyeOpen - rightEyeOpen).abs();
    final oneEyeClosed = eyeDifference > 0.4 && 
        (leftEyeOpen < 0.3 || rightEyeOpen < 0.3);
    
    return bothEyesClosed || (bothEyesPartiallyClosed && !oneEyeClosed) || oneEyeClosed;
  }
  
  bool _areBothEyesClosed(List<Face> faces) {
    if (faces.isEmpty) return false;
    
    final face = faces.first;
    final leftEyeOpen = face.leftEyeOpenProbability;
    final rightEyeOpen = face.rightEyeOpenProbability;
    
    // If eye classification is not available, return false
    if (leftEyeOpen == null || rightEyeOpen == null) {
      return false;
    }
    
    // Both eyes closed threshold: less than 30% open for both eyes
    // This threshold is optimized for accurate drowsiness detection
    return leftEyeOpen < 0.3 && rightEyeOpen < 0.3;
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