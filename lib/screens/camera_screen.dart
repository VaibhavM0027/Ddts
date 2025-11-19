import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers/driver_provider.dart';
import '../widgets/face_painter.dart';

class CameraScreen extends StatefulWidget {
  const CameraScreen({super.key});

  @override
  State<CameraScreen> createState() => _CameraScreenState();
}

class _CameraScreenState extends State<CameraScreen> {
  CameraController? _controller;
  bool _isPermissionGranted = false;
  bool _isPermissionRequested = false;
  bool _alertDialogShown = false;

  @override
  void initState() {
    super.initState();
    _requestPermissions();
  }

  Future<void> _requestPermissions() async {
    setState(() {
      _isPermissionRequested = true;
    });
    
    final status = await Permission.camera.request();
    if (status == PermissionStatus.granted) {
      setState(() {
        _isPermissionGranted = true;
      });
      _initializeCamera();
    } else {
      setState(() {
        _isPermissionGranted = false;
      });
      // Show dialog to explain why permission is needed
      if (mounted) {
        _showPermissionDialog();
      }
    }
  }

  Future<void> _initializeCamera() async {
    final driverProvider = Provider.of<DriverProvider>(context, listen: false);
    driverProvider.initializeCameraService();

    try {
      await driverProvider.cameraService!.initializeCamera((controller) {
        if (mounted) {
          setState(() {
            _controller = controller;
          });
        }
      });

      if (mounted) {
        driverProvider.setLoading(false);
        driverProvider.setStatusMessage('🟢 Driver is awake');

        driverProvider.cameraService!.startDetection((result) {
          if (!mounted) return;
          
          driverProvider.setDrowsy(result.isDrowsy, bothEyesClosed: result.bothEyesClosed);
          driverProvider.updateFaceData(
            faces: result.faces,
            imageSize: result.imageSize,
            lensDirection: result.cameraLensDirection,
            rotation: result.rotation,
            leftEyePercent: result.leftEyeOpenPercent,
            rightEyePercent: result.rightEyeOpenPercent,
          );
          
          // Show alert dialog if eyes closed for > 2 seconds
          if (driverProvider.showAlertDialog && mounted && !_alertDialogShown) {
            _alertDialogShown = true;
            _showEyeClosureAlert(driverProvider);
          } else if (!driverProvider.showAlertDialog) {
            _alertDialogShown = false;
          }
          
          if (result.faces.isEmpty && !driverProvider.isDrowsy) {
            driverProvider.setStatusMessage('👤 No face detected - Position face in frame');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        driverProvider.setStatusMessage('Error: $e');
      }
    }
  }

  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Camera Permission Required'),
          content: const Text(
              'This app needs camera permission to detect your face and eyes for drowsiness detection. '
              'Please enable camera permission in settings.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                Navigator.of(context).pop();
                await openAppSettings();
              },
              child: const Text('Open Settings'),
            ),
          ],
        );
      },
    );
  }
  
  void _showEyeClosureAlert(DriverProvider provider) {
    // Prevent multiple dialogs from showing
    if (!mounted) return;
    
    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.red.withOpacity(0.7),
      builder: (BuildContext context) {
        return PopScope(
          canPop: false, // Prevent dismissing by back button
          child: AlertDialog(
            backgroundColor: Colors.red.shade900,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: const BorderSide(color: Colors.white, width: 3),
            ),
            title: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white, size: 40),
                SizedBox(width: 10),
                Text(
                  'ALERT!',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Your eyes have been closed for more than 2 seconds!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Text(
                    '⚠️ WAKE UP IMMEDIATELY!\n\nPlease pull over safely and take a break.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              Center(
                child: ElevatedButton(
                  onPressed: () {
                    if (mounted) {
                      Navigator.of(context).pop();
                      _alertDialogShown = false;
                      provider.dismissAlert();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Colors.red.shade900,
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(25),
                    ),
                  ),
                  child: const Text(
                    'I\'M AWAKE',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final driverProvider = Provider.of<DriverProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Driver Alert System'),
        backgroundColor: driverProvider.isDrowsy ? Colors.red : Colors.green,
      ),
      body: !_isPermissionRequested
          ? const Center(child: CircularProgressIndicator())
          : !_isPermissionGranted
              ? _buildPermissionDeniedView()
              : driverProvider.isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildCameraPreview(driverProvider),
    );
  }

  Widget _buildPermissionDeniedView() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.no_photography,
            size: 80,
            color: Colors.red,
          ),
          const SizedBox(height: 20),
          const Text(
            'Camera permission denied',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 10),
          const Text(
            'Please enable camera permission to use this app',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            onPressed: _requestPermissions,
            child: const Text('Request Permission'),
          ),
        ],
      ),
    );
  }

  Widget _buildCameraPreview(DriverProvider driverProvider) {
    if (_controller == null || !_controller!.value.isInitialized) {
      return const Center(child: Text('Camera not initialized'));
    }

    return Stack(
      children: [
        // Camera preview
        CameraPreview(_controller!),

        // Face overlays
        if (driverProvider.faces.isNotEmpty &&
            driverProvider.imageSize != null &&
            driverProvider.cameraLensDirection != null &&
            driverProvider.imageRotation != null)
          Positioned.fill(
            child: CustomPaint(
              painter: FacePainter(
                faces: driverProvider.faces,
                isDrowsy: driverProvider.isDrowsy,
                absoluteImageSize: driverProvider.imageSize!,
                cameraLensDirection: driverProvider.cameraLensDirection!,
                imageRotation: driverProvider.imageRotation!,
              ),
            ),
          )
        else
          _buildFaceDetectionBox(),

        _buildStatusOverlay(driverProvider),
        _buildEyeMetrics(driverProvider),

        // Instructions
        const Positioned(
          bottom: 50,
          left: 0,
          right: 0,
          child: Center(
            child: Text(
              'Position your face in the box above',
              style: TextStyle(
                fontSize: 16,
                color: Colors.white,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFaceDetectionBox() {
    return Stack(
      children: [
        Center(
          child: Container(
            width: 250,
            height: 300,
            decoration: BoxDecoration(
              border: Border.all(
                color: Colors.green.withOpacity(0.5),
                width: 3.0,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).size.height * 0.3 + 160,
          left: 0,
          right: 0,
          child: const Center(
            child: Text(
              'Position your face in the frame',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                backgroundColor: Colors.black54,
              ),
            ),
          ),
        ),
      ],
    );
  }
  
  Widget _buildStatusOverlay(DriverProvider provider) {
    return Positioned(
      top: 50,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: provider.isDrowsy
              ? Colors.red.withOpacity(0.85)
              : Colors.green.withOpacity(0.8),
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              provider.statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            if (provider.faces.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 4.0),
                child: Text(
                  'Ensure proper lighting and keep your face inside the frame.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildEyeMetrics(DriverProvider provider) {
    return Positioned(
      bottom: 110,
      left: 16,
      right: 16,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.55),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: provider.isDrowsy ? Colors.redAccent : Colors.greenAccent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _EyeMetricTile(
              label: 'Left Eye',
              percentage: provider.leftEyeOpenPercent,
            ),
            Container(
              width: 1,
              height: 48,
              color: Colors.white24,
            ),
            _EyeMetricTile(
              label: 'Right Eye',
              percentage: provider.rightEyeOpenPercent,
            ),
          ],
        ),
      ),
    );
  }
  
  @override
  void dispose() {
    _controller?.dispose();
    Provider.of<DriverProvider>(context, listen: false).disposeCameraService();
    super.dispose();
  }
}

class _EyeMetricTile extends StatelessWidget {
  const _EyeMetricTile({
    required this.label,
    required this.percentage,
  });
  
  final String label;
  final double percentage;
  
  Color get _statusColor {
    if (percentage >= 65) return Colors.greenAccent;
    if (percentage >= 35) return Colors.orangeAccent;
    return Colors.redAccent;
  }
  
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.white70,
            fontSize: 14,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          '${percentage.toStringAsFixed(0)}%',
          style: TextStyle(
            color: _statusColor,
            fontSize: 26,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          percentage >= 65
              ? 'OPEN'
              : percentage >= 35
                  ? 'PARTIAL'
                  : 'CLOSED',
          style: TextStyle(
            color: _statusColor,
            fontSize: 12,
            letterSpacing: 1.2,
          ),
        ),
      ],
    );
  }
}