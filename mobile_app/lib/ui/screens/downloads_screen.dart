// lib/ui/screens/downloads_screen.dart
// Arich Player — Downloads Screen v2.0
// ─────────────────────────────────────────────────────────────────────────────
// Design inspiré Amazon Prime Video :
//   • Header avec compteur + taille totale + bouton Edit
//   • Tiles avec thumbnail large + infos + actions contextuelles
//   • Progress bar inline pour en cours
//   • Empty state premium
//   • Sections : en cours / disponibles / erreurs
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/l10n.dart';
import '../../core/tv_layout.dart';
import '../../providers/language_provider.dart';
import '../../services/download_service.dart';
import '../widgets/focusable_ink.dart';
import 'player_screen.dart';

class DownloadsScreen extends StatelessWidget {
  const DownloadsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: context.read<DownloadService>(),
      child: const _DownloadsBody(),
    );
  }
}

class _DownloadsBody extends StatefulWidget {
  const _DownloadsBody();
  @override
  State<_DownloadsBody> createState() => _DownloadsBodyState();
}

class _DownloadsBodyState extends State<_DownloadsBody> {
  String _totalSize = '';
  bool _editMode = false;
  final Set<String> _selected = {};

  @override
  void initState() {
    super.initState();
    _refreshSize();
  }

  Future<void> _refreshSize() async {
    final svc  = context.read<DownloadService>();
    final size = await svc.totalSizeLabel();
    if (mounted) setState(() => _totalSize = size);
  }

  void _play(DownloadItem item) {
    Navigator.push(context, PageRouteBuilder(
      pageBuilder: (_, a, __) => PlayerScreen(
        streamUrl:  'file://${item.localPath}',
        title:      item.displayTitle,
        streamIcon: item.streamIcon,
        streamId:   0,
        tabIndex:   item.tabIndex,
      ),
      transitionsBuilder: (_, a, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
        child: child,
      ),
      transitionDuration: const Duration(milliseconds: 280),
    ));
  }

  void _confirmDelete(DownloadItem item) {
    final l = context.read<LanguageProvider>().l10n;
    final svc = context.read<DownloadService>();
    _showConfirmSheet(
      title: context.read<LanguageProvider>().l10n.t('delete'),
      body: context.read<LanguageProvider>().l10n.t('downloads_delete_confirm'),
      confirmLabel: context.read<LanguageProvider>().l10n.t('downloads_delete'),
      danger: true,
      onConfirm: () { svc.delete(item.id); _refreshSize(); },
    );
  }

  void _confirmDeleteAll() {
    final l = context.read<LanguageProvider>().l10n;
    final svc = context.read<DownloadService>();
    _showConfirmSheet(
      title: context.read<LanguageProvider>().l10n.t('downloads_delete_all'),
      body: context.read<LanguageProvider>().l10n.t('downloads_delete_all_confirm'),
      confirmLabel: context.read<LanguageProvider>().l10n.t('downloads_delete_all'),
      danger: true,
      onConfirm: () { svc.deleteAllCompleted(); _refreshSize(); setState(() { _selected.clear(); _editMode = false; }); },
    );
  }

