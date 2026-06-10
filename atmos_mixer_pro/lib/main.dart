import 'package:flutter/material.dart';
import 'src/rust/frb_generated.dart';
import 'src/rust/api/simple.dart';
import 'package:provider/provider.dart';
import 'core/state/global_state.dart';
import 'features/dashboard/screens/dashboard_screen.dart';

Future<void> main() async {
  await RustLib.init();
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => GlobalState()),
      ],
      child: const AtmosApp(),
    ),
  );
}

class AtmosApp extends StatelessWidget {
  const AtmosApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Atmos Mixer Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        fontFamily: 'Inter',
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF00FFCC),
          brightness: Brightness.dark,
        ),
      ),
      home: const DashboardScreen(),
    );
  }
}
