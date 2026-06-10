import 'package:flutter/material.dart';
import '../../../core/theme/colors.dart';

class RoutingMatrix extends StatelessWidget {
  const RoutingMatrix({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text("Live Routing Matrix", style: TextStyle(color: AtmosColors.textMain, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black45,
              border: Border.all(color: AtmosColors.neonCyan.withOpacity(0.3)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 8,
                crossAxisSpacing: 4,
                mainAxisSpacing: 4,
              ),
              itemCount: 32, // example grid
              itemBuilder: (context, index) {
                final isActive = index % 5 == 0;
                return Container(
                  decoration: BoxDecoration(
                    color: isActive ? AtmosColors.neonCyan : Colors.transparent,
                    border: Border.all(color: isActive ? Colors.transparent : AtmosColors.textDim.withOpacity(0.2)),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Center(
                    child: Text(
                      "${index + 1}",
                      style: TextStyle(
                        color: isActive ? Colors.black : AtmosColors.textDim,
                        fontSize: 10,
                        fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}
