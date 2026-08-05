// lib/ui/screens/profile_picker_screen.dart
//
// Arich Player — Profile Picker Screen v1.1
//
// [v1.1 — Session v10] Navigation D-pad / télécommande Tizen :
//   • _ProfileTile    → GestureDetector remplacé par FocusableInk (focusable)
//   • _AddProfileTile → GestureDetector remplacé par FocusableInk (focusable)
//   • _ProfileManageTile → _actionBtn remplacé par FocusableInk
//   • _NumPad         → chaque bouton numérique remplacé par FocusableInk
//   • Bouton "Gérer"  → GestureDetector remplacé par FocusableInk
//   • _ProfileEditDialog → boutons Annuler/Sauver, toggles → FocusableInk
//   • TvBackHandler ajouté à la racine pour intercepter le bouton Back TV
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../providers/profile_provider.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import '../widgets/focusable_ink.dart';

// ── Avatars disponibles ───────────────────────────────────────────────────────

const kAvatarEmojis = [
  '🎬', '🎮', '🎵', '📺', '🏆', '🚀', '🌙', '⚡',
  '🎭', '🏄', '🎯', '🌟', '🦁', '🐉', '🎸', '🤖',
];

// ── Entrée publique ───────────────────────────────────────────────────────────

class ProfilePickerScreen extends StatefulWidget {
  final VoidCallback onProfileSelected;

  const ProfilePickerScreen({super.key, required this.onProfileSelected});

  @override
  State<ProfilePickerScreen> createState() => _ProfilePickerScreenState();
}