  void _showConfirmSheet({
    required String title, required String body,
    required String confirmLabel, required bool danger,
    required VoidCallback onConfirm,
  }) {
    showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => _ConfirmSheet(
        title: title, body: body,
        confirmLabel: confirmLabel, danger: danger,
        onConfirm: onConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l   = context.read<LanguageProvider>().l10n;
    final top = MediaQuery.paddingOf(context).top;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Consumer<DownloadService>(
        builder: (_, svc, __) {
          final all        = svc.items;
          final inProgress = all.where((i) =>
              i.status == DownloadStatus.downloading ||
              i.status == DownloadStatus.queued).toList();
          final done    = all.where((i) => i.isCompleted).toList();
          final errors  = all.where((i) => i.status == DownloadStatus.error).toList();
          final total   = done.length + inProgress.length;

          return Column(children: [
            // ── Header ───────────────────────────────────────────────────────
            _Header(
              top: top, l: l,
              totalCount: total,
              totalSize: _totalSize,
              hasItems: done.isNotEmpty,
              editMode: _editMode,
              selectedCount: _selected.length,
              onBack: () => Navigator.pop(context),
              onEdit: () => setState(() { _editMode = !_editMode; _selected.clear(); }),
              onDeleteSelected: () {
                for (final id in _selected) svc.delete(id);
                _refreshSize();
                setState(() { _selected.clear(); _editMode = false; });
              },
              onDeleteAll: _confirmDeleteAll,
            ),

            // ── Contenu ───────────────────────────────────────────────────────
            Expanded(
              child: all.isEmpty
                  ? _EmptyState(l: l)
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 40),
                      children: [
                        // En cours
                        if (inProgress.isNotEmpty) ...[
                          _SectionLabel(label: '${context.read<LanguageProvider>().l10n.t('downloads_in_progress')} · ${inProgress.length}',
                              color: AppTheme.violet),
                          ...inProgress.asMap().entries.map((e) => _DownloadTile(
                            item: e.value, editMode: false,
                            selected: false, l: l,
                            onPlay: null,
                            onCancel: () => svc.cancel(e.value.id),
                            onRetry: null, onDelete: null,
                            onSelect: null,
                            delay: e.key * 35,
                          )),
                          const SizedBox(height: 8),
                        ],
                        // Erreurs
                        if (errors.isNotEmpty) ...[
                          _SectionLabel(label: '${context.read<LanguageProvider>().l10n.t('downloads_errors')} · ${errors.length}',
                              color: AppTheme.danger),
                          ...errors.asMap().entries.map((e) => _DownloadTile(
                            item: e.value, editMode: _editMode,
                            selected: _selected.contains(e.value.id), l: l,
                            onPlay: null,
                            onCancel: () => svc.cancel(e.value.id),
                            onRetry: () => svc.retry(e.value.id),
                            onDelete: () => _confirmDelete(e.value),
                            onSelect: _editMode ? () => setState(() {
                              if (_selected.contains(e.value.id)) _selected.remove(e.value.id);
                              else _selected.add(e.value.id);
                            }) : null,
                            delay: e.key * 35,
                          )),
                          const SizedBox(height: 8),
                        ],
                        // Complétés
                        if (done.isNotEmpty) ...[
                          _SectionLabel(label: context.read<LanguageProvider>().l10n.t('downloads_completed'),
                              color: AppTheme.success),
                          ...done.asMap().entries.map((e) => _DownloadTile(
                            item: e.value, editMode: _editMode,
                            selected: _selected.contains(e.value.id), l: l,
                            onPlay: () => _play(e.value),
                            onCancel: null, onRetry: null,
                            onDelete: () => _confirmDelete(e.value),
                            onSelect: _editMode ? () => setState(() {
                              if (_selected.contains(e.value.id)) _selected.remove(e.value.id);
                              else _selected.add(e.value.id);
                            }) : null,
                            delay: e.key * 35,
                          )),
                        ],
                      ],
                    ),
            ),
          ]);
        },
      ),
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────
class _Header extends StatelessWidget {
  final double top;
  final AppL10n l;
  final int totalCount, selectedCount;
  final String totalSize;
  final bool hasItems, editMode;
  final VoidCallback onBack, onEdit, onDeleteSelected, onDeleteAll;

