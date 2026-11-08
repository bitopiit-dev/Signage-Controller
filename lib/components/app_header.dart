import 'dart:ui';
import 'package:flutter/material.dart';
import '../core/constants.dart';
import '../widgets/digital_clock.dart';

class ProCommandHeader extends StatelessWidget {
  final bool serverRunning;
  final String localIp;
  final int activePort;
  final int totalDevices;
  final int onlineCount;
  final int offlineCount;
  final String serverLoad;
  final VoidCallback? onEmergencyBroadcast;
  final VoidCallback? onForceSync;
  final VoidCallback? onStopAll;
  final VoidCallback? onScreenshotAll;
  final VoidCallback? onRefreshIp;
  final VoidCallback? onClearCache;
  final Function(String)? onCardTap;
  final bool emergencyActive;
  final String activeFilter;

  const ProCommandHeader({
    super.key,
    required this.serverRunning,
    required this.localIp,
    required this.activePort,
    this.totalDevices = 0,
    this.onlineCount = 0,
    this.offlineCount = 0,
    this.serverLoad = '0.4% CPU',
    this.onEmergencyBroadcast,
    this.onForceSync,
    this.onStopAll,
    this.onScreenshotAll,
    this.onRefreshIp,
    this.onClearCache,
    this.onCardTap,
    this.emergencyActive = false,
    this.activeFilter = 'total',
  });

  @override
  Widget build(BuildContext context) {
    return GlassmorphicContainer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3,
              vertical: AppSpacing.s2,
            ),
            child: Row(
              children: [
                // Branding Area
                _buildBranding(context),
                const SizedBox(width: AppSpacing.s3),

                // Summary Cards (scroll horizontally on narrow screens)
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        SummaryCard(
                          label: 'TOTAL DEVICES',
                          value: '$totalDevices',
                          icon: Icons.devices,
                          selected: activeFilter == 'total',
                          onTap: () => onCardTap?.call('total'),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        SummaryCard(
                          label: 'ACTIVE NODES',
                          value: '$onlineCount',
                          icon: Icons.hub,
                          color: AppColors.successEmerald,
                          selected: activeFilter == 'active',
                          onTap: () => onCardTap?.call('active'),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        SummaryCard(
                          label: 'CRITICAL/OFFLINE',
                          value: '$offlineCount',
                          icon: Icons.gpp_maybe,
                          color: AppColors.dangerRose,
                          selected: activeFilter == 'critical',
                          onTap: () => onCardTap?.call('critical'),
                        ),
                        const SizedBox(width: AppSpacing.s2),
                        SummaryCard(
                          label: 'SERVER UPTIME',
                          value: serverLoad,
                          icon: Icons.speed,
                          useMono: true,
                          color: serverRunning ? null : AppColors.dangerRose,
                          onTap: () => onCardTap?.call('load'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.s2),

                // System Info Stack
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const DigitalClock(),
                    const SizedBox(height: 4),
                    _buildIpBadge(),
                  ],
                ),
              ],
            ),
          ),
          
          const Divider(height: 1, color: AppColors.glassWhite),
          