class _ProfilePickerScreenState extends State<ProfilePickerScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  String? _pinProfileId;
  final _pinCtrl = TextEditingController();
  String _pinError = '';
  bool _showManage = false;

  bool get _isTV => TVDetector().isTV;

  @override
  void initState() {
    super.initState();
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 12))
      ..repeat();
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  void _selectProfile(ProfileModel profile) {
    if (profile.hasPin) {
      setState(() {
        _pinProfileId = profile.id;
        _pinCtrl.clear();
        _pinError = '';
      });
    } else {
      _activateProfile(profile.id);
    }
  }

  void _activateProfile(String id) {
    context.read<ProfileProvider>().switchTo(id);
    widget.onProfileSelected();
  }

  void _submitPin() {
    final id = _pinProfileId;
    if (id == null) return;
    final ok =
        context.read<ProfileProvider>().checkPin(id, _pinCtrl.text.trim());
    if (ok) {
      _activateProfile(id);
    } else {
      setState(() => _pinError = 'PIN incorrect');
      _pinCtrl.clear();
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    return TvBackHandler(
      onBack: () {
        if (_showManage) {
          setState(() => _showManage = false);
        } else if (_pinProfileId != null) {
          setState(() {
            _pinProfileId = null;
            _pinError = '';
          });
        } else {
          Navigator.maybePop(context);
        }
      },
      child: Scaffold(
        backgroundColor: AppTheme.background,
        body: Stack(children: [
          _buildBg(),
          Consumer<ProfileProvider>(builder: (_, prov, __) {
            if (_pinProfileId != null) return _buildPinEntry(prov);
            if (_showManage) return _buildManageProfiles(prov);
            return _buildPicker(prov);
          }),
        ]),
      ),
    );
  }

  // ── Fond ─────────────────────────────────────────────────────────────────

  Widget _buildBg() {
    return AnimatedBuilder(
      animation: _bgCtrl,
      builder: (_, __) {
        final t = _bgCtrl.value;
        return Stack(children: [
          Positioned(
            left: -80 + 60 * _sin(t * 2 * 3.14159),
            top: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.violet.withOpacity(0.18),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          Positioned(
            right: -60 + 40 * _sin(t * 2 * 3.14159 + 1.5),
            bottom: -40,
            child: Container(
              width: 260,
              height: 260,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.red.withOpacity(0.14),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
        ]);
      },
    );
  }

  double _sin(double x) =>
      (x % (2 * 3.14159) < 3.14159) ? 1.0 : -1.0;

  // ── Picker principal ──────────────────────────────────────────────────────

  Widget _buildPicker(ProfileProvider prov) {
    final profiles = prov.profiles;
    final isTV = _isTV;

    return SafeArea(
      child: Column(children: [
        SizedBox(height: 40),
        // Titre
        ShaderMask(
          shaderCallback: (b) => AppTheme.gradientHorizontal
              .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
          child: Text(
            context
                .read<LanguageProvider>()
                .l10n
                .t('profile_who_watching'),
            style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontSize: isTV ? 34 : 28,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.5),
          ),
        ).animate().fadeIn(duration: 400.ms).slideY(begin: -0.1, end: 0),

        SizedBox(height: 8),
        Text(
          context.read<LanguageProvider>().l10n.t('profile_choose'),
          style: GoogleFonts.inter(
              color: Colors.white38, fontSize: isTV ? 14 : 13),
        ).animate().fadeIn(delay: 100.ms, duration: 300.ms),

        const SizedBox(height: 48),

        // Grille profils
        Expanded(
          child: Center(
            child: Wrap(
              spacing: isTV ? 32 : 20,
              runSpacing: isTV ? 32 : 20,
              alignment: WrapAlignment.center,
              children: [
                ...profiles.asMap().entries.map((e) => _ProfileTile(
                      profile: e.value,
                      delay: e.key * 80,
                      isTV: isTV,
                      onTap: () => _selectProfile(e.value),
                    )),
                if (prov.canAddMore)
                  _AddProfileTile(
                    delay: profiles.length * 80,
                    isTV: isTV,
                    onTap: () => setState(() => _showManage = true),
                  ),
              ],
            ),
          ),
        ),

        // Bouton Gérer — [v1.1] FocusableInk (était GestureDetector)
        FocusableInk(
          onTap: () => setState(() => _showManage = true),
          borderRadius: 10,
          focusColor: AppTheme.violet,
          child: Container(
            margin: const EdgeInsets.only(bottom: 32),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.06),
              borderRadius: BorderRadius.circular(10),
              border:
                  Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.edit_rounded,
                  color: Colors.white54, size: 15),
              SizedBox(width: 8),
              Text(
                context
                    .read<LanguageProvider>()
                    .l10n
                    .t('profile_manage'),
                style: GoogleFonts.inter(
                    color: Colors.white54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ]),
          ),
        ).animate().fadeIn(delay: 400.ms, duration: 300.ms),
      ]),
    );
  }

  // ── Saisie PIN ────────────────────────────────────────────────────────────

  Widget _buildPinEntry(ProfileProvider prov) {
    final profile = prov.profiles.firstWhere(
        (p) => p.id == _pinProfileId,
        orElse: () => ProfileModel.defaultProfile());

    return SafeArea(
      child: Column(children: [
        Align(
          alignment: Alignment.topLeft,
          child: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white54, size: 18),
            onPressed: () =>
                setState(() {
                  _pinProfileId = null;
                  _pinError = '';
                }),
          ),
        ),
        const Spacer(),
        Text(profile.avatar,
                style: const TextStyle(fontSize: 56))
            .animate()
            .scale(
                begin: const Offset(0.5, 0.5),
                end: const Offset(1, 1),
                duration: 300.ms,
                curve: Curves.easeOutBack),
        SizedBox(height: 12),
        Text(profile.name,
            style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700)),
        SizedBox(height: 32),
        Text(
          context
              .read<LanguageProvider>()
              .l10n
              .t('profile_enter_pin'),
          style: GoogleFonts.inter(
              color: Colors.white54, fontSize: 14),
        ),
        const SizedBox(height: 24),

        _PinDots(
          controller: _pinCtrl,
          error: _pinError,
          onChanged: (v) {
            setState(() => _pinError = '');
            if (v.length == 4) _submitPin();
          },
        ),

        if (_pinError.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(_pinError,
                  style: GoogleFonts.inter(
                      color: AppTheme.error,
                      fontSize: 13,
                      fontWeight: FontWeight.w500))
              .animate()
              .shakeX(duration: 300.ms),
        ],

        const Spacer(),
        _NumPad(
          controller: _pinCtrl,
          onSubmit: _submitPin,
          maxLength: 4,
        ),
        const SizedBox(height: 40),
      ]),
    );
  }

  // ── Gestion profils ───────────────────────────────────────────────────────

  Widget _buildManageProfiles(ProfileProvider prov) {
    return SafeArea(
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
          child: Row(children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 18),
              onPressed: () =>
                  setState(() => _showManage = false),
            ),
            SizedBox(width: 4),
            ShaderMask(
              shaderCallback: (b) => AppTheme.gradientHorizontal
                  .createShader(
                      Rect.fromLTWH(0, 0, b.width, b.height)),
              child: Text(
                context
                    .read<LanguageProvider>()
                    .l10n
                    .t('profile_manage'),
                style: GoogleFonts.rajdhani(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700),
              ),
            ),
            const Spacer(),
            if (prov.canAddMore)
              FocusableInk(
                onTap: () => _showAddProfileDialog(prov),
                borderRadius: 10,
                focusColor: AppTheme.violet,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientPrimary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.add_rounded,
                            color: Colors.white, size: 14),
                        SizedBox(width: 5),
                        Text(
                          context
                              .read<LanguageProvider>()
                              .l10n
                              .t('profile_add'),
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                      ]),
                ),
              ),
          ]),
        ),
        const SizedBox(height: 16),

        Expanded(
          child: ListView.builder(
            padding:
                const EdgeInsets.fromLTRB(16, 0, 16, 32),
            itemCount: prov.profiles.length,
            itemBuilder: (_, i) {
              final p = prov.profiles[i];
              return _ProfileManageTile(
                profile: p,
                isActive: p.id == prov.active.id,
                onSelect: () {
                  _activateProfile(p.id);
                },
                onEdit: () =>
                    _showEditProfileDialog(prov, p),
                onDelete: p.isDefault
                    ? null
                    : () => _confirmDelete(prov, p),
              );
            },
          ),
        ),
      ]),
    );
  }

  void _showAddProfileDialog(ProfileProvider prov) {
    showDialog(
      context: context,
      builder: (_) => _ProfileEditDialog(
        onSave: (name, avatar, pin, isKids) async {
          await prov.addProfile(
              name: name,
              avatar: avatar,
              pin: pin,
              isKids: isKids);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _showEditProfileDialog(
      ProfileProvider prov, ProfileModel profile) {
    showDialog(
      context: context,
      builder: (_) => _ProfileEditDialog(
        existing: profile,
        onSave: (name, avatar, pin, isKids) async {
          await prov.updateProfile(profile.id,
              name: name,
              avatar: avatar,
              pin: pin?.isEmpty == true ? null : pin,
              isKids: isKids);
          if (mounted) setState(() {});
        },
      ),
    );
  }

  void _confirmDelete(
      ProfileProvider prov, ProfileModel profile) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${context.read<LanguageProvider>().l10n.t('profile_delete_title')} "${profile.name}" ?',
          style: GoogleFonts.rajdhani(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w700),
        ),
        content: Text(
          context
              .read<LanguageProvider>()
              .l10n
              .t('profile_delete_body'),
          style: GoogleFonts.inter(
              color: Colors.white54, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              context
                  .read<LanguageProvider>()
                  .l10n
                  .t('cancel'),
              style: GoogleFonts.inter(
                  color: Colors.white54),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              prov.removeProfile(profile.id);
            },
            child: Text(
              context
                  .read<LanguageProvider>()
                  .l10n
                  .t('delete'),
              style: GoogleFonts.inter(
                  color: AppTheme.error,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Profile Tile — [v1.1] FocusableInk ───────────────────────────────────────

class _ProfileTile extends StatefulWidget {
  final ProfileModel profile;
  final int delay;
  final bool isTV;
  final VoidCallback onTap;
  const _ProfileTile(
      {required this.profile,
      required this.delay,
      required this.isTV,
      required this.onTap});
  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _hovered = false, _focused = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.isTV ? 110.0 : 84.0;
    final p = widget.profile;
    final hasFocus = _hovered || _focused;

    return FocusableInk(
      onTap: widget.onTap,
      borderRadius: 16,
      focusColor: AppTheme.violet,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: AnimatedScale(
            scale: hasFocus ? 1.06 : 1.0,
            duration: const Duration(milliseconds: 150),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                width: size,
                height: size,
                decoration: BoxDecoration(
                  gradient: hasFocus
                      ? AppTheme.gradientPrimary
                      : LinearGradient(colors: [
                          AppTheme.surfaceHigh,
                          AppTheme.surfaceTop,
                        ]),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasFocus
                        ? AppTheme.violet.withOpacity(0.8)
                        : Colors.white.withOpacity(0.1),
                    width: hasFocus ? 2 : 1,
                  ),
                  boxShadow: hasFocus
                      ? [
                          BoxShadow(
                              color: AppTheme.violet.withOpacity(0.4),
                              blurRadius: 20,
                              spreadRadius: 2),
                        ]
                      : null,
                ),
                child: Stack(alignment: Alignment.center, children: [
                  Text(p.avatar,
                      style: TextStyle(
                          fontSize: widget.isTV ? 42 : 32)),
                  if (p.hasPin)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.6),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.lock_rounded,
                            color: Colors.white70, size: 10),
                      ),
                    ),
                  if (p.isKids)
                    Positioned(
                      top: 6,
                      left: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppTheme.gold.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          context
                              .read<LanguageProvider>()
                              .l10n
                              .t('profile_kids'),
                          style: GoogleFonts.inter(
                              color: Colors.black,
                              fontSize: 8,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 10),
              Text(
                p.name,
                style: GoogleFonts.inter(
                    color: hasFocus
                        ? Colors.white
                        : Colors.white70,
                    fontSize: widget.isTV ? 14 : 12,
                    fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ]),
          ),
        ),
      ),
    )
        .animate()
        .fadeIn(
            delay: Duration(milliseconds: widget.delay),
            duration: 300.ms)
        .scale(
            begin: const Offset(0.7, 0.7),
            end: const Offset(1, 1),
            delay: Duration(milliseconds: widget.delay),
            duration: 320.ms,
            curve: Curves.easeOutBack);
  }
}

// ── Add Profile Tile — [v1.1] FocusableInk ───────────────────────────────────

class _AddProfileTile extends StatefulWidget {
  final int delay;
  final bool isTV;
  final VoidCallback onTap;
  const _AddProfileTile(
      {required this.delay,
      required this.isTV,
      required this.onTap});
  @override
  State<_AddProfileTile> createState() => _AddProfileTileState();
}

class _AddProfileTileState extends State<_AddProfileTile> {
  bool _hovered = false, _focused = false;

  @override
  Widget build(BuildContext context) {
    final size = widget.isTV ? 110.0 : 84.0;
    final hasFocus = _hovered || _focused;

    return FocusableInk(
      onTap: widget.onTap,
      borderRadius: 16,
      focusColor: AppTheme.violet,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Focus(
          onFocusChange: (f) => setState(() => _focused = f),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: hasFocus
                    ? AppTheme.violet.withOpacity(0.12)
                    : Colors.white.withOpacity(0.04),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: hasFocus
                      ? AppTheme.violet.withOpacity(0.5)
                      : Colors.white.withOpacity(0.1),
                  width: 1.5,
                  style: BorderStyle.solid,
                ),
              ),
              child: Icon(Icons.add_rounded,
                  color: hasFocus
                      ? AppTheme.violet
                      : Colors.white24,
                  size: widget.isTV ? 36 : 28),
            ),
            SizedBox(height: 10),
            Text(
              context
                  .read<LanguageProvider>()
                  .l10n
                  .t('profile_add'),
              style: GoogleFonts.inter(
                  color: Colors.white38,
                  fontSize: widget.isTV ? 14 : 12),
            ),
          ]),
        ),
      ),
    ).animate().fadeIn(
        delay: Duration(milliseconds: widget.delay),
        duration: 300.ms);
  }
}