  const _Header({
    required this.top, required this.l,
    required this.totalCount, required this.selectedCount,
    required this.totalSize, required this.hasItems,
    required this.editMode,
    required this.onBack, required this.onEdit,
    required this.onDeleteSelected, required this.onDeleteAll,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.fromLTRB(6, top + 6, 16, 0),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.65),
            border: Border(bottom: BorderSide(
                color: Colors.white.withOpacity(0.07)))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Row 1 : nav + title + edit
            Row(children: [
              IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 18),
                onPressed: onBack),
              const SizedBox(width: 2),
              Expanded(child: Text(context.read<LanguageProvider>().l10n.t('downloads_title'),
                style: GoogleFonts.rajdhani(
                    color: Colors.white, fontSize: 20,
                    fontWeight: FontWeight.w700))),
              if (editMode && selectedCount > 0)
                FocusableInk(onTap: onDeleteSelected, borderRadius: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.danger.withOpacity(0.4))),
                    child: Text('Supprimer ($selectedCount)',
                        style: GoogleFonts.inter(
                            color: AppTheme.danger, fontSize: 12,
                            fontWeight: FontWeight.w600)))),
              if (hasItems) ...[
                const SizedBox(width: 8),
                FocusableInk(onTap: onEdit, borderRadius: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: editMode
                          ? AppTheme.violet.withOpacity(0.15)
                          : Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: editMode
                              ? AppTheme.violet.withOpacity(0.4)
                              : Colors.white.withOpacity(0.1))),
                    child: Text(editMode ? 'Terminé' : 'Éditer',
                        style: GoogleFonts.inter(
                            color: editMode ? AppTheme.violet : Colors.white70,
                            fontSize: 12, fontWeight: FontWeight.w600)))),
              ],
            ]),
            // Row 2 : stats
            if (totalCount > 0 || totalSize.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 2, 14, 10),
                child: Row(children: [
                  if (totalCount > 0) ...[
                    Text('$totalCount vidéo${totalCount > 1 ? 's' : ''}',
                        style: GoogleFonts.inter(
                            color: Colors.white54, fontSize: 12)),
                    if (totalSize.isNotEmpty) ...[
                      Text('  ·  ', style: GoogleFonts.inter(
                          color: Colors.white24, fontSize: 12)),
                      Icon(Icons.storage_rounded,
                          color: Colors.white38, size: 12),
                      const SizedBox(width: 4),
                      Text(totalSize, style: GoogleFonts.inter(
                          color: Colors.white54, fontSize: 12)),
                    ],
                  ],
                  const Spacer(),
                  if (hasItems && !editMode)
                    FocusableInk(onTap: onDeleteAll, borderRadius: 8,
                      child: Text(context.read<LanguageProvider>().l10n.t('downloads_delete_all'),
                          style: GoogleFonts.inter(
                              color: AppTheme.danger.withOpacity(0.7),
                              fontSize: 11,
                              fontWeight: FontWeight.w500))),
                ]),
              ),
          ]),
        ),
      ),
    );
  }
}

// ── Section label ─────────────────────────────────────────────────────────────
class _SectionLabel extends StatelessWidget {
  final String label; final Color color;
  const _SectionLabel({required this.label, required this.color});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Row(children: [
      Container(width: 3, height: 13,
        decoration: BoxDecoration(
          color: color, borderRadius: BorderRadius.circular(2),
          boxShadow: [BoxShadow(color: color.withOpacity(0.5), blurRadius: 4)])),
      const SizedBox(width: 8),
      Text(label, style: GoogleFonts.inter(
          color: color, fontSize: 11,
          fontWeight: FontWeight.w700, letterSpacing: 0.8)),
    ]),
  );
}

// ── Download tile ─────────────────────────────────────────────────────────────
class _DownloadTile extends StatelessWidget {
  final DownloadItem item;
  final AppL10n l;
  final bool editMode, selected;
  final int delay;
  final VoidCallback? onPlay, onCancel, onRetry, onDelete, onSelect;

  const _DownloadTile({
    required this.item, required this.l,
    required this.editMode, required this.selected,
    this.onPlay, this.onCancel, this.onRetry, this.onDelete, this.onSelect,
    this.delay = 0,
  });

  Color get _statusColor => switch (item.status) {
    DownloadStatus.completed  => AppTheme.success,
    DownloadStatus.error      => AppTheme.danger,
    DownloadStatus.paused     => AppTheme.gold,
    DownloadStatus.downloading => AppTheme.violet,
    DownloadStatus.queued     => Colors.white38,
  };

  IconData get _statusIcon => switch (item.status) {
    DownloadStatus.completed  => Icons.check_circle_rounded,
    DownloadStatus.error      => Icons.error_outline_rounded,
    DownloadStatus.paused     => Icons.pause_circle_rounded,
    DownloadStatus.downloading => Icons.downloading_rounded,
    DownloadStatus.queued     => Icons.hourglass_top_rounded,
  };

