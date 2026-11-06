import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/theme/weather_palette.dart';
import '../../../core/widgets/app_motion.dart';
import '../../../routing/app_routes.dart';
import '../../alerts/application/alert_tap_controller.dart';
import '../../alerts/presentation/alerts_tab.dart';
import '../../dashboard/application/dashboard_providers.dart';
import '../../location/presentation/locations_tab.dart';
import 'dashboard_home_tab.dart';

/// Width at which the dashboard switches from a bottom navigation bar to the
/// permanent sidebar.
const double _kSidebarBreakpoint = 900;

/// Post-authentication shell for the dashboard pipeline.
///
/// Hosts the three pipeline tabs (home weather, alerts, location map) in an
/// [IndexedStack]. Profile is reachable from the header. On wide viewports the
/// bottom bar is replaced by a persistent sidebar; both drive the same tab
/// index, so navigation behavior is identical on either layout.
class DashboardShell extends ConsumerStatefulWidget {
  const DashboardShell({super.key});

  @override
  ConsumerState<DashboardShell> createState() => _DashboardShellState();
}

class _DashboardShellState extends ConsumerState<DashboardShell> {
  int _index = 0;
  final GlobalKey<DashboardHomeTabState> _homeKey =
      GlobalKey<DashboardHomeTabState>();

  static const List<String> _titles = ['Weather', 'Alerts', 'Map'];

