import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'providers/driver_provider.dart';
import 'screens/camera_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Request camera permission
  final status = await Permission.camera.request();
  if (status != PermissionStatus.granted) {
    // Handle permission denied
    print('Camera permission denied');
  }
  
  runApp(const DriverAlertApp());
}

class DriverAlertApp extends StatelessWidget {
  const DriverAlertApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => DriverProvider()),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Driver Alert System',
        theme: ThemeData(
          brightness: Brightness.dark,
          primarySwatch: Colors.green,
        ),
        home: const CameraScreen(),
      ),
    );
  }
}