// ── Profile Manage Tile — [v1.1] _actionBtn → FocusableInk ───────────────────

class _ProfileManageTile extends StatelessWidget {
  final ProfileModel profile;
  final bool isActive;
  final VoidCallback onSelect;
  final VoidCallback onEdit;
  final VoidCallback? onDelete;
  const _ProfileManageTile({
    required this.profile,
    required this.isActive,
    required this.onSelect,
    required this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return FocusableInk(
      onTap: onSelect,
      borderRadius: 14,
      focusColor: AppTheme.violet,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(colors: [
                  AppTheme.violet.withOpacity(0.12),
                  AppTheme.violet.withOpacity(0.04),
                ])
              : null,
          color: isActive ? null : AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isActive
                ? AppTheme.violet.withOpacity(0.4)
                : Colors.white.withOpacity(0.07),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
          child: Row(children: [
            Text(profile.avatar,
                style: const TextStyle(fontSize: 32)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Text(profile.name,
                        style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                    if (isActive) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: AppTheme.gradientPrimary,
                          borderRadius:
                              BorderRadius.circular(8),
                        ),
                        child: Text(
                          context
                              .read<LanguageProvider>()
                              .l10n
                              .t('profile_active'),
                          style: GoogleFonts.inter(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 3),
                  Row(children: [
                    if (profile.hasPin)
                      _badge(Icons.lock_rounded,
                          'PIN activé', AppTheme.gold),
                    if (profile.isKids)
                      _badge(Icons.child_care_rounded,
                          'Enfants', AppTheme.success),
                    if (!profile.hasPin && !profile.isKids)
                      Text(
                        context
                            .read<LanguageProvider>()
                            .l10n
                            .t('profile_standard'),
                        style: GoogleFonts.inter(
                            color: Colors.white38,
                            fontSize: 11),
                      ),
                  ]),
                ],
              ),
            ),
            // Actions — [v1.1] FocusableInk
            Row(mainAxisSize: MainAxisSize.min, children: [
              _actionBtn(
                  Icons.edit_rounded, Colors.white38, onEdit),
              if (onDelete != null) ...[
                const SizedBox(width: 4),
                _actionBtn(Icons.delete_rounded,
                    AppTheme.error.withOpacity(0.7), onDelete!),
              ],
            ]),
          ]),
        ),
      ),
    );
  }

  Widget _badge(IconData icon, String label, Color color) =>
      Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(
            horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, color: color, size: 10),
          const SizedBox(width: 3),
          Text(label,
              style: GoogleFonts.inter(
                  color: color,
                  fontSize: 9,
                  fontWeight: FontWeight.w600)),
        ]),
      );

  // [v1.1] était GestureDetector → FocusableInk
  Widget _actionBtn(
          IconData icon, Color color, VoidCallback onTap) =>
      FocusableInk(
        onTap: onTap,
        borderRadius: 16,
        focusColor: color,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
            border:
                Border.all(color: color.withOpacity(0.25)),
          ),
          child: Icon(icon, color: color, size: 15),
        ),
      );
}

