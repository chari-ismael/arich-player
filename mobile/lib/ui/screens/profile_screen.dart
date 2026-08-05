// lib/ui/screens/profile_screen.dart
//
// Arich Player — Écran Profil — v2 AAA
//
// Nouveautés v2 :
//  • Header AppBar : border bottom gradient violet→red + back button pill gradient
//  • Avatar : double ring gradient (outer glow ring + inner border) + scale elasticOut
//  • Avatar bottom sheet : drag handle gradient + icon tiles gradient
//  • Pseudo field : TextField border violet actif + save button gradient
//  • Cards AAA : left border accent 3px gradient + gradient dark multicouche
//    + icon pill gradient + séparateur gradient + badge gradient pill avec glow
//  • _row : icône pill subtle + valueColor support
//  • _stat mini-cards : gradient soft + icon gradient pill + chiffre w800
//  • _daysRemaining : couleur adaptative + border gradient
//  • Bouton sign out : gradient rouge destructif + double boxShadow glow
//  • Dialog : border gradient violet + bouton confirm gradient
//  • Bottom sheet avatar : items avec fond gradient actif
//  • Background orbs conservés (AnimationController + CustomPainter)
//  • Layout TV 2 colonnes préservé
//  • [FIX] IptvProvider.logout() + PlaylistProvider.clear() avant signOut préservé
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../services/supabase_service.dart';
import 'login_screen.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';

