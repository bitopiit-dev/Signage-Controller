import 'package:flutter/material.dart';
import '../core/constants.dart';

class CommandCenterDock extends StatelessWidget {
  final bool isPaused;
  final bool isStopped;
  final bool shuffle;
  final bool repeatOne;
  final double volume;
  final VoidCallback onPlayPause;
  final VoidCallback onStop;
  final VoidCallback onNext;
  final VoidCallback onPrev;
  final VoidCallback? onSeekBack;
  final VoidCallback? onSeekForward;
  final VoidCallback onShuffleToggle;
  final VoidCallback onRepeatToggle;
  final VoidCallback onSync;
  final VoidCallback onRebootAll;
  final ValueChanged<double> onVolumeChanged;

  const CommandCenterDock({
    super.key,
    required this.isPaused,
    this.isStopped = false,
    required this.shuffle,
    required this.repeatOne,
    required this.volume,
    required this.onPlayPause,
    required this.onStop,
    required this.onNext,
    required this.onPrev,
    this.onSeekBack,
    this.onSeekForward,
    required this.onShuffleToggle,
    required this.onRepeatToggle,
    required this.onSync,
    required this.onRebootAll,
    required this.onVolumeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s1, left: AppSpacing.s2, right: AppSpacing.s2),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.s2),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3, vertical: AppSpacing.s2),
          decoration: BoxDecoration(
            color: AppColors.surfaceNavy.withOpacity(0.95),
            borderRadius: BorderRadius.circular(AppRadius.large * 2),
            border: Border.all(color: AppColors.glassWhite, width: 1.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.6),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Playlist Group
            _ControlGroup(
              children: [
                _DockButton(
                  icon: shuffle ? Icons.shuffle : Icons.trending_flat,
                  onPressed: onShuffleToggle,
                  isActive: shuffle,
                  tooltip: 'Shuffle',
                ),
                _DockButton(
                  icon: repeatOne ? Icons.repeat_one : Icons.repeat,
                  onPressed: onRepeatToggle,
                  isActive: repeatOne,
                  tooltip: 'Repeat',
                ),
              ],
            ),
            const _GroupDivider(),
            
            // Navigation Group
            _ControlGroup(
              children: [
                _DockButton(
                  icon: Icons.skip_previous_rounded,
                  onPressed: onPrev,
                  tooltip: 'Previous',
                ),
                _DockButton(
                  icon: Icons.replay_10_rounded,
                  onPressed: onSeekBack ?? () {},
                  tooltip: 'Back 10 s (all screens)',
                ),
                _DockButton(
                  icon: Icons.forward_10_rounded,
                  onPressed: onSeekForward ?? () {},
                  tooltip: 'Forward 10 s (all screens)',
                ),
                _DockButton(
                  icon: Icons.skip_next_rounded,
                  onPressed: onNext,
                  tooltip: 'Next',
                ),
              ],
            ),
            const _GroupDivider(),

            // Primary Playback
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
              child: _MainActionCircle(
                isPaused: isPaused,
                onPressed: onPlayPause,
              ),
            ),
            _StateLabel(isStopped: isStopped, isPaused: isPaused),
            const SizedBox(width: AppSpacing.s1),
            _DockButton(
              icon: Icons.stop_rounded,
              onPressed: onStop,
              color: AppColors.dangerRose,
              isActive: isStopped,
              tooltip: 'Stop (all screens to standby)',
            ),
            
            const _GroupDivider(),

            // Volume Control
            SizedBox(
              width: 200,
              child: Row(
                children: [
                  Icon(
                    volume == 0 ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                    size: 18,
                    color: Colors.white54,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 3,
                        thumbColor: Colors.white,
                        activeTrackColor: AppColors.actionBlue,
                        inactiveTrackColor: Colors.white10,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 4),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                      ),
                      child: Slider(
                        value: volume.clamp(0.0, 1.0),
                        onChanged: onVolumeChanged,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 34,
                    child: Text(
                      '${(volume * 100).round()}%',
                      style: const TextStyle(fontSize: 10, fontFamily: 'JetBrains Mono', color: Colors.white54),
                    ),
                  ),
                ],
              ),
            ),
            
            const _GroupDivider(),

            // System Group
            _ControlGroup(
              children: [
                _DockButton(
                  icon: Icons.sync_rounded,
                  onPressed: onSync,
                  color: AppColors.successEmerald,
                  tooltip: 'Force re-sync all screens',
                ),
                _DockButton(
                  icon: Icons.power_settings_new_rounded,
                  onPressed: onRebootAll,
                  color: AppColors.dangerRose,
                  tooltip: 'Reboot All Devices',
                ),
              ],
            ),
          ],
        ),
      ),
        ),
      ),
    );
  }
}

class _StateLabel extends StatelessWidget {
  final bool isStopped;
  final bool isPaused;
  const _StateLabel({required this.isStopped, required this.isPaused});

  @override
  Widget build(BuildContext context) {
    final label = isStopped ? 'STANDBY' : (isPaused ? 'PAUSED' : 'ON AIR');
    final color = isStopped
        ? Colors.white38
        : (isPaused ? AppColors.warningAmber : AppColors.successEmerald);
    return Container(
      width: 76,
      padding: const EdgeInsets.symmetric(vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w900, letterSpacing: 1, color: color)),
    );
  }
}

class _ControlGroup extends StatelessWidget {
  final List<Widget> children;
  const _ControlGroup({required this.children});

  @override
  Widget build(BuildContext context) {
    return Row(children: children);
  }
}

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 24,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
      color: AppColors.glassWhite,
    );
  }
}

class _DockButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isActive;
  final Color? color;
  final String tooltip;

  const _DockButton({
    required this.icon,
    required this.onPressed,
    this.isActive = false,
    this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final Color buttonColor = color ?? (isActive ? AppColors.actionBlue : Colors.white70);

    return Tooltip(
      message: tooltip,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(AppRadius.button),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(AppRadius.button),
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s1),
              decoration: BoxDecoration(
                color: isActive ? AppColors.actionBlue.withOpacity(0.15) : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.button),
                boxShadow: isActive ? [
                  BoxShadow(
                    color: AppColors.actionBlue.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ] : null,
              ),
              child: Icon(
                icon,
                color: buttonColor,
                size: 22,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MainActionCircle extends StatelessWidget {
  final bool isPaused;
  final VoidCallback onPressed;

  const _MainActionCircle({
    required this.isPaused,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: isPaused ? 'Play / Go Live (all screens)' : 'Pause (all screens)',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [AppColors.actionBlue, Color(0xFF0077FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: [
                BoxShadow(
                  color: AppColors.actionBlue.withOpacity(0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                )
              ],
            ),
            child: Icon(
              isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              size: 34,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