          // Action Bar
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s3,
              vertical: 12,
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
              children: [
                ButtonGroup(
                  title: 'SYSTEM',
                  actions: [
                    ButtonAction(label: 'Refresh IP', icon: Icons.refresh, onTap: onRefreshIp),
                    ButtonAction(label: 'Force Sync', icon: Icons.sync, onTap: onForceSync),
                  ],
                ),
                const SizedBox(width: AppSpacing.s3),
                ButtonGroup(
                  title: 'BROADCAST',
                  actions: [
                    ButtonAction(
                      label: emergencyActive ? 'End Emergency' : 'Emergency Broadcast',
                      icon: emergencyActive ? Icons.campaign_outlined : Icons.campaign,
                      onTap: onEmergencyBroadcast,
                      isDanger: true,
                      isActive: emergencyActive,
                    ),
                    ButtonAction(label: 'Stop All', icon: Icons.stop_circle, onTap: onStopAll),
                  ],
                ),
                const SizedBox(width: AppSpacing.s3),
                ButtonGroup(
                  title: 'TOOLS',
                  actions: [
                    ButtonAction(label: 'Screenshot All', icon: Icons.screenshot_monitor, onTap: onScreenshotAll),
                    ButtonAction(label: 'Clear Cache', icon: Icons.cleaning_services, onTap: onClearCache),
                  ],
                ),
                if (emergencyActive) ...[
                  const SizedBox(width: AppSpacing.s3),
                  const _EmergencyLiveChip(),
                ],
              ],
            ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBranding(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            gradient: AppColors.primaryGradient,
            borderRadius: BorderRadius.circular(AppRadius.standard),
            boxShadow: [AppShadows.glowBlue],
          ),
          child: const Icon(Icons.dvr, color: Colors.white, size: 28),
        ),
        const SizedBox(width: AppSpacing.s2),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'PRO COMMAND',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AppColors.accentCyan,
                    letterSpacing: 2.0,
                    fontSize: 10,
                  ),
            ),
            RichText(
              text: const TextSpan(
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                  color: Colors.white,
                  fontFamily: 'Inter',
                ),
                children: [
                  TextSpan(text: 'SIGNAGE'),
                  TextSpan(
                    text: 'CORE',
                    style: TextStyle(
                      fontWeight: FontWeight.w300,
                      color: Colors.white54,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIpBadge() {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(4),
      child: InkWell(
        onTap: onRefreshIp,
        borderRadius: BorderRadius.circular(4),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppColors.glassWhite),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: serverRunning ? AppColors.successEmerald : AppColors.dangerRose,
                ),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.terminal, size: 12, color: AppColors.accentCyan),
              const SizedBox(width: 8),
              Text(
                serverRunning ? 'http://$localIp:$activePort' : 'SERVER OFFLINE',
                style: const TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 11,
                  color: AppColors.accentCyan,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GlassmorphicContainer extends StatelessWidget {
  final Widget child;
  const GlassmorphicContainer({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          decoration: BoxDecoration(
            color: AppColors.surfaceNavy.withOpacity(0.8),
            border: const Border(
              bottom: BorderSide(color: AppColors.glassWhite, width: 1.5),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

class SummaryCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final VoidCallback? onTap;
  final bool useMono;
  final bool selected;

  const SummaryCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.onTap,
    this.useMono = false,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.standard),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: selected
                ? (color ?? AppColors.accentCyan).withOpacity(0.08)
                : Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(AppRadius.standard),
            border: Border.all(
              color: selected
                  ? (color ?? AppColors.accentCyan).withOpacity(0.35)
                  : AppColors.glassWhite,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: color ?? Colors.white54),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 8,
                      color: Colors.white38,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.0,
                    ),
                  ),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: color ?? Colors.white,
                      fontFamily: useMono ? 'JetBrains Mono' : 'Inter',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ButtonGroup extends StatelessWidget {
  final String title;
  final List<ButtonAction> actions;

  const ButtonGroup({
    super.key,
    required this.title,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black12,
        borderRadius: BorderRadius.circular(AppRadius.button),
        border: Border.all(color: AppColors.glassWhite),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w900,
                color: Colors.white24,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Container(width: 1, height: 24, color: AppColors.glassWhite),
          ...actions.map((action) => _buildActionButton(action)),
        ],
      ),
    );
  }

  Widget _buildActionButton(ButtonAction action) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: action.onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: action.isActive ? AppColors.dangerRose.withOpacity(0.18) : null,
            border: const Border(left: BorderSide(color: AppColors.glassWhite)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                action.icon,
                size: 14,
                color: action.isDanger ? AppColors.dangerRose : AppColors.accentCyan,
              ),
              const SizedBox(width: 8),
              Text(
                action.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: action.isDanger ? AppColors.dangerRose : Colors.white70,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class ButtonAction {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isDanger;
  final bool isActive;

  ButtonAction({
    required this.label,
    required this.icon,
    this.onTap,
    this.isDanger = false,
    this.isActive = false,
  });
}

class _EmergencyLiveChip extends StatefulWidget {
  const _EmergencyLiveChip();

  @override
  State<_EmergencyLiveChip> createState() => _EmergencyLiveChipState();
}

class _EmergencyLiveChipState extends State<_EmergencyLiveChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
        ..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.45, end: 1.0).animate(_c),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.dangerRose.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.dangerRose.withOpacity(0.6)),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.warning_amber_rounded, size: 14, color: AppColors.dangerRose),
            SizedBox(width: 6),
            Text('EMERGENCY ON AIR',
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, color: AppColors.dangerRose, letterSpacing: 1)),
          ],
        ),
      ),
    );
  }
}
