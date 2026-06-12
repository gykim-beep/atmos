import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';
import 'package:atmos_mixer_pro/src/rust/frb_generated.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;
import 'package:atmos_mixer_pro/features/dashboard/screens/dashboard_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize rust bridge
  await RustLib.init();
  
  // Start the background rust threads
  rust_api.apiStartAudioEngine(deviceName: null);
  
  // Initialize window_manager for frameless kiosk mode
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(1280, 800),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden, // Frameless window
  );
  
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    const ProviderScope(
      child: AtmosMixerProApp(),
    ),
  );
}

class AtmosMixerProApp extends StatelessWidget {
  const AtmosMixerProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atmos Mixer Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        fontFamily: 'Pretendard', // Fallback to system font if not provided
      ),
      home: const DashboardScreen(),
    );
  }
}
