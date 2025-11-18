import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

class FacePainter extends CustomPainter {
  FacePainter({
    required this.faces,
    required this.isDrowsy,
    required this.absoluteImageSize,
    required this.cameraLensDirection,
    required this.imageRotation,
  });
  
  final List<Face> faces;
  final bool isDrowsy;
  final Size absoluteImageSize;
  final CameraLensDirection cameraLensDirection;
  final InputImageRotation imageRotation;
  
  @override
  void paint(Canvas canvas, Size size) {
    if (faces.isEmpty || absoluteImageSize == Size.zero) return;
    
    final paintBox = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = isDrowsy ? Colors.redAccent : Colors.greenAccent;
    
    for (final face in faces) {
      final rect = _scaleRect(face.boundingBox, size);
      canvas.drawRRect(
        RRect.fromRectXY(rect, 18, 18),
        paintBox,
      );
      _drawFaceLabel(canvas, rect);
      _drawEyeState(
        canvas: canvas,
        size: size,
        eyeProbability: face.leftEyeOpenProbability ?? 1.0,
        landmark: face.landmarks[FaceLandmarkType.leftEye],
        contour: face.contours[FaceContourType.leftEye],
        label: 'Left Eye',
      );
      _drawEyeState(
        canvas: canvas,
        size: size,
        eyeProbability: face.rightEyeOpenProbability ?? 1.0,
        landmark: face.landmarks[FaceLandmarkType.rightEye],
        contour: face.contours[FaceContourType.rightEye],
        label: 'Right Eye',
      );
    }
  }
  
  void _drawFaceLabel(Canvas canvas, Rect rect) {
    final label = TextPainter(
      text: TextSpan(
        text: isDrowsy ? 'DROWSY!' : 'Face Detected',
        style: TextStyle(
          color: isDrowsy ? Colors.redAccent : Colors.greenAccent,
          fontSize: 16,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withOpacity(0.6),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    label.paint(canvas, Offset(rect.left, rect.top - 26));
  }
  
  void _drawEyeState({
    required Canvas canvas,
    required Size size,
    required double eyeProbability,
    required FaceLandmark? landmark,
    required FaceContour? contour,
    required String label,
  }) {
    if (landmark == null) return;
    
    final probability = eyeProbability.clamp(0.0, 1.0);
    final isEyeOpen = probability >= 0.3;
    final color = isDrowsy
        ? Colors.redAccent
        : (isEyeOpen ? Colors.greenAccent : Colors.orangeAccent);
    
    final points = contour?.points ?? [];
    final scaledPoints = points
        .map(
          (point) => _scalePoint(
            point.x.toDouble(),
            point.y.toDouble(),
            size,
          ),
        )
        .toList();
    
    final eyePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = color;
    
    if (scaledPoints.isNotEmpty) {
      _drawContour(canvas, scaledPoints, eyePaint);
      final eyeCenter = _calculateCenter(scaledPoints);
      final eyeRadius = _calculateRadius(scaledPoints, eyeCenter) * 1.2;
      canvas.drawCircle(eyeCenter, eyeRadius, eyePaint);
      canvas.drawCircle(
        eyeCenter,
        eyeRadius * (0.35 + probability * 0.55),
        eyePaint..style = PaintingStyle.fill..color = color.withOpacity(0.25),
      );
    } else {
      final center = _scalePoint(
        landmark.position.x.toDouble(),
        landmark.position.y.toDouble(),
        size,
      );
      canvas.drawCircle(center, 14, eyePaint);
    }
    
    final textPainter = TextPainter(
      text: TextSpan(
        text:
            '$label ${(probability * 100).toStringAsFixed(0)}% ${isEyeOpen ? 'OPEN' : 'CLOSED'}',
        style: TextStyle(
          color: color,
          fontSize: 13,
          fontWeight: FontWeight.bold,
          backgroundColor: Colors.black.withOpacity(0.65),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    
    final labelOffset = _scalePoint(
      landmark.position.x.toDouble(),
      landmark.position.y.toDouble(),
      size,
    ) -
        const Offset(60, 36);
    textPainter.paint(canvas, labelOffset);
  }
  
  Rect _scaleRect(Rect rect, Size widgetSize) {
    final leftTop = _scalePoint(rect.left, rect.top, widgetSize);
    final rightBottom = _scalePoint(rect.right, rect.bottom, widgetSize);
    return Rect.fromLTRB(leftTop.dx, leftTop.dy, rightBottom.dx, rightBottom.dy);
  }
  
  Offset _scalePoint(double x, double y, Size widgetSize) {
    final isRotated = imageRotation == InputImageRotation.rotation90deg ||
        imageRotation == InputImageRotation.rotation270deg;
    final adjustedWidth = isRotated ? absoluteImageSize.height : absoluteImageSize.width;
    final adjustedHeight = isRotated ? absoluteImageSize.width : absoluteImageSize.height;
    
    double translatedX = x / adjustedWidth * widgetSize.width;
    double translatedY = y / adjustedHeight * widgetSize.height;
    
    if (cameraLensDirection == CameraLensDirection.front) {
      translatedX = widgetSize.width - translatedX;
    }
    
    return Offset(translatedX, translatedY);
  }
  
  Offset _calculateCenter(List<Offset> points) {
    double sumX = 0;
    double sumY = 0;
    for (final point in points) {
      sumX += point.dx;
      sumY += point.dy;
    }
    return Offset(sumX / points.length, sumY / points.length);
  }
  
  double _calculateRadius(List<Offset> points, Offset center) {
    double sumDistances = 0;
    for (final point in points) {
      sumDistances += (point - center).distance;
    }
    return points.isEmpty ? 0 : sumDistances / points.length;
  }
  
  void _drawContour(Canvas canvas, List<Offset> points, Paint paint) {
    if (points.length < 2) return;
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (int i = 1; i < points.length; i++) {
      path.lineTo(points[i].dx, points[i].dy);
    }
    path.close();
    canvas.drawPath(path, paint);
  }
  
  @override
  bool shouldRepaint(covariant FacePainter oldDelegate) {
    return oldDelegate.faces != faces ||
        oldDelegate.isDrowsy != isDrowsy ||
        oldDelegate.absoluteImageSize != absoluteImageSize ||
        oldDelegate.cameraLensDirection != cameraLensDirection ||
        oldDelegate.imageRotation != imageRotation;
  }
}