// ── PIN Dots ──────────────────────────────────────────────────────────────────

class _PinDots extends StatelessWidget {
  final TextEditingController controller;
  final String error;
  final ValueChanged<String> onChanged;
  const _PinDots(
      {required this.controller,
      required this.error,
      required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (_, __, ___) {
        final len = controller.text.length;
        return Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(4, (i) {
              final filled = i < len;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                margin: const EdgeInsets.symmetric(
                    horizontal: 10),
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: filled
                      ? AppTheme.gradientPrimary
                      : null,
                  color: filled
                      ? null
                      : Colors.white.withOpacity(0.15),
                  border: Border.all(
                    color: error.isNotEmpty
                        ? AppTheme.error
                        : filled
                            ? AppTheme.violet
                            : Colors.white24,
                    width: filled ? 0 : 1.5,
                  ),
                ),
              );
            }));
      },
    );
  }
}

// ── NumPad — [v1.1] GestureDetector → FocusableInk ───────────────────────────

class _NumPad extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSubmit;
  final int maxLength;
  const _NumPad(
      {required this.controller,
      required this.onSubmit,
      required this.maxLength});

  void _press(String digit) {
    if (controller.text.length >= maxLength) return;
    controller.text += digit;
    controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length));
  }

  void _delete() {
    if (controller.text.isEmpty) return;
    controller.text = controller.text
        .substring(0, controller.text.length - 1);
    controller.selection = TextSelection.fromPosition(
        TextPosition(offset: controller.text.length));
  }

  @override
  Widget build(BuildContext context) {
    final btns = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['⌫', '0', '✓'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: btns
          .map((row) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: row.map((lbl) {
                    final isDelete = lbl == '⌫';
                    final isOk = lbl == '✓';
                    return FocusableInk(
                      onTap: () {
                        if (isDelete) {
                          _delete();
                          return;
                        }
                        if (isOk) {
                          onSubmit();
                          return;
                        }
                        _press(lbl);
                      },
                      borderRadius: 32,
                      focusColor: isOk
                          ? AppTheme.violet
                          : Colors.white38,
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 100),
                        margin: const EdgeInsets.symmetric(
                            horizontal: 10),
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          gradient: isOk
                              ? AppTheme.gradientPrimary
                              : null,
                          color: isOk
                              ? null
                              : AppTheme.surfaceHigh,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isOk
                                ? AppTheme.violet
                                    .withOpacity(0.6)
                                : Colors.white
                                    .withOpacity(0.1),
                          ),
                          boxShadow: isOk
                              ? [
                                  BoxShadow(
                                      color: AppTheme.violet
                                          .withOpacity(0.3),
                                      blurRadius: 12),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: Text(lbl,
                              style: TextStyle(
                                  color: isOk
                                      ? Colors.white
                                      : Colors.white
                                          .withOpacity(0.85),
                                  fontSize:
                                      isDelete ? 20 : 22,
                                  fontWeight:
                                      FontWeight.w600)),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ))
          .toList(),
    );
  }
}