  String _statusLabel(AppL10n l) => switch (item.status) {
    DownloadStatus.completed  => item.sizeLabel,
    DownloadStatus.error      => 'Échec du téléchargement',
    DownloadStatus.paused     => 'En pause',
    DownloadStatus.downloading => item.progress > 0
        ? '${(item.progress * 100).toStringAsFixed(0)}%  ·  ${item.sizeLabel}'
        : 'Téléchargement…',
    DownloadStatus.queued     => 'En attente…',
  };

  @override
  Widget build(BuildContext context) {
    return FocusableInk(
      onTap: editMode ? onSelect : onPlay,
      borderRadius: 0,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.violet.withOpacity(0.1)
              : Colors.white.withOpacity(0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? AppTheme.violet.withOpacity(0.4)
                : Colors.white.withOpacity(0.07)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              // ── Checkbox edit mode ──
              if (editMode) ...[
                AnimatedContainer(
                  duration: 180.ms,
                  width: 22, height: 22,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    gradient: selected ? AppTheme.gradientPrimary : null,
                    color: selected ? null : Colors.white.withOpacity(0.07),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: selected
                          ? AppTheme.violet
                          : Colors.white.withOpacity(0.2),
                      width: selected ? 0 : 1.5)),
                  child: selected
                      ? const Icon(Icons.check_rounded, color: Colors.white, size: 13)
                      : null),
              ],

              // ── Thumbnail ──
              ClipRRect(
                borderRadius: BorderRadius.circular(9),
                child: SizedBox(
                  width: 90, height: 58,
                  child: item.streamIcon.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: item.streamIcon,
                          fit: BoxFit.cover,
                          memCacheWidth: 180,
                          placeholder: (_, __) => Container(
                              color: Colors.white.withOpacity(0.04)),
                          errorWidget: (_, __, ___) => _thumbFallback())
                      : _thumbFallback(),
                ),
              ),

              const SizedBox(width: 12),

              // ── Infos ──
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(item.title,
                        style: GoogleFonts.inter(
                            color: Colors.white, fontSize: 13.5,
                            fontWeight: FontWeight.w600),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (item.episodeTitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${item.seasonLabel ?? ''}  ${item.episodeTitle}',
                        style: GoogleFonts.inter(
                            color: Colors.white54, fontSize: 11),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                    const SizedBox(height: 6),
                    Row(children: [
                      Icon(_statusIcon, color: _statusColor, size: 12),
                      const SizedBox(width: 4),
                      Expanded(child: Text(_statusLabel(l),
                          style: GoogleFonts.inter(
                              color: _statusColor, fontSize: 11,
                              fontWeight: FontWeight.w500),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                    ]),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              // ── Actions ──
              if (!editMode)
                _ActionsMenu(
                  item: item, l: l,
                  onPlay: onPlay, onRetry: onRetry,
                  onDelete: onDelete, onCancel: onCancel),
            ]),
          ),

          // Progress bar pour en cours
          if (item.status == DownloadStatus.downloading ||
              item.status == DownloadStatus.paused)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
              child: LinearProgressIndicator(
                value: item.progress > 0 ? item.progress : null,
                backgroundColor: Colors.white.withOpacity(0.05),
                valueColor: AlwaysStoppedAnimation(
                    item.status == DownloadStatus.paused
                        ? AppTheme.gold : AppTheme.violet),
                minHeight: 3,
              ),
            ),
        ]),
      ),
    ).animate()
        .fadeIn(delay: Duration(milliseconds: delay), duration: 220.ms)
        .slideY(begin: 0.04, end: 0,
            delay: Duration(milliseconds: delay), duration: 240.ms);
  }

  Widget _thumbFallback() => Container(
    color: Colors.white.withOpacity(0.04),
    child: Center(child: Icon(
        item.tabIndex == 2 ? Icons.movie_rounded : Icons.tv_rounded,
        color: Colors.white12, size: 22)));
}

