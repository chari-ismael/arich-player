import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import '../../core/l10n.dart';
import '../../core/theme.dart';
import '../../providers/language_provider.dart';
import 'focusable_ink.dart';
import '../screens/downloads_screen.dart';
import '../screens/epg_screen.dart';
import '../screens/favorites_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/stats_screen.dart';

class MoreMenuSheet extends StatelessWidget {
  final VoidCallback? onSettingsClosed;

  const MoreMenuSheet({super.key, this.onSettingsClosed});

  static Future<void> show(BuildContext context, {VoidCallback? onSettingsClosed}) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => MoreMenuSheet(onSettingsClosed: onSettingsClosed),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<LanguageProvider>().l10n;
    final isTizen = Platform.operatingSystem == 'tizen';
    final bottom = MediaQuery.viewPaddingOf(context).bottom;

    final items = <_MoreItem>[
      _MoreItem(Icons.settings_rounded, AppTheme.violet, l.t('settings_title'), l.t('settings_preferences'), () {
        Navigator.pop(context);
        Navigator.push(
          context,
          PageRouteBuilder(
            pageBuilder: (_, __, ___) => const SettingsScreen(),
            transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
          ),
        ).then((_) => onSettingsClosed?.call());
      }),
      _MoreItem(Icons.favorite_rounded, AppTheme.red, l.t('nav_favorites'), l.t('favorites_subtitle'), () {
        Navigator.pop(context);
        Navigator.push(context, _fade(const FavoritesScreen()));
      }),
      _MoreItem(Icons.calendar_view_week_rounded, AppTheme.secondary, l.t('nav_tv_guide'), l.t('epg_subtitle'), () {
        Navigator.pop(context);
        Navigator.push(context, _fade(EpgScreen()));
      }),
      _MoreItem(Icons.download_rounded, AppTheme.secondary, l.t('downloads_title'), l.t('settings_my_downloads'), () {
        Navigator.pop(context);
        Navigator.push(context, _fade(const DownloadsScreen()));
      }),
      _MoreItem(Icons.bar_chart_rounded, AppTheme.gold, l.t('nav_stats'), l.t('stats_subtitle'), () {
        Navigator.pop(context);
        Navigator.push(context, _fade(const StatsScreen()));
      }),
    ];

    Widget sheet = Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.72,
      ),
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(isTizen ? 0.97 : 0.55),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withOpacity(0.10)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.violet.withOpacity(0.12),
            blurRadius: 32,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Row(
              children: [
                Text(
                  l.t('nav_more'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
                const Spacer(),
                FocusableInk(
                  onTap: () => Navigator.pop(context),
                  borderRadius: 10,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.close_rounded, color: Colors.white54, size: 16),
                  ),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: EdgeInsets.fromLTRB(12, 4, 12, 12 + bottom),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 6),
              itemBuilder: (_, i) {
                final item = items[i];
                return FocusableInk(
                  onTap: item.onTap,
                  borderRadius: 14,
                  focusColor: item.color,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withOpacity(0.06)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: item.color.withOpacity(0.14),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: item.color.withOpacity(0.22)),
                          ),
                          child: Icon(item.icon, color: item.color, size: 18),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.subtitle,
                                style: const TextStyle(
                                  color: AppTheme.textSecondary,
                                  fontSize: 11,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        Icon(Icons.chevron_right_rounded, color: item.color.withOpacity(0.5), size: 18),
                      ],
                    ),
                  ),
                ).animate(delay: (i * 35).ms).fadeIn(duration: 220.ms).slideY(begin: 0.04, end: 0);
              },
            ),
          ),
        ],
      ),
    );

    if (!isTizen) {
      sheet = ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: sheet,
        ),
      );
    }

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom > 0 ? 0 : 8),
        child: sheet,
      ),
    );
  }

  static PageRouteBuilder<T> _fade<T>(Widget page) => PageRouteBuilder<T>(
        pageBuilder: (_, __, ___) => page,
        transitionsBuilder: (_, a, __, c) => FadeTransition(opacity: a, child: c),
      );
}

class _MoreItem {
  final IconData icon;
  final Color color;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _MoreItem(this.icon, this.color, this.label, this.subtitle, this.onTap);
}
