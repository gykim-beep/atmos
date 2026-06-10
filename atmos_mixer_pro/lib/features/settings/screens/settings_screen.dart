import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/glass_container.dart';
import '../widgets/preferences_modal.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AtmosColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text("Settings & Preferences", style: TextStyle(color: AtmosColors.neonCyan)),
      ),
      body: Center(
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AtmosColors.neonMagenta,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            showDialog(
              context: context,
              builder: (context) => const PreferencesModal(),
            );
          },
          child: const Text("Open Console Wizard"),
        ),
      ),
    );
  }
}