// ── Actions menu ──────────────────────────────────────────────────────────────
class _ActionsMenu extends StatelessWidget {
  final DownloadItem item;
  final AppL10n l;
  final VoidCallback? onPlay, onRetry, onDelete, onCancel;

  const _ActionsMenu({
    required this.item, required this.l,
    this.onPlay, this.onRetry, this.onDelete, this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    // Bouton play direct si complété
    if (item.isCompleted && onPlay != null) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        _ActionBtn(icon: Icons.play_arrow_rounded,
            color: AppTheme.violet, onTap: onPlay!),
        const SizedBox(width: 4),
        _MoreBtn(item: item, l: l, onDelete: onDelete),
      ]);
    }

    // Bouton retry si erreur
    if (item.status == DownloadStatus.error) {
      return Row(mainAxisSize: MainAxisSize.min, children: [
        if (onRetry != null)
          _ActionBtn(icon: Icons.refresh_rounded,
              color: AppTheme.gold, onTap: onRetry!),
        const SizedBox(width: 4),
        _MoreBtn(item: item, l: l, onDelete: onDelete),
      ]);
    }

    // Bouton cancel si en cours
    if (onCancel != null) {
      return _ActionBtn(icon: Icons.close_rounded,
          color: Colors.white38, onTap: onCancel!);
    }

    return const SizedBox.shrink();
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final Color color; final VoidCallback onTap;
  const _ActionBtn({required this.icon, required this.color, required this.onTap});
  @override
  Widget build(BuildContext context) => FocusableInk(onTap: onTap, borderRadius: 20,
    child: Container(
      width: 36, height: 36,
      decoration: BoxDecoration(
        color: color.withOpacity(0.13), shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.3))),
      child: Icon(icon, color: color, size: 17)));
}

class _MoreBtn extends StatelessWidget {
  final DownloadItem item; final AppL10n l; final VoidCallback? onDelete;
  const _MoreBtn({required this.item, required this.l, required this.onDelete});
  @override
  Widget build(BuildContext context) => FocusableInk(
    onTap: () => showModalBottomSheet(
      context: context, backgroundColor: Colors.transparent,
      builder: (_) => _ItemSheet(item: item, l: l, onDelete: onDelete)),
    borderRadius: 20,
    child: Container(
      width: 32, height: 32,
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.07), shape: BoxShape.circle),
      child: const Icon(Icons.more_vert_rounded, color: Colors.white54, size: 16)));
}

// ── Item bottom sheet ─────────────────────────────────────────────────────────
class _ItemSheet extends StatelessWidget {
  final DownloadItem item; final AppL10n l; final VoidCallback? onDelete;
  const _ItemSheet({required this.item, required this.l, required this.onDelete});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.08)))),
      child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Center(child: Container(width: 34, height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 16),
        Text(item.title, style: GoogleFonts.rajdhani(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        const SizedBox(height: 4),
        Text(item.sizeLabel, style: GoogleFonts.inter(
            color: Colors.white38, fontSize: 12)),
        const SizedBox(height: 16),
        if (onDelete != null)
          FocusableInk(
            onTap: () { Navigator.pop(context); onDelete?.call(); },
            borderRadius: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              decoration: BoxDecoration(
                color: AppTheme.danger.withOpacity(0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppTheme.danger.withOpacity(0.25))),
              child: Row(children: [
                Icon(Icons.delete_outline_rounded, color: AppTheme.danger, size: 18),
                const SizedBox(width: 12),
                Text(context.read<LanguageProvider>().l10n.t('downloads_delete'), style: GoogleFonts.inter(
                    color: AppTheme.danger, fontSize: 14,
                    fontWeight: FontWeight.w500)),
              ]))),
      ]),
    );
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  final AppL10n l;
  const _EmptyState({required this.l});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        // Icône avec glow
        Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppTheme.violet.withOpacity(0.15),
              AppTheme.secondary.withOpacity(0.08),
            ]),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.violet.withOpacity(0.2))),
          child: const Icon(Icons.download_rounded,
              color: AppTheme.violet, size: 36))
            .animate().scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1),
                duration: 400.ms, curve: Curves.easeOutBack),
        const SizedBox(height: 20),
        Text(context.read<LanguageProvider>().l10n.t('downloads_empty'), style: GoogleFonts.rajdhani(
            color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700))
            .animate().fadeIn(delay: 100.ms, duration: 300.ms),
        const SizedBox(height: 8),
        Text(context.read<LanguageProvider>().l10n.t('downloads_empty_sub'), style: GoogleFonts.inter(
            color: Colors.white38, fontSize: 13),
            textAlign: TextAlign.center)
            .animate().fadeIn(delay: 180.ms, duration: 300.ms),
        const SizedBox(height: 32),
        // Illustration steps
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withOpacity(0.06))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _StepHint(icon: Icons.movie_rounded, color: AppTheme.violet,
                text: 'Ouvrez un film ou une série'),
            const SizedBox(height: 10),
            _StepHint(icon: Icons.download_rounded, color: AppTheme.secondary,
                text: 'Appuyez sur le bouton télécharger'),
            const SizedBox(height: 10),
            _StepHint(icon: Icons.wifi_off_rounded, color: AppTheme.success,
                text: 'Regardez sans connexion internet'),
          ])).animate().fadeIn(delay: 260.ms, duration: 300.ms),
      ]),
    ),
  );
}

