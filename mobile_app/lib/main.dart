import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera_android/camera_android.dart';
import 'package:camera_platform_interface/camera_platform_interface.dart';
import 'theme/app_theme.dart';
import 'views/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // Força uso da implementação estável Camera2 (camera_android)
    CameraPlatform.instance = AndroidCamera();
  }
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  runApp(const MovementBiomechanicsApp());
}

class MovementBiomechanicsApp extends StatelessWidget {
  const MovementBiomechanicsApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Movement Biomechanics',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const HomeScreen(),
    );
  }
}