// ── Profile Edit Dialog — [v1.1] toggles/boutons → FocusableInk ──────────────

class _ProfileEditDialog extends StatefulWidget {
  final ProfileModel? existing;
  final Future<void> Function(
      String name, String avatar, String? pin, bool isKids) onSave;
  const _ProfileEditDialog(
      {this.existing, required this.onSave});
  @override
  State<_ProfileEditDialog> createState() =>
      _ProfileEditDialogState();
}

class _ProfileEditDialogState
    extends State<_ProfileEditDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pinCtrl;
  late String _selectedAvatar;
  late bool _isKids;
  bool _setPinEnabled = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl =
        TextEditingController(text: e?.name ?? '');
    _pinCtrl = TextEditingController();
    _selectedAvatar = e?.avatar ?? kAvatarEmojis.first;
    _isKids = e?.isKids ?? false;
    _setPinEnabled = e?.hasPin ?? false;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.surfaceHigh,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24)),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
          Text(
            widget.existing == null
                ? 'Nouveau profil'
                : 'Modifier le profil',
            style: GoogleFonts.rajdhani(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 24),

          Text(_selectedAvatar,
              style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 16),

          // Grille avatars
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: kAvatarEmojis
                .map((e) => FocusableInk(
                      onTap: () =>
                          setState(() => _selectedAvatar = e),
                      borderRadius: 10,
                      focusColor: AppTheme.violet,
                      child: AnimatedContainer(
                        duration: const Duration(
                            milliseconds: 130),
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: _selectedAvatar == e
                              ? AppTheme.gradientPrimary
                              : null,
                          color: _selectedAvatar == e
                              ? null
                              : AppTheme.surface,
                          borderRadius:
                              BorderRadius.circular(10),
                          border: Border.all(
                            color: _selectedAvatar == e
                                ? AppTheme.violet
                                : Colors.white
                                    .withOpacity(0.08),
                          ),
                        ),
                        child: Center(
                            child: Text(e,
                                style: const TextStyle(
                                    fontSize: 22))),
                      ),
                    ))
                .toList(),
          ),
          const SizedBox(height: 20),

          // Nom
          TextField(
            controller: _nameCtrl,
            style: GoogleFonts.inter(
                color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: context
                  .read<LanguageProvider>()
                  .l10n
                  .t('profile_name_hint'),
              hintStyle: GoogleFonts.inter(
                  color: Colors.white38),
              filled: true,
              fillColor: AppTheme.surface,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                    color: AppTheme.violet
                        .withOpacity(0.5)),
              ),
            ),
          ),
          const SizedBox(height: 14),

          // Mode enfants — [v1.1] FocusableInk
          FocusableInk(
            onTap: () =>
                setState(() => _isKids = !_isKids),
            borderRadius: 12,
            focusColor: AppTheme.gold,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _isKids
                    ? AppTheme.gold.withOpacity(0.1)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _isKids
                      ? AppTheme.gold.withOpacity(0.4)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(children: [
                const Icon(Icons.child_care_rounded,
                    color: AppTheme.gold, size: 18),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                  context
                      .read<LanguageProvider>()
                      .l10n
                      .t('profile_kids_mode'),
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 13),
                )),
                AnimatedContainer(
                  duration:
                      const Duration(milliseconds: 150),
                  width: 36,
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: _isKids
                        ? AppTheme.gradientPrimary
                        : null,
                    color: _isKids
                        ? null
                        : Colors.white.withOpacity(0.1),
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                  child: Align(
                    alignment: _isKids
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 14),

          // PIN — [v1.1] FocusableInk
          FocusableInk(
            onTap: () => setState(
                () => _setPinEnabled = !_setPinEnabled),
            borderRadius: 12,
            focusColor: AppTheme.violet,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _setPinEnabled
                    ? AppTheme.violet.withOpacity(0.1)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _setPinEnabled
                      ? AppTheme.violet.withOpacity(0.4)
                      : Colors.white.withOpacity(0.08),
                ),
              ),
              child: Row(children: [
                const Icon(Icons.lock_rounded,
                    color: AppTheme.violet, size: 18),
                SizedBox(width: 10),
                Expanded(
                    child: Text(
                  context
                      .read<LanguageProvider>()
                      .l10n
                      .t('profile_enable_pin'),
                  style: GoogleFonts.inter(
                      color: Colors.white, fontSize: 13),
                )),
                AnimatedContainer(
                  duration:
                      const Duration(milliseconds: 150),
                  width: 36,
                  height: 20,
                  decoration: BoxDecoration(
                    gradient: _setPinEnabled
                        ? AppTheme.gradientPrimary
                        : null,
                    color: _setPinEnabled
                        ? null
                        : Colors.white.withOpacity(0.1),
                    borderRadius:
                        BorderRadius.circular(10),
                  ),
                  child: Align(
                    alignment: _setPinEnabled
                        ? Alignment.centerRight
                        : Alignment.centerLeft,
                    child: Container(
                      margin: const EdgeInsets.all(3),
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle),
                    ),
                  ),
                ),
              ]),
            ),
          ),
          if (_setPinEnabled) ...[
            const SizedBox(height: 10),
            TextField(
              controller: _pinCtrl,
              keyboardType: TextInputType.number,
              maxLength: 4,
              obscureText: true,
              style: GoogleFonts.inter(
                  color: Colors.white,
                  fontSize: 20,
                  letterSpacing: 8),
              decoration: InputDecoration(
                hintText: '● ● ● ●',
                hintStyle: GoogleFonts.inter(
                    color: Colors.white24,
                    letterSpacing: 8),
                counterText: '',
                filled: true,
                fillColor: AppTheme.surface,
                border: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius:
                      BorderRadius.circular(12),
                  borderSide: BorderSide(
                      color: AppTheme.violet
                          .withOpacity(0.5)),
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),

          // Boutons Annuler / Sauver — [v1.1] FocusableInk
          Row(children: [
            Expanded(
              child: FocusableInk(
                onTap: () => Navigator.pop(context),
                borderRadius: 12,
                focusColor: Colors.white38,
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: AppTheme.surface,
                    borderRadius:
                        BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.white
                            .withOpacity(0.08)),
                  ),
                  child: Center(
                      child: Text(
                    context
                        .read<LanguageProvider>()
                        .l10n
                        .t('cancel'),
                    style: GoogleFonts.inter(
                        color: Colors.white54,
                        fontWeight: FontWeight.w600),
                  )),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FocusableInk(
                onTap: _loading
                    ? null
                    : () async {
                        final name =
                            _nameCtrl.text.trim();
                        if (name.isEmpty) return;
                        setState(
                            () => _loading = true);
                        await widget.onSave(
                          name,
                          _selectedAvatar,
                          _setPinEnabled &&
                                  _pinCtrl.text.length ==
                                      4
                              ? _pinCtrl.text
                              : null,
                          _isKids,
                        );
                        if (mounted)
                          Navigator.pop(context);
                      },
                borderRadius: 12,
                focusColor: AppTheme.violet,
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: AppTheme.gradientPrimary,
                    borderRadius:
                        BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.violet
                              .withOpacity(0.35),
                          blurRadius: 12)
                    ],
                  ),
                  child: Center(
                      child: _loading
                          ? SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2))
                          : Text(
                              context
                                  .read<
                                      LanguageProvider>()
                                  .l10n
                                  .t('profile_save'),
                              style: GoogleFonts.inter(
                                  color: Colors.white,
                                  fontWeight:
                                      FontWeight.w700),
                            )),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

// ── Profile Manage —  