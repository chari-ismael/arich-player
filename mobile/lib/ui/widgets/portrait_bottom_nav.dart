import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../providers/language_provider.dart';
import 'more_menu_sheet.dart';

/// Barre de navigation basse portrait — style Prime Video / Netflix.
class PortraitBottomNav extends StatelessWidget {
  final int activeTab;
  final bool hideLive;
  final bool hideMovies;
  final bool hideSeries;
  final ValueChanged<int> onTabTap;
  final VoidCallback? onSettingsClosed;

  const PortraitBottomNav({
    super.key,
    required this.activeTab,
    required this.hideLive,
    required this.hideMovies,
    required this.hideSeries,
    required this.onTabTap,
    this.onSettingsClosed,
  });

  @override
  Widget build(BuildContext context) {
    final l = context.read<LanguageProvider>().l10n;
    final isTizen = Platform.operatingSystem == 'tizen';

    final tabs = <({int index, IconData icon, String label})>[
      (index: 0, icon: Icons.home_rounded, label: l.t('nav_home')),
      if (!hideLive) (index: 1, icon: Icons.live_tv_rounded, label: l.t('nav_live')),
      if (!hideMovies) (index: 2, icon: Icons.movie_rounded, label: l.t('nav_movies')),
      if (!hideSeries) (index: 3, icon: Icons.tv_rounded, label: l.t('nav_series')),
    ];

    Widget inner = Container(
      decoration: BoxDecoration(
        color: const Color(0xFF06060F).withOpacity(isTizen ? 0.97 : 0.82),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 58,
          child: Row(
            children: [
              ...tabs.map((t) {
                final active = activeTab == t.index;
                return Expanded(
                  child: _NavItem(
                    icon: t.icon,
                    label: t.label,
                    active: active,
                    onTap: () => onTabTap(t.index),
                  ),
                );
              }),
              Expanded(
                child: _NavItem(
                  icon: Icons.more_horiz_rounded,
                  label: l.t('nav_more'),
                  active: false,
                  onTap: () => MoreMenuSheet.show(context, onSettingsClosed: onSettingsClosed),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (isTizen) return ClipRect(child: inner);
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: inner,
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: AppTheme.violet.withOpacity(0.12),
        highlightColor: Colors.transparent,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: active ? AppTheme.violet.withOpacity(0.16) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                size: 20,
                color: active ? AppTheme.gold : Colors.white38,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 9.5,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? AppTheme.gold : Colors.white38,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
