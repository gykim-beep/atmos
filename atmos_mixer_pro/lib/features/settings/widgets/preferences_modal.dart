import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/glass_container.dart';
import '../../../core/state/global_state.dart';

class PreferencesModal extends StatefulWidget {
  const PreferencesModal({super.key});

  @override
  State<PreferencesModal> createState() => _PreferencesModalState();
}

class _PreferencesModalState extends State<PreferencesModal> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GlassContainer(
        width: 800,
        height: 600,
        child: Material(
          color: Colors.transparent,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "AUDIO SETTINGS & CONSOLE WIZARD",
                      style: TextStyle(
                        color: AtmosColors.neonCyan,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 2.0,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AtmosColors.textMain),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                indicatorColor: AtmosColors.neonMagenta,
                labelColor: AtmosColors.neonMagenta,
                unselectedLabelColor: AtmosColors.textDim,
                tabs: const [
                  Tab(text: "1. Audio Output Settings"),
                  Tab(text: "2. Room Signal & Routing"),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildAudioSettingsTab(context),
                    _buildRoutingSettingsTab(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAudioSettingsTab(BuildContext context) {
    final state = context.watch<GlobalState>();
    final devices = state.availableDevices.isEmpty ? ["Default"] : state.availableDevices;
    final selectedDevice = state.selectedDevice.isEmpty ? "Default" : state.selectedDevice;

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Output Device Selection", style: TextStyle(color: AtmosColors.textMain, fontSize: 18)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AtmosColors.neonCyan.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                dropdownColor: AtmosColors.background,
                value: devices.contains(selectedDevice) ? selectedDevice : devices.first,
                items: devices
                    .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(color: AtmosColors.textMain))))
                    .toList(),
                onChanged: (val) {},
              ),
            ),
          ),
          const SizedBox(height: 32),
          const Text("Buffer Size (Latency)", style: TextStyle(color: AtmosColors.textMain, fontSize: 18)),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              border: Border.all(color: AtmosColors.neonCyan.withOpacity(0.5)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                dropdownColor: AtmosColors.background,
                value: 256,
                items: [64, 128, 256, 512, 1024]
                    .map((e) => DropdownMenuItem(value: e, child: Text("$e Samples (${(e/48.0).toStringAsFixed(1)} ms)", style: const TextStyle(color: AtmosColors.textMain))))
                    .toList(),
                onChanged: (val) {},
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutingSettingsTab() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("OSC Triggers & Matrix Mapping", style: TextStyle(color: AtmosColors.textMain, fontSize: 18)),
          const SizedBox(height: 16),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: AtmosColors.neonMagenta.withOpacity(0.5)),
                borderRadius: BorderRadius.circular(8),
                color: AtmosColors.background.withOpacity(0.5),
              ),
              child: ListView.builder(
                itemCount: 5,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(Icons.router, color: AtmosColors.neonCyan),
                    title: Text("Room ${index + 1} Matrix Config", style: const TextStyle(color: AtmosColors.textMain)),
                    subtitle: Text("OSC: /room${index+1}/play -> Out Channels: [${index*2}, ${index*2+1}]", style: const TextStyle(color: AtmosColors.textDim)),
                    trailing: const Icon(Icons.edit, color: AtmosColors.neonMagenta),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