class _StepHint extends StatelessWidget {
  final IconData icon; final Color color; final String text;
  const _StepHint({required this.icon, required this.color, required this.text});
  @override
  Widget build(BuildContext context) => Row(children: [
    Container(
      width: 30, height: 30,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2))),
      child: Icon(icon, color: color, size: 15)),
    const SizedBox(width: 12),
    Expanded(child: Text(text, style: GoogleFonts.inter(
        color: Colors.white60, fontSize: 12))),
  ]);
}

// ── Confirm sheet ─────────────────────────────────────────────────────────────
class _ConfirmSheet extends StatelessWidget {
  final String title, body, confirmLabel;
  final bool danger;
  final VoidCallback onConfirm;
  const _ConfirmSheet({required this.title, required this.body,
      required this.confirmLabel, required this.danger, required this.onConfirm});
  @override
  Widget build(BuildContext context) {
    final btnColor = danger ? AppTheme.danger : AppTheme.violet;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
        border: Border(top: BorderSide(color: btnColor.withOpacity(0.2), width: 1.5))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Center(child: Container(width: 34, height: 4,
          decoration: BoxDecoration(
            color: btnColor.withOpacity(0.3),
            borderRadius: BorderRadius.circular(2)))),
        const SizedBox(height: 20),
        Container(width: 48, height: 48,
          decoration: BoxDecoration(
            color: btnColor.withOpacity(0.12), shape: BoxShape.circle,
            border: Border.all(color: btnColor.withOpacity(0.3))),
          child: Icon(danger ? Icons.delete_rounded : Icons.info_rounded,
              color: btnColor, size: 22)),
        const SizedBox(height: 14),
        Text(title, style: GoogleFonts.rajdhani(
            color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700),
            textAlign: TextAlign.center),
        const SizedBox(height: 8),
        Text(body, style: GoogleFonts.inter(
            color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center),
        const SizedBox(height: 22),
        Row(children: [
          Expanded(child: FocusableInk(
            onTap: () => Navigator.pop(context), borderRadius: 12,
            child: Container(height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.1))),
              child: Center(child: Text('Annuler', style: GoogleFonts.inter(
                  color: Colors.white54, fontWeight: FontWeight.w600)))))),
          const SizedBox(width: 10),
          Expanded(child: FocusableInk(
            onTap: () { Navigator.pop(context); onConfirm(); }, borderRadius: 12,
            child: Container(height: 46,
              decoration: BoxDecoration(
                color: btnColor.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: btnColor.withOpacity(0.4))),
              child: Center(child: Text(confirmLabel, style: GoogleFonts.inter(
                  color: btnColor, fontWeight: FontWeight.w700)))))),
        ]),
      ]),
    );
  }
}