const _kAvatarPath  = 'arich_user_avatar_path';
const _kArichPseudo = 'arich_user_pseudo';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  late final AnimationController _bgCtrl;
  late final List<_BgOrb> _orbs;

  Map<String, dynamic>? _licenseInfo;
  bool _licenseLoading = true;

  String _pseudo      = '';
  String _avatarPath  = '';
  bool _hasAvatarFile = false; // cache — existsSync() jamais appelé dans build()
  bool _editingPseudo = false;
  bool _avatarLoading = false;
  final _pseudoCtrl  = TextEditingController();
  final _pseudoFocus = FocusNode();

  @override
  void initState() {
    super.initState();
    // 20s : réduit la fréquence de repaint du CustomPainter
    _bgCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 20))
      ..repeat();

    final rng = math.Random(7);
    _orbs = List.generate(
      8,
      (i) => _BgOrb(
        x: rng.nextDouble(), y: rng.nextDouble(),
        r: 60.0 + rng.nextDouble() * 120,
        speed: 0.15 + rng.nextDouble() * 0.3,
        phase: rng.nextDouble() * math.pi * 2,
        color: i % 2 == 0 ? AppTheme.violet : AppTheme.red,
        opacity: 0.03 + rng.nextDouble() * 0.06,
      ),
    );

    final box = Hive.box('settings');
    _pseudo     = box.get(_kArichPseudo, defaultValue: '') as String;
    _avatarPath = box.get(_kAvatarPath,  defaultValue: '') as String;
    // existsSync() une seule fois à l'init, résultat caché dans _hasAvatarFile
    _hasAvatarFile = _avatarPath.isNotEmpty && File(_avatarPath).existsSync();
    _pseudoCtrl.text = _pseudo;
    _loadLicense();
  }

  Future<void> _loadLicense() async {
    final info = await SupabaseService.getLicenseInfo();
    if (mounted) setState(() { _licenseInfo = info; _licenseLoading = false; });
  }

  @override
  void dispose() {
    _bgCtrl.dispose();
    _pseudoCtrl.dispose();
    _pseudoFocus.dispose();
    super.dispose();
  }

  // ── Avatar ─────────────────────────────────────────────────────────────────

  Future<void> _pickAvatar() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 400, maxHeight: 400, imageQuality: 85,
    );
    if (picked == null || !mounted) return;

    setState(() => _avatarLoading = true);
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final dest   = File(
          '${appDir.path}/arich_avatar_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await File(picked.path).copy(dest.path);
      if (_avatarPath.isNotEmpty) {
        try { await File(_avatarPath).delete(); } catch (_) {}
      }
      setState(() { _avatarPath = dest.path; _hasAvatarFile = true; _avatarLoading = false; });
      Hive.box('settings').put(_kAvatarPath, dest.path);
    } catch (_) {
      setState(() => _avatarLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(context.read<LanguageProvider>().l10n.t('profile_img_error'),
              style: GoogleFonts.poppins()),
          backgroundColor: AppTheme.red,
        ));
      }
    }
  }

  Future<void> _removeAvatar() async {
    if (_avatarPath.isNotEmpty) {
      try { await File(_avatarPath).delete(); } catch (_) {}
    }
    setState(() { _avatarPath = ''; _hasAvatarFile = false; });
    Hive.box('settings').put(_kAvatarPath, '');
  }

  // ── Pseudo ─────────────────────────────────────────────────────────────────

  void _savePseudo() {
    final val = _pseudoCtrl.text.trim();
    setState(() { _pseudo = val; _editingPseudo = false; });
    Hive.box('settings').put(_kArichPseudo, val);
    _pseudoFocus.unfocus();
  }

  // ── Sign out ───────────────────────────────────────────────────────────────

  Future<void> _signOut() async {
    final ok = await _confirmDialog(
      icon: Icons.logout_rounded, iconColor: AppTheme.red,
      title: context.read<LanguageProvider>().l10n.t('profile_disconnect'),
      message: 'Vous serez redirigé vers l\'écran de connexion.',
      confirmLabel: 'Déconnexion', confirmColor: AppTheme.red,
    );
    if (!ok || !mounted) return;

    // [FIX] Vider playlists IPTV + credentials Hive AVANT Supabase signOut
    await context.read<IptvProvider>().logout();
    context.read<PlaylistProvider>().clear();

    await SupabaseService.signOut();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, a, __) => const LoginScreen(),
        transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Curves.easeOut),
            child: child),
        transitionDuration: const Duration(milliseconds: 500),
      ),
      (_) => false,
    );
  }

  Future<bool> _confirmDialog({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.all(26),
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: AppTheme.violet.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                  color: iconColor.withOpacity(0.12), blurRadius: 40),
            ],
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            // Icon ring gradient
            Container(
              width: 58, height: 58,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    iconColor.withOpacity(0.18),
                    iconColor.withOpacity(0.06),
                  ],
                ),
                shape: BoxShape.circle,
                border: Border.all(color: iconColor.withOpacity(0.35), width: 1.5),
              ),
              child: Icon(icon, color: iconColor, size: 26),
            ),
            const SizedBox(height: 16),
            // Accent bar + title
            Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Container(
                width: 3, height: 15,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary,
                  borderRadius: BorderRadius.circular(2),
                ),
                margin: const EdgeInsets.only(right: 8),
              ),
              Text(title, style: GoogleFonts.poppins(
                  color: Colors.white, fontSize: 17,
                  fontWeight: FontWeight.w700)),
            ]),
            const SizedBox(height: 10),
            // Séparateur gradient
            Container(height: 1, margin: const EdgeInsets.symmetric(vertical: 4),
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  Colors.transparent,
                  AppTheme.violet.withOpacity(0.2),
                  Colors.transparent,
                ]),
              ),
            ),
            const SizedBox(height: 6),
            Text(message,
                style: GoogleFonts.poppins(
                    color: AppTheme.textSecondary, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center),
            const SizedBox(height: 22),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      color: AppTheme.surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Center(child: Text(context.read<LanguageProvider>().l10n.t('cancel'),
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w600))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        confirmColor.withOpacity(0.85),
                        confirmColor.withOpacity(0.6),
                      ]),
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: confirmColor.withOpacity(0.3),
                          blurRadius: 14, offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Center(child: Text(confirmLabel,
                        style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontWeight: FontWeight.w700))),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
    return result == true;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isTV = context.isTV;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(children: [
        // Background orbs animés
        Positioned.fill(child: AnimatedBuilder(
          animation: _bgCtrl,
          builder: (_, __) => CustomPaint(
              painter: _OrbPainter(orbs: _orbs, t: _bgCtrl.value)),
        )),
        SafeArea(child: isTV ? _buildTV() : _buildMobile()),
      ]),
    );
  }

  // ─── MOBILE ───────────────────────────────────────────────────────────────

  Widget _buildMobile() {
    final user        = Supabase.instance.client.auth.currentUser;
    final email       = user?.email ?? '';
    final displayName = _pseudo.isNotEmpty
        ? _pseudo
        : email.isNotEmpty ? email.split('@').first : 'Utilisateur';

    return CustomScrollView(slivers: [
      SliverToBoxAdapter(child: Column(children: [
        _buildTopBar(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 28, 20, 0),
          child: Column(children: [
            _avatarWidget(size: 92, fontSize: 36),
            const SizedBox(height: 18),
            _pseudoField(displayName),
            const SizedBox(height: 5),
            Text(email, style: GoogleFonts.poppins(
                color: AppTheme.textSecondary, fontSize: 12)),
            const SizedBox(height: 8),
          ]),
        ),
      ])),
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        sliver: SliverList(delegate: SliverChildListDelegate([
          const SizedBox(height: 20),
          _infoCard(),
          const SizedBox(height: 14),
          _licenseCard(),
          const SizedBox(height: 14),
          _statsCard(),
          const SizedBox(height: 28),
          _signOutBtn(),
          const SizedBox(height: 40),
        ])),
      ),
    ]);
  }

  // ─── TOP BAR MOBILE ───────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return Stack(children: [
      Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        color: Colors.transparent,
        child: Row(children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [
                  AppTheme.violet.withOpacity(0.18),
                  AppTheme.red.withOpacity(0.12),
                ]),
                shape: BoxShape.circle,
                border: Border.all(
                    color: AppTheme.violet.withOpacity(0.25), width: 1),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white, size: 14),
            ),
          ),
          const SizedBox(width: 14),
          // Icon pill
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientPrimary,
              borderRadius: BorderRadius.circular(9),
              boxShadow: AppTheme.glowViolet(),
            ),
            child: const Icon(Icons.person_rounded,
                color: Colors.white, size: 15),
          ),
          const SizedBox(width: 10),
          Text(context.read<LanguageProvider>().l10n.t('profile_my'), style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 17,
              fontWeight: FontWeight.w700)),
        ]),
      ),
      // Border bas gradient
      Positioned(bottom: 0, left: 0, right: 0, height: 1,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              Colors.transparent,
              AppTheme.violet.withOpacity(0.4),
              AppTheme.red.withOpacity(0.3),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    ]);
  }

  // ─── TV ───────────────────────────────────────────────────────────────────

  Widget _buildTV() {
    final user        = Supabase.instance.client.auth.currentUser;
    final email       = user?.email ?? '';
    final displayName = _pseudo.isNotEmpty
        ? _pseudo
        : email.isNotEmpty ? email.split('@').first : 'Utilisateur';

    return Padding(
      padding: const EdgeInsets.all(48),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 270, child: Column(children: [
          _avatarWidget(size: 100, fontSize: 42),
          const SizedBox(height: 18),
          _pseudoField(displayName),
          const SizedBox(height: 5),
          Text(email,
              style: GoogleFonts.poppins(
                  color: AppTheme.textSecondary, fontSize: 12),
              textAlign: TextAlign.center),
          const Spacer(),
          _signOutBtn(),
        ])),
        const SizedBox(width: 40),
        Expanded(child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Section header TV
            Row(children: [
              Container(
                width: 3, height: 22,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary,
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: AppTheme.glowViolet(),
                ),
              ),
              const SizedBox(width: 10),
              Container(
                width: 26, height: 26,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientHorizontal,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.manage_accounts_rounded,
                    color: Colors.white, size: 13),
              ),
              const SizedBox(width: 10),
              Text(context.read<LanguageProvider>().l10n.t('profile_my_account'),
                  style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.5)),
            ]),
            const SizedBox(height: 22),
            _infoCard(),
            const SizedBox(height: 14),
            _licenseCard(),
            const SizedBox(height: 14),
            _statsCard(),
          ]),
        )),
      ]),
    );
  }

  // ─── AVATAR ───────────────────────────────────────────────────────────────

  Widget _avatarWidget({required double size, required double fontSize}) {
    final user        = Supabase.instance.client.auth.currentUser;
    final email       = user?.email ?? '';
    final displayName = _pseudo.isNotEmpty ? _pseudo : email;
    final initial     = displayName.isNotEmpty ? displayName[0].toUpperCase() : '?';
    // Utilise le cache — pas d'I/O dans build()
    final hasImage    = _hasAvatarFile;

    return GestureDetector(
      onTap: _showAvatarOptions,
      child: Stack(children: [
        // Outer glow ring
        Container(
          width: size + 8, height: size + 8,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [
                AppTheme.violet.withOpacity(0.45),
                AppTheme.red.withOpacity(0.3),
              ],
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.violet.withOpacity(0.35),
                blurRadius: 28, spreadRadius: 4,
              ),
            ],
          ),
        ),
        // Inner avatar
        Padding(
          padding: const EdgeInsets.all(4),
          child: Container(
            width: size, height: size,
            decoration: BoxDecoration(
              gradient: hasImage ? null : AppTheme.gradientPrimary,
              shape: BoxShape.circle,
            ),
            child: ClipOval(
              child: _avatarLoading
                  ? Center(child: SizedBox(width: 24, height: 24,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white.withOpacity(0.8))))
                  : hasImage
                      ? Image.file(File(_avatarPath), fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _initialFallback(initial, fontSize))
                      : _initialFallback(initial, fontSize),
            ),
          ),
        ).animate().scale(begin: const Offset(0.8, 0.8),
            duration: 450.ms, curve: Curves.elasticOut),

        // Camera badge gradient
        Positioned(right: 0, bottom: 0,
          child: Container(
            width: size * 0.3, height: size * 0.3,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.background, width: 2),
              boxShadow: AppTheme.glowViolet(),
            ),
            child: Icon(Icons.camera_alt_rounded,
                color: Colors.white, size: size * 0.14),
          ),
        ),
      ]),
    );
  }

  Widget _initialFallback(String initial, double fontSize) => Center(
    child: Text(initial, style: GoogleFonts.poppins(
        color: Colors.white, fontSize: fontSize,
        fontWeight: FontWeight.w800)),
  );

  void _showAvatarOptions() {
    final hasImage = _hasAvatarFile;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppTheme.surfaceHigh,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (_) => SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          // Drag handle gradient
          Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          // Section header
          Row(children: [
            Container(width: 3, height: 14,
              decoration: BoxDecoration(
                gradient: AppTheme.gradientPrimary,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 8),
            Flexible(child: Text(context.read<LanguageProvider>().l10n.t('profile_photo'), style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 11,
                fontWeight: FontWeight.w800, letterSpacing: 1.5), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 10),
          // Option galerie
          _sheetTile(
            icon: Icons.photo_library_rounded,
            color: AppTheme.violet,
            label: context.read<LanguageProvider>().l10n.t('profile_pick_gallery'),
            onTap: () { Navigator.pop(context); _pickAvatar(); },
          ),
          if (hasImage)
            _sheetTile(
              icon: Icons.delete_outline_rounded,
              color: AppTheme.red,
              label: context.read<LanguageProvider>().l10n.t('profile_remove_photo'),
              isDestructive: true,
              onTap: () { Navigator.pop(context); _removeAvatar(); },
            ),
          const SizedBox(height: 4),
        ]),
      )),
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
    bool isDestructive = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        gradient: isDestructive
            ? LinearGradient(colors: [
                AppTheme.red.withOpacity(0.08),
                Colors.transparent,
              ])
            : null,
        color: isDestructive ? null : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: isDestructive
            ? Border.all(color: AppTheme.red.withOpacity(0.18))
            : null,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              color.withOpacity(0.18),
              color.withOpacity(0.08),
            ]),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        title: Text(label, style: GoogleFonts.poppins(
            color: isDestructive ? AppTheme.red : Colors.white,
            fontSize: 14,
            fontWeight: isDestructive ? FontWeight.w600 : FontWeight.w500)),
        onTap: onTap,
      ),
    );
  }

  // ─── PSEUDO ───────────────────────────────────────────────────────────────

  Widget _pseudoField(String displayName) {
    if (_editingPseudo) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 185,
          child: TextField(
            controller: _pseudoCtrl,
            focusNode: _pseudoFocus,
            autofocus: true,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 17,
                fontWeight: FontWeight.w700),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 9),
              fillColor: AppTheme.surfaceHigh, filled: true,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(
                      color: AppTheme.violet.withOpacity(0.5))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: BorderSide(
                      color: AppTheme.violet.withOpacity(0.3))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(11),
                  borderSide: const BorderSide(
                      color: AppTheme.violet, width: 1.5)),
            ),
            onSubmitted: (_) => _savePseudo(),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: _savePseudo,
          child: Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientPrimary,
              borderRadius: BorderRadius.circular(11),
              boxShadow: AppTheme.glowViolet(),
            ),
            child: const Icon(Icons.check_rounded,
                color: Colors.white, size: 19),
          ),
        ),
      ]);
    }
    return GestureDetector(
      onTap: () => setState(() => _editingPseudo = true),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(displayName, style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 19,
              fontWeight: FontWeight.w700)),
          const SizedBox(width: 7),
          Container(
            width: 24, height: 24,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppTheme.violet.withOpacity(0.2),
                AppTheme.red.withOpacity(0.12),
              ]),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.edit_rounded,
                color: AppTheme.violet, size: 13),
          ),
        ],
      ),
    );
  }

  // ─── CARDS ────────────────────────────────────────────────────────────────

  Widget _infoCard() {
    final user      = Supabase.instance.client.auth.currentUser;
    final email     = user?.email ?? 'Non connecté';
    final provider  = user?.appMetadata['provider'] as String? ?? 'email';
    final createdAt = user?.createdAt != null
        ? _formatDate(DateTime.parse(user!.createdAt)) : '—';

    return _card(
      icon: Icons.person_rounded, iconColor: AppTheme.violet,
      title: context.read<LanguageProvider>().l10n.t('profile_account_info'),
      children: [
        _row(Icons.mail_outline_rounded, 'Email', email),
        _row(Icons.login_rounded, 'Connexion via',
            provider == 'google' ? 'Google' : 'Email / Mot de passe'),
        _row(Icons.calendar_today_rounded, 'Membre depuis', createdAt,
            isLast: true),
      ],
    );
  }

  Widget _licenseCard() {
    if (_licenseLoading) {
      return _card(
        icon: Icons.workspace_premium_rounded,
        iconColor: AppTheme.gold, title: context.read<LanguageProvider>().l10n.t('profile_license'),
        children: [
          const Center(child: Padding(
            padding: EdgeInsets.all(16),
            child: CircularProgressIndicator(
                strokeWidth: 2, color: AppTheme.violet),
          )),
        ],
      );
    }
    if (_licenseInfo == null) {
      return _card(
        icon: Icons.workspace_premium_rounded,
        iconColor: AppTheme.textSecondary, title: context.read<LanguageProvider>().l10n.t('profile_license'),
        children: [
          _row(Icons.info_outline_rounded, 'Statut',
              'Aucune licence', isLast: true),
        ],
      );
    }

    final plan      = _licenseInfo!['plan'] as String? ?? 'trial';
    final isActive  = _licenseInfo!['is_active'] as bool? ?? false;
    final expiresAt = _licenseInfo!['expires_at'] != null
        ? DateTime.tryParse(_licenseInfo!['expires_at'] as String) : null;
    final isExpired  = expiresAt != null && expiresAt.isBefore(DateTime.now());
    final isLifetime = plan == 'lifetime';

    Color planColor; String planLabel; IconData planIcon;
    if (isLifetime) {
      planColor = AppTheme.gold;         planLabel = '✦ À vie';
      planIcon  = Icons.all_inclusive_rounded;
    } else if (plan == 'annual') {
      planColor = AppTheme.violet;       planLabel = 'Annuel';
      planIcon  = Icons.calendar_month_rounded;
    } else {
      planColor = AppTheme.textSecondary; planLabel = 'Essai gratuit';
      planIcon  = Icons.hourglass_empty_rounded;
    }

    return _card(
      icon: Icons.workspace_premium_rounded,
      iconColor: AppTheme.gold, title: context.read<LanguageProvider>().l10n.t('profile_license'),
      badge: _badge(planLabel, planColor),
      children: [
        _row(planIcon, 'Plan', planLabel, valueColor: planColor),
        _row(
          isActive && !isExpired
              ? Icons.check_circle_rounded : Icons.cancel_rounded,
          'Statut', isActive && !isExpired ? 'Actif' : 'Expiré',
          valueColor: isActive && !isExpired
              ? AppTheme.success : AppTheme.red,
        ),
        if (!isLifetime && expiresAt != null)
          _row(Icons.timer_outlined, 'Expire le', _formatDate(expiresAt),
              valueColor: isExpired ? AppTheme.red : null),
        if (!isLifetime && !isExpired && expiresAt != null)
          _daysRemaining(expiresAt),
      ],
    );
  }

  Widget _daysRemaining(DateTime expires) {
    final days  = expires.difference(DateTime.now()).inDays;
    final color = days < 3
        ? AppTheme.red : days < 7 ? AppTheme.gold : AppTheme.success;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [
            color.withOpacity(0.10), color.withOpacity(0.04),
          ]),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: color.withOpacity(0.28)),
        ),
        child: Row(children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withOpacity(0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.access_time_rounded, color: color, size: 15),
          ),
          const SizedBox(width: 10),
          Flexible(child: Text(
            '$days jour${days > 1 ? 's' : ''} restant${days > 1 ? 's' : ''}',
            style: GoogleFonts.poppins(
                color: color, fontSize: 13, fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          )),
        ]),
      ),
    );
  }

  Widget _statsCard() {
    final iptv = context.read<IptvProvider>();
    return _card(
      icon: Icons.bar_chart_rounded, iconColor: AppTheme.secondary,
      title: context.read<LanguageProvider>().l10n.t('profile_my_stats'),
      children: [
        Row(children: [
          _stat('${iptv.favorites.length}', 'Favoris',
              Icons.favorite_rounded, AppTheme.gold),
          const SizedBox(width: 10),
          _stat('${iptv.watchHistory.length}', 'Visionnés',
              Icons.history_rounded, AppTheme.violet),
          const SizedBox(width: 10),
          _stat('${context.read<PlaylistProvider>().accounts.length}',
              'Playlists', Icons.playlist_play_rounded, AppTheme.secondary),
        ]),
      ],
    );
  }

  Widget _signOutBtn() => GestureDetector(
    onTap: _signOut,
    child: Container(
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [
          AppTheme.red.withOpacity(0.18),
          AppTheme.red.withOpacity(0.08),
        ]),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: AppTheme.red.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.red.withOpacity(0.12),
            blurRadius: 20, offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Container(
          width: 30, height: 30,
          decoration: BoxDecoration(
            color: AppTheme.red.withOpacity(0.15),
            borderRadius: BorderRadius.circular(9),
          ),
          child: const Icon(Icons.logout_rounded,
              color: AppTheme.red, size: 16),
        ),
        const SizedBox(width: 10),
        Text(context.read<LanguageProvider>().l10n.t('profile_signout'), style: GoogleFonts.poppins(
            color: AppTheme.red,
            fontWeight: FontWeight.w700, fontSize: 14)),
      ]),
    ),
  );

  // ─── UI HELPERS ───────────────────────────────────────────────────────────

  Widget _card({
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
    Widget? badge,
  }) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        // Gradient dark multicouche
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.surface,
            const Color(0xFF09091A),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.07)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.28),
              blurRadius: 18, offset: const Offset(0, 6)),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Left border accent 3px gradient
          Container(
            width: 3,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientPrimary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  // Icon pill gradient
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        iconColor.withOpacity(0.22),
                        iconColor.withOpacity(0.08),
                      ]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: iconColor, size: 17),
                  ),
                  const SizedBox(width: 10),
                  Text(title, style: GoogleFonts.poppins(
                      color: Colors.white, fontSize: 14,
                      fontWeight: FontWeight.w700)),
                  const Spacer(),
                  if (badge != null) badge,
                ]),
                const SizedBox(height: 14),
                // Séparateur gradient
                Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [
                      Colors.transparent,
                      AppTheme.violet.withOpacity(0.2),
                      Colors.transparent,
                    ]),
                  ),
                ),
                const SizedBox(height: 12),
                ...children,
              ],
            ),
          ),
        ]),
      ),
    ).animate()
        .fadeIn(duration: 350.ms)
        .slideY(begin: 0.04, end: 0, curve: Curves.easeOutCubic);
  }

  Widget _row(IconData icon, String label, String value,
      {Color? valueColor, bool isLast = false}) {
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : 10),
      child: Row(children: [
        // Icon subtle pill
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: AppTheme.violet.withOpacity(0.08),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Icon(icon, size: 13, color: AppTheme.textSecondary),
        ),
        const SizedBox(width: 9),
        Text(label, style: GoogleFonts.poppins(
            color: AppTheme.textSecondary, fontSize: 13)),
        const Spacer(),
        Flexible(child: Text(value,
          style: GoogleFonts.poppins(
              color: valueColor ?? Colors.white,
              fontSize: 13, fontWeight: FontWeight.w600),
          textAlign: TextAlign.right,
          overflow: TextOverflow.ellipsis,
        )),
      ]),
    );
  }

  Widget _badge(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
    decoration: BoxDecoration(
      gradient: LinearGradient(colors: [
        color.withOpacity(0.20),
        color.withOpacity(0.10),
      ]),
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.35)),
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.18),
          blurRadius: 8,
        ),
      ],
    ),
    child: Text(label, style: GoogleFonts.poppins(
        color: color, fontSize: 11, fontWeight: FontWeight.w700)),
  );

  Widget _stat(String value, String label, IconData icon, Color color) =>
      Expanded(child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withOpacity(0.10),
              color.withOpacity(0.04),
            ],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Column(children: [
          // Icon pill gradient
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                color.withOpacity(0.25),
                color.withOpacity(0.10),
              ]),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 17),
          ),
          const SizedBox(height: 8),
          Text(value, style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 20,
              fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text(label, style: GoogleFonts.poppins(
              color: AppTheme.textSecondary, fontSize: 10),
              textAlign: TextAlign.center),
        ]),
      ));

  String _formatDate(DateTime dt) {
    const m = ['jan.', 'fév.', 'mar.', 'avr.', 'mai', 'juin',
                'juil.', 'août', 'sep.', 'oct.', 'nov.', 'déc.'];
    return '${dt.day} ${m[dt.month - 1]} ${dt.year}';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background orbs
// ─────────────────────────────────────────────────────────────────────────────

class _BgOrb {
  final double x, y, r, speed, phase, opacity;
  final Color  color;
  const _BgOrb({
    required this.x, required this.y, required this.r,
    required this.speed, required this.phase, required this.opacity,
    required this.color,
  });
}

class _OrbPainter extends CustomPainter {
  final List<_BgOrb> orbs;
  final double t;
  const _OrbPainter({required this.orbs, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    for (final o in orbs) {
      final dx = math.cos((t * o.speed * math.pi * 2) + o.phase) * o.r * 0.3;
      final dy = math.sin((t * o.speed * math.pi * 2) + o.phase) * o.r * 0.2;
      canvas.drawCircle(
        Offset(o.x * size.width + dx, o.y * size.height + dy), o.r,
        Paint()
          ..color     = o.color.withOpacity(o.opacity)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 40),
      );
    }
  }

  @override
  bool shouldRepaint(_OrbPainter old) => old.t != t;
}