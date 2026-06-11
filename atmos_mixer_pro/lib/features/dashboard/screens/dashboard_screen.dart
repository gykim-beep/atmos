import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/colors.dart';
import '../../settings/widgets/preferences_modal.dart';
import '../../../core/state/global_state.dart';
import '../widgets/room_card.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GlobalState>();
    
    return Scaffold(
      backgroundColor: AtmosColors.background,
      body: Column(
        children: [
          _buildGlobalHeader(context, state),
          Expanded(
            child: _buildRoomPanel(state),
          ),
          _buildSystemLog(state),
        ],
      ),
    );
  }

  Widget _buildGlobalHeader(BuildContext context, GlobalState state) {
    return Container(
      height: 60,
      color: AtmosColors.header,
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          const Text("Atmos Mixer Pro", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const Spacer(),
          _buildHeaderButton("Theme Start", AtmosColors.buttonStart, Icons.play_arrow, () {}),
          _buildHeaderButton("Panic Stop", AtmosColors.buttonPanic, Icons.stop, () {}),
          _buildHeaderButton("Reset", AtmosColors.buttonReset, Icons.refresh, () {}),
          _buildHeaderButton("Add Room", AtmosColors.buttonAdd, Icons.add, () {}),
          _buildHeaderButton("Settings", AtmosColors.buttonSettings, Icons.settings, () {
            showDialog(
              context: context,
              builder: (context) => const PreferencesModal(),
            );
          }),
          const SizedBox(width: 16),
          // Device Dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AtmosColors.background,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: Colors.white24),
            ),
            child: DropdownButton<String>(
              value: state.selectedDevice.isNotEmpty ? state.selectedDevice : null,
              dropdownColor: AtmosColors.header,
              underline: const SizedBox(),
              style: const TextStyle(color: Colors.white),
              icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
              items: state.availableDevices.map((d) => DropdownMenuItem(value: d, child: Text(d))).toList(),
              onChanged: (val) {},
            ),
          ),
          const SizedBox(width: 16),
          IconButton(
            icon: Icon(
              state.isEngineRunning ? Icons.power_settings_new : Icons.power_settings_new_outlined,
              color: state.isEngineRunning ? AtmosColors.logText : Colors.white54,
            ),
            onPressed: () => state.toggleEngine(),
            tooltip: "Toggle Audio Engine",
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderButton(String label, Color color, IconData icon, VoidCallback onPressed) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4.0),
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
        ),
        icon: Icon(icon, size: 16),
        label: Text(label),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildRoomPanel(GlobalState state) {
    return ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(16),
      itemCount: 4, // Dummy room count
      itemBuilder: (context, index) {
        return RoomCard(roomId: index + 1);
      },
    );
  }

  Widget _buildSystemLog(GlobalState state) {
    return Container(
      height: 155,
      width: double.infinity,
      color: AtmosColors.logBackground,
      padding: const EdgeInsets.all(8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("SYSTEM LOG", style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold)),
              InkWell(
                onTap: () => state.clearLogs(),
                child: const Text("Clear", style: TextStyle(color: Colors.white54, fontSize: 12)),
              ),
            ],
          ),
          const Divider(color: Colors.white24),
          Expanded(
            child: ListView.builder(
              itemCount: state.systemLogs.length,
              itemBuilder: (context, index) {
                return Text(
                  state.systemLogs[index],
                  style: const TextStyle(color: AtmosColors.logText, fontFamily: 'Courier', fontSize: 12),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
