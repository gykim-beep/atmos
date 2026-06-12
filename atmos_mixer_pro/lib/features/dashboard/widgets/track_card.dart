import 'package:flutter/material.dart';
import 'package:atmos_mixer_pro/core/theme/colors.dart';
import 'package:atmos_mixer_pro/src/rust/common/config.dart';
import 'package:atmos_mixer_pro/src/rust/api/simple.dart' as rust_api;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:atmos_mixer_pro/core/state/global_state.dart';

final deviceChannelsProvider = FutureProvider<List<String>>((ref) async {
  final config = ref.watch(configProvider);
  if (config?.deviceName == null) return ['Ch 1', 'Ch 2'];
  try {
    return await rust_api.apiGetDeviceChannelNames(deviceName: config!.deviceName!);
  } catch (e) {
    return ['Ch 1', 'Ch 2'];
  }
});

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
  late TextEditingController _nameController;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.track.name);
  }

  @override
  void didUpdateWidget(TrackCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.track.name != widget.track.name && _nameController.text != widget.track.name) {
      _nameController.text = widget.track.name;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final engineState = ref.watch(engineStateProvider);
    final isPlaying = engineState.playingTrackIds.contains(widget.track.id);

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: AppColors.background.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: widget.accentColor.withValues(alpha: 0.3)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Row 1: Controls & Name
          Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 4.0),
                child: IconButton(
                  icon: Icon(isPlaying ? Icons.stop : Icons.play_arrow),
                  color: isPlaying ? const Color(0xFF8B0000) : const Color(0xFF1E6B22),
                  iconSize: 22,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    if (isPlaying) {
                      widget.onStop?.call();
                    } else {
                      widget.onPlay?.call();
                    }
                  },
                  tooltip: isPlaying ? '정지' : '재생',
                ),
              ),
              Expanded(
                child: TextField(
                  controller: _nameController,
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
              IconButton(
                icon: Icon(
                  Icons.all_inclusive,
                  shadows: widget.track.isLoop 
                      ? [Shadow(color: widget.accentColor, blurRadius: 8)] 
                      : null,
                ),
                color: widget.track.isLoop ? widget.accentColor : AppColors.darkGrey,
                iconSize: 20,
                onPressed: () => widget.onLoopChanged?.call(!widget.track.isLoop),
                tooltip: '무한 루프 (BGM)',
              ),
              const SizedBox(width: 8),
              Text(
                widget.track.outputStereo 
                    ? 'Ext. Out: ${widget.track.outputChannel}/${widget.track.outputChannel + 1}' 
                    : 'Ext. Out: ${widget.track.outputChannel}',
                style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
              ),
            ],
          ),
              ],
            ),
          ),
          ],
        ),
      ),
    );
  }
}

typedef VoidChannel = void Function();