  @override
  void initState() {
    super.initState();
    // A tap that arrived before this shell existed (cold start from a
    // notification) is still pending, so open it on the first frame rather
    // than waiting for another tap.
    WidgetsBinding.instance.addPostFrameCallback((_) => _openPendingTap());
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AlertTapState>(alertTapControllerProvider, (previous, next) {
      if (next.fingerprint != previous?.fingerprint) _openPendingTap();
    });

    final pages = <Widget>[
      DashboardHomeTab(
        key: _homeKey,
        onOpenLocations: () => _select(2),
        onOpenAlerts: () => _select(1),
      ),
      const AlertsTab(),
      const LocationsTab(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= _kSidebarBreakpoint;
        final body = IndexedStack(index: _index, children: pages);

        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: WeatherPalette.canvasGradient,
          ),
          child: Scaffold(
            backgroundColor: Colors.transparent,
            appBar: _DashboardHeader(
              title: _titles[_index],
              wide: wide,
              onSelectSettings: () => context.push(RoutePath.settings),
              onSelectProfile: () => context.push(RoutePath.profile),
              onSelectAlerts: () => _select(1),
            ),
            body: wide
                ? Row(
                    children: [
                      _Sidebar(
                        selectedIndex: _index,
                        onSelect: _select,
                        onSelectSection: _scrollToSection,
                        onSelectSettings: () => context.push(RoutePath.settings),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: body),
                    ],
                  )
                : body,
            bottomNavigationBar: wide
                ? null
                : NavigationBar(
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    destinations: const [
                      NavigationDestination(
                        key: ValueKey('nav_weather'),
                        icon: Icon(Icons.home_outlined),
                        selectedIcon: Icon(Icons.home_rounded),
                        label: 'Weather',
                      ),
                      NavigationDestination(
                        key: ValueKey('nav_alerts'),
                        icon: Icon(Icons.warning_amber_outlined),
                        selectedIcon: Icon(Icons.warning_amber_rounded),
                        label: 'Alerts',
                      ),
                      NavigationDestination(
                        key: ValueKey('nav_locations'),
                        icon: Icon(Icons.map_outlined),
                        selectedIcon: Icon(Icons.map_rounded),
                        label: 'Map',
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  /// Jumps to a section that already exists on the home tab.
  ///
  /// Hourly and Daily are sections of the dashboard, not separate screens, so
  /// the sidebar links scroll to them instead of routing anywhere new.
  void _scrollToSection(DashboardSection section) {
    _select(0);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _homeKey.currentState?.scrollToSection(section);
    });
  }

  /// Navigates to the alert the user tapped, if one is pending.
  ///
  /// Pushed rather than replaced so the back gesture returns to the dashboard
  /// the user came from, and the tap is consumed either way so a rebuild (tab
  /// switch, rotation) cannot re-navigate behind the user's back.
  void _openPendingTap() {
    if (!mounted) return;
    final fingerprint = ref.read(alertTapControllerProvider).fingerprint;
    if (fingerprint == null) return;
    ref.read(alertTapControllerProvider.notifier).consume();
    context.push(RoutePath.alertDetailsFor(fingerprint));
  }
}

/// Modern top header: brand, current location and the account/settings actions.
///
/// The location line reads the same dashboard state the home tab renders, so
/// no location logic lives here.
class _DashboardHeader extends ConsumerWidget implements PreferredSizeWidget {
  const _DashboardHeader({
    required this.title,
    required this.wide,
    required this.onSelectSettings,
    required this.onSelectProfile,
    required this.onSelectAlerts,
  });

  final String title;
  final bool wide;
  final VoidCallback onSelectSettings;
  final VoidCallback onSelectProfile;
  final VoidCallback onSelectAlerts;

  @override
  Size get preferredSize => Size.fromHeight(wide ? 76 : 68);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final location = ref.watch(dashboardControllerProvider).location;
    final alertCount = ref.watch(dashboardControllerProvider).activeAlerts.length;

    final brand = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [WeatherPalette.cyan, WeatherPalette.blue],
            ),
            borderRadius: BorderRadius.circular(13),
            boxShadow: WeatherPalette.glow(WeatherPalette.cyan),
          ),
          padding: const EdgeInsets.all(9),
          child: const Icon(
            Icons.wb_cloudy_rounded,
            color: Color(0xFF04202E),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              AppConstants.appName,
              style: theme.textTheme.titleMedium?.copyWith(
                color: WeatherPalette.textPrimary,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.2,
              ),
            ),
            if (wide)
              Text(
                'Real-time weather, anytime, anywhere',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: WeatherPalette.textMuted),
              ),
          ],
        ),
      ],
    );

    final locationChip = location == null
        ? _HeaderChip(
            icon: Icons.location_off_outlined,
            label: 'Locating…',
          )
        : _HeaderChip(
            icon: Icons.location_on_rounded,
            label: location.label,
            accent: WeatherPalette.cyan,
          );

    return AppBar(
      toolbarHeight: wide ? 76 : 68,
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleSpacing: wide ? 20 : 12,
      title: Row(
        children: [
          brand,
          // On wide layouts the chip carries the location. On narrow ones the
          // dashboard's own location hero sits directly underneath, so
          // repeating it here would crowd the bar and duplicate the text.
          if (wide) ...[const SizedBox(width: 20), locationChip],
        ],
      ),
      actions: [
        if (alertCount > 0)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              onPressed: onSelectAlerts,
              tooltip: 'Active alerts',
              icon: Badge.count(
                count: alertCount,
                backgroundColor: WeatherPalette.danger,
                child: const Icon(Icons.warning_amber_rounded),
              ),
            ),
          ),
        IconButton(
          key: const ValueKey('settings_button'),
          icon: const Icon(Icons.settings_outlined),
          tooltip: 'Settings',
          onPressed: onSelectSettings,
        ),
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: IconButton(
            key: const ValueKey('profile_button'),
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile',
            onPressed: onSelectProfile,
          ),
        ),
      ],
    );
  }
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.icon, required this.label, this.accent});

  final IconData icon;
  final String label;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final color = accent ?? WeatherPalette.textSecondary;
    return Flexible(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 260),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: WeatherPalette.glassFill,
          borderRadius: BorderRadius.circular(WeatherPalette.radiusPill),
          border: Border.all(color: WeatherPalette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: WeatherPalette.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Persistent navigation rail for wide viewports.
///
/// Every entry is wired to something that already exists: the three pipeline
/// tabs, the two dashboard sections, and the Settings route.
class _Sidebar extends StatelessWidget {
  const _Sidebar({
    required this.selectedIndex,
    required this.onSelect,
    required this.onSelectSection,
    required this.onSelectSettings,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final ValueChanged<DashboardSection> onSelectSection;
  final VoidCallback onSelectSettings;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 232,
      color: WeatherPalette.canvasElevated,
      padding: const EdgeInsets.fromLTRB(14, 18, 14, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'MENU',
            style: TextStyle(
              color: WeatherPalette.textMuted,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          _SidebarItem(
            label: 'Home',
            icon: Icons.dashboard_rounded,
            selected: selectedIndex == 0,
            onTap: () => onSelect(0),
          ),
          _SidebarItem(
            label: 'Hourly',
            icon: Icons.schedule_rounded,
            selected: false,
            onTap: () => onSelectSection(DashboardSection.hourly),
          ),
          _SidebarItem(
            label: 'Daily',
            icon: Icons.calendar_month_rounded,
            selected: false,
            onTap: () => onSelectSection(DashboardSection.daily),
          ),
          _SidebarItem(
            label: 'Alerts',
            icon: Icons.warning_amber_rounded,
            selected: selectedIndex == 1,
            onTap: () => onSelect(1),
          ),
          _SidebarItem(
            label: 'Map',
            icon: Icons.map_rounded,
            selected: selectedIndex == 2,
            onTap: () => onSelect(2),
          ),
          const SizedBox(height: 10),
          _SidebarItem(
            label: 'Settings',
            icon: Icons.settings_outlined,
            selected: false,
            onTap: onSelectSettings,
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              'Weather risk assessment, not a prediction. Official warnings '
              'always take precedence.',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: WeatherPalette.textMuted, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}

class _SidebarItem extends StatefulWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<_SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color =
        widget.selected ? WeatherPalette.cyan : WeatherPalette.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: AppMotion.quick,
            curve: AppMotion.enter,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: widget.selected
                  ? WeatherPalette.cyan.withValues(alpha: 0.13)
                  : (_hovered
                      ? WeatherPalette.glassFill
                      : Colors.transparent),
              borderRadius:
                  BorderRadius.circular(WeatherPalette.radiusControl),
              border: Border.all(
                color: widget.selected
                    ? WeatherPalette.cyan.withValues(alpha: 0.32)
                    : Colors.transparent,
              ),
            ),
            child: Row(
              children: [
                Icon(widget.icon, size: 20, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: color,
                          fontWeight: widget.selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                  ),
                ),
                if (widget.selected)
                  Container(
                    width: 4,
                    height: 18,
                    decoration: BoxDecoration(
                      color: WeatherPalette.cyan,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}