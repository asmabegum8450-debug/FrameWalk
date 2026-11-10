import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'firebase_options.dart';
import 'frontend/screens/auth_gate.dart';
import 'frontend/theme/app_theme.dart';
import 'backend/providers/route_provider.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const FrameWalkApp());
}

class FrameWalkApp extends StatelessWidget {
  const FrameWalkApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => RouteProvider(),
      child: MaterialApp(
        title: 'FrameWalk',
        theme: AppTheme.lightTheme,
        home: const AuthGate(),
      ),
    );
  }
}
