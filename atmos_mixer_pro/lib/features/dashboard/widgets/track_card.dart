import 'package:flutter/material.dart';
import 'package:atmos_mixer_pro/core/theme/colors.dart';
import 'package:atmos_mixer_pro/src/rust/common/config.dart';
import 'vu_meter.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atmos_mixer_pro/core/state/global_state.dart';

class TrackCard extends ConsumerStatefulWidget {
  final TrackConfig track;
  final Color accentColor;
  final VoidChannel? onPlay;
  final VoidChannel? onStop;
  final VoidChannel? onDelete;
  final ValueChanged<double>? onVolumeChanged;
  final ValueChanged<bool>? onLoopChanged;
  final ValueChanged<String>? onNameChanged;
  final ValueChanged<int>? onOutputChanged;

  const TrackCard({
    super.key,
    required this.track,
    required this.accentColor,
    this.onPlay,
    this.onStop,
    this.onDelete,
    this.onVolumeChanged,
    this.onLoopChanged,
    this.onNameChanged,
    this.onOutputChanged,
  });

  @override
  ConsumerState<TrackCard> createState() => _TrackCardState();
}

class _TrackCardState extends ConsumerState<TrackCard> {
  bool _isPlaying = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Controls & Name
          Row(
            children: [
              IconButton(
                icon: Icon(_isPlaying ? Icons.stop : Icons.play_arrow),
                color: _isPlaying ? const Color(0xFF8B0000) : const Color(0xFF1E6B22),
                iconSize: 20,
                onPressed: () {
                  if (_isPlaying) {
                    widget.onStop?.call();
                  } else {
                    widget.onPlay?.call();
                  }
                  setState(() => _isPlaying = !_isPlaying);
                },
                tooltip: _isPlaying ? '정지' : '재생',
              ),
              Expanded(
                child: TextField(
                  controller: TextEditingController(text: widget.track.name),
                  style: const TextStyle(color: AppColors.textPrimary, fontSize: 14),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    border: InputBorder.none,
                  ),
                  onSubmitted: widget.onNameChanged,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: const Color(0xFFCC0000),
                iconSize: 18,
                onPressed: widget.onDelete,
                tooltip: '삭제',
              ),
            ],
          ),
          // Row 2: Volume & Settings
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: widget.accentColor,
                    inactiveTrackColor: AppColors.darkGrey,
                    thumbColor: widget.accentColor,
                    trackHeight: 2.0,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
                  ),
                  child: Slider(
                    value: widget.track.volume,
                    min: 0.0,
                    max: 1.0,
                    onChanged: widget.onVolumeChanged,
                  ),
                ),
              ),
              Text(
                '${(widget.track.volume * 100).toInt()}%',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
              const SizedBox(width: 8),
              Tooltip(
                message: '무한 루프 (BGM)',
                child: Switch(
                  value: widget.track.isLoop,
                  onChanged: widget.onLoopChanged,
                  activeThumbColor: widget.accentColor,
                ),
              ),
              const SizedBox(width: 8),
              DropdownButtonHideUnderline(
                child: Builder(
                  builder: (context) {
                    ref.watch(routingMatrixProvider); // Trigger rebuild on matrix change
                    final labels = ref.read(routingMatrixProvider.notifier).activeChannelLabels;
                    final items = labels.map((label) {
                      int val = int.parse(label.split('/').first);
                      return DropdownMenuItem<int>(
                        value: val,
                        child: Text('🔌 Out $label'),
                      );
                    }).toList();
                    
                    // Ensure current value exists
                    if (!items.any((item) => item.value == widget.track.outputChannel)) {
                      items.add(DropdownMenuItem<int>(
                        value: widget.track.outputChannel,
                        child: Text('🔌 Out ${widget.track.outputChannel} (Off)'),
                      ));
                    }
                    
                    return DropdownButton<int>(
                      value: widget.track.outputChannel,
                      icon: const Icon(Icons.arrow_drop_down, color: AppColors.textSecondary, size: 16),
                      isDense: true,
                      dropdownColor: AppColors.cardSurface,
                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 10),
                      items: items,
                      onChanged: (val) {
                        if (val != null) {
                          widget.onOutputChanged?.call(val);
                        }
                      },
                    );
                  }
                ),
              ),
            ],
          ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          NeonVUMeter(outputChannel: widget.track.outputChannel),
        ],
      ),
    );
  }
}

typedef VoidChannel = void Function();
