import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/colors.dart';
import '../../../core/theme/glass_container.dart';
import '../../settings/widgets/preferences_modal.dart';
import '../../../core/state/global_state.dart';
import '../widgets/channel_strip.dart';
import '../widgets/room_card.dart';
import '../widgets/routing_matrix.dart';
import '../widgets/vu_meter.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<GlobalState>();
    
    return Scaffold(
      backgroundColor: AtmosColors.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text("Atmos Mixer Pro", style: TextStyle(color: AtmosColors.neonCyan, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        actions: [
          IconButton(
            icon: Icon(
              state.isEngineRunning ? Icons.stop_circle : Icons.play_arrow,
              color: state.isEngineRunning ? AtmosColors.neonMagenta : AtmosColors.neonCyan,
            ),
            onPressed: () => state.toggleEngine(),
          ),
          IconButton(
            icon: const Icon(Icons.settings, color: AtmosColors.textMain),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => const PreferencesModal(),
              );
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: GlassContainer(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Channels", style: TextStyle(color: AtmosColors.textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(4, (index) => ChannelStrip(index: index)),
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text("Rooms", style: TextStyle(color: AtmosColors.textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: List.generate(3, (index) => Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8.0), child: RoomCard(roomId: index + 1)))),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 24),
            Expanded(
              flex: 1,
              child: GlassContainer(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    children: [
                      const Expanded(flex: 1, child: RoutingMatrix()),
                      const SizedBox(height: 24),
                      const Text("Master Bus", style: TextStyle(color: AtmosColors.textMain, fontSize: 20, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Expanded(
                        flex: 1,
                        child: Container(
                          width: 60,
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AtmosColors.neonMagenta.withOpacity(0.3)),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(8.0),
                            child: VuMeter(level: 0.75), // Initial master level test
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
