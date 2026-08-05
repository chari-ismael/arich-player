// lib/ui/screens/auth_screen.dart
//
// ARICH Player — AuthScreen v3.2
//
// FIX v3.1 :
// [FIX1] StreamSubscription stockée + cancel() dans dispose()
//        → empêche le double traitement du deep link OAuth
// [FIX2] onError sur onAuthStateChange → ignore flow_state_not_found
// [FIX5] Post-frame check session existante au montage (cold start deep link)
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import '../../services/supabase_service.dart';

class AuthScreen extends StatefulWidget {
  final VoidCallback? onAuthSuccess;
  const AuthScreen({super.key, this.onAuthSuccess});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {

  // ── [FIX1] StreamSubscription déclarée ici pour pouvoir cancel() dans dispose()
  late final StreamSubscription<AuthState> _authSubscription;

  late final AnimationController _flipCtrl;
  late final Animation<double> _flipAngle;
  bool _showingLogin = true;
  bool _isFlipping   = false;
  bool _displayLogin = true;

  late final AnimationController _bgCtrl;
  late final List<_BgParticle> _particles;

  final _loginEmailCtrl  = TextEditingController();
  final _loginPassCtrl   = TextEditingController();
  final _loginEmailFocus = FocusNode();
  final _loginPassFocus  = FocusNode();
  final _loginBtnFocus   = FocusNode();
  final _loginGoogleFocus= FocusNode();
  final _loginForgotFocus= FocusNode();
  bool _loginPassVisible = false;
  bool _loginLoading     = false;
  String _loginError     = '';
  // [FIX] Guard anti-double-appel onAuthSuccess (subscription + submitLogin)
  bool _authSuccessCalled = false;

  final _regNameCtrl    = TextEditingController();
  final _regEmailCtrl   = TextEditingController();
  final _regPassCtrl    = TextEditingController();
  final _regConfirmCtrl = TextEditingController();
  final _regNameFocus   = FocusNode();
  final _regEmailFocus  = FocusNode();
  final _regPassFocus   = FocusNode();
  final _regConfirmFocus= FocusNode();
  final _regBtnFocus    = FocusNode();
  final _regGoogleFocus = FocusNode();
  bool _regPassVisible  = false;
  bool _regLoading      = false;
  String _regError      = '';

  bool _googleLoading = false;

  File? _avatarFile;

  AppL10n get _l => context.read<LanguageProvider>().l10n;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    );
    _flipAngle = CurvedAnimation(
      parent: _flipCtrl,
      curve: Curves.easeInOutCubic,
    ).drive(Tween(begin: 0.0, end: math.pi));

    bool midTriggered = false;
    _flipCtrl.addListener(() {
      final progress = _flipCtrl.value;
      if (!midTriggered && progress >= 0.5) {
        midTriggered = true;
        if (mounted) setState(() => _displayLogin = !_showingLogin);
      }
      if (midTriggered && progress < 0.5) {
        midTriggered = false;
        if (mounted) setState(() => _displayLogin = _showingLogin);
      }
    });

    final rng = math.Random(7);
    _particles = List.generate(18, (i) => _BgParticle(
      x:       rng.nextDouble(),
      y:       rng.nextDouble(),
      size:    1.5 + rng.nextDouble() * 3,
      speed:   0.3 + rng.nextDouble() * 0.7,
      angle:   rng.nextDouble() * math.pi * 2,
      color:   i % 2 == 0 ? AppTheme.violet : AppTheme.red,
      opacity: 0.10 + rng.nextDouble() * 0.22,
    ));

    _bgCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    );

    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bgCtrl.repeat();
      _loginGoogleFocus.requestFocus();
    });

    // [PERF] Suppression du addListener → setState global qui rebuilde tout
    // l'écran à chaque frappe dans le champ nom.
    // _buildAvatarPicker() utilise maintenant ValueListenableBuilder directement.

    // [FIX-OAUTH-5] Vérifier si la session existe déjà AU MONTAGE.
    // Cas cold start : _handleDeepLink() dans main.dart traite le deep link
    // et crée la session AVANT que AuthScreen soit monté → signedIn est émis
    // avant que _authSubscription soit en place → onAuthSuccess jamais appelé.
    // Fix : post-frame check immédiat.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null && !_authSuccessCalled) {
        _authSuccessCalled = true;
        debugPrint('[Auth] Session déjà présente au montage → onAuthSuccess');
        widget.onAuthSuccess?.call();
        return;
      }
    });

    // ── [FIX1] Stocker la subscription dans _authSubscription
    // ── [FIX2] onError : ignorer flow_state_not_found (deep link déjà traité)
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(
      (data) {
        if (!mounted) return;
        if (data.event == AuthChangeEvent.signedIn && !_authSuccessCalled) {
          _authSuccessCalled = true;
          widget.onAuthSuccess?.call();
        }
      },
      onError: (error) {
        // flow_state_not_found = le 1er handler Supabase a déjà consommé
        // le flow state OAuth. La session est probablement déjà établie.
        // On ignore silencieusement cette erreur bénigne.
        if (error is AuthException &&
            error.message.contains('flow_state_not_found')) {
          debugPrint('[Auth] flow_state déjà consommé — session probablement OK');
          return;
        }
        debugPrint('[Auth] Erreur inattendue: $error');
      },
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    // ── [FIX1] Annuler la subscription OAuth → stop double handler
    _authSubscription.cancel();

    _flipCtrl.dispose();
    _bgCtrl.dispose();
    _loginEmailCtrl.dispose();
    _loginPassCtrl.dispose();
    _loginEmailFocus.dispose();
    _loginPassFocus.dispose();
    _loginBtnFocus.dispose();
    _loginGoogleFocus.dispose();
    _loginForgotFocus.dispose();
    _regNameCtrl.dispose();
    _regEmailCtrl.dispose();
    _regPassCtrl.dispose();
    _regConfirmCtrl.dispose();
    _regNameFocus.dispose();
    _regEmailFocus.dispose();
    _regPassFocus.dispose();
    _regConfirmFocus.dispose();
    _regBtnFocus.dispose();
    _regGoogleFocus.dispose();
    super.dispose();
  }

  // [FIX-OAUTH-RESUME] Au retour foreground après OAuth Google :
  // le deep link a créé la session pendant que l'app était en bg.
  // On re-vérifie la session ici pour déclencher onAuthSuccess si besoin.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      _onResumeAfterOAuth();
    }
  }

  Future<void> _onResumeAfterOAuth() async {
    // Remettre le loading à false dès le retour app
    if (_googleLoading && mounted) {
      setState(() => _googleLoading = false);
    }

    // Le parsing du deep link peut arriver quelques ms après resumed.
    // On fait un second check court pour éviter les faux "pas connecté".
    bool hasSession() =>
        Supabase.instance.client.auth.currentSession != null;

    if (hasSession() && !_authSuccessCalled) {
      _authSuccessCalled = true;
      debugPrint('[Auth] Session détectée au resume → onAuthSuccess');
      widget.onAuthSuccess?.call();
      return;
    }

    await Future.delayed(const Duration(milliseconds: 450));
    if (!mounted) return;

    if (hasSession() && !_authSuccessCalled) {
      _authSuccessCalled = true;
      debugPrint('[Auth] Session détectée après délai resume → onAuthSuccess');
      widget.onAuthSuccess?.call();
    }
  }

  Future<void> _flip() async {
    if (_isFlipping) return;
    HapticFeedback.lightImpact();
    setState(() => _isFlipping = true);
    if (_showingLogin) {
      await _flipCtrl.forward();
    } else {
      await _flipCtrl.reverse();
    }
    setState(() {
      _showingLogin  = !_showingLogin;
      _displayLogin  = _showingLogin;
      _isFlipping    = false;
      _loginError    = '';
      _regError      = '';
    });
    _flipCtrl.value = 0;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_showingLogin) {
        _loginGoogleFocus.requestFocus();
      } else {
        _regGoogleFocus.requestFocus();
      }
    });
  }

  Future<void> _submitLogin() async {
    final l     = _l;
    final email = _loginEmailCtrl.text.trim();
    final pass  = _loginPassCtrl.text;
    if (email.isEmpty || pass.isEmpty) {
      setState(() => _loginError = context.read<LanguageProvider>().l10n.t('auth_fill_fields'));
      return;
    }
    if (!email.contains('@')) {
      setState(() => _loginError = context.read<LanguageProvider>().l10n.t('auth_invalid_email'));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() { _loginLoading = true; _loginError = ''; });
    try {
      await SupabaseService.signIn(email: email, password: pass);
      if (!mounted) return;
      setState(() => _loginLoading = false);
      await _askOrientationAndProceed();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loginLoading = false;
        _loginError   = _friendlyError(e.toString());
      });
    }
  }

  /// Déclenche onAuthSuccess après connexion email/password.
  /// [FIX] Suppression du verrou _orientationProceedInProgress qui bloquait
  /// le callback si onAuthStateChange l'avait déjà appelé une fois.
  /// On vérifie mounted AVANT l'appel pour éviter les erreurs de contexte détaché.
  Future<void> _askOrientationAndProceed() async {
    if (!mounted || _authSuccessCalled) return;
    _authSuccessCalled = true;
    widget.onAuthSuccess?.call();
  }

  Future<void> _submitRegister() async {
    final l       = _l;
    final name    = _regNameCtrl.text.trim();
    final email   = _regEmailCtrl.text.trim();
    final pass    = _regPassCtrl.text;
    final confirm = _regConfirmCtrl.text;

    if (name.isEmpty || email.isEmpty || pass.isEmpty) {
      setState(() => _regError = context.read<LanguageProvider>().l10n.t('auth_fill_fields'));
      return;
    }
    if (!email.contains('@')) {
      setState(() => _regError = context.read<LanguageProvider>().l10n.t('auth_invalid_email'));
      return;
    }
    if (pass.length < 8) {
      setState(() => _regError = context.read<LanguageProvider>().l10n.t('auth_password_too_short'));
      return;
    }
    if (pass != confirm) {
      setState(() => _regError = context.read<LanguageProvider>().l10n.t('auth_passwords_mismatch'));
      return;
    }
    HapticFeedback.selectionClick();
    setState(() { _regLoading = true; _regError = ''; });
    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: pass,
        data: {'full_name': name},
      );

      if (!mounted) return;

      // Cas : compte déjà existant (Supabase renvoie user sans session et identities vides)
      final identities = response.user?.identities;
      if (response.user != null && (identities == null || identities.isEmpty)) {
        setState(() {
          _regLoading = false;
          _regError = 'Un compte existe déjà avec cet email. Connecte-toi plutôt.';
        });
        return;
      }

      if (_avatarFile != null && response.user != null) {
        try {
          final uid  = response.user!.id;
          final ext  = _avatarFile!.path.split('.').last;
          final path = 'avatars/$uid.$ext';
          await Supabase.instance.client.storage.from('avatars').upload(
            path, _avatarFile!,
            fileOptions: const FileOptions(upsert: true),
          );
          final avatarUrl = Supabase.instance.client.storage
              .from('avatars')
              .getPublicUrl(path);
          if (response.session != null) {
            await Supabase.instance.client.auth.updateUser(UserAttributes(
              data: {'full_name': name, 'avatar_url': avatarUrl},
            ));
          }
          await Hive.box('settings').put('arich_user_avatar_url', avatarUrl);
          await Hive.box('settings').put('arich_user_avatar_path', '');
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _regLoading = false);
      await Hive.box('settings').put('arich_user_name', name);

      if (response.session == null) {
        setState(() => _regError = '');
        // Email de confirmation envoyé
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.mark_email_read_rounded, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Compte créé ! Un email de confirmation a été envoyé à $email. Vérifie ta boîte mail (et les spams).',
              style: GoogleFonts.poppins(fontSize: 13),
            )),
          ]),
          backgroundColor: AppTheme.success,
          duration: const Duration(seconds: 6),
        ));
        // Switcher vers login
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted && !_showingLogin) _flip();
        });
      } else {
        // Connecté directement — demander orientation
        await _askOrientationAndProceed();
      }
    } catch (e) {
      if (!mounted) return;
      final errStr = e.toString();
      String msg;
      if (errStr.contains('already registered') || errStr.contains('User already registered')) {
        msg = 'Un compte existe déjà avec cet email. Connecte-toi plutôt.';
      } else if (errStr.contains('email') && errStr.contains('invalid')) {
        msg = 'Adresse email invalide.';
      } else if (errStr.contains('password') && errStr.contains('weak')) {
        msg = 'Mot de passe trop faible (min. 8 caractères).';
      } else {
        msg = _friendlyError(errStr);
      }
      setState(() {
        _regLoading = false;
        _regError   = msg;
      });
    }
  }

  String _friendlyError(String raw) {
    if (raw.contains('Invalid login credentials'))   return 'Email ou mot de passe incorrect.';
    if (raw.contains('Email not confirmed'))          return 'Confirmez votre email avant de vous connecter.';
    if (raw.contains('already registered') ||
        raw.contains('User already registered'))      return 'Un compte existe déjà avec cet email. Connecte-toi plutôt.';
    if (raw.contains('network') ||
        raw.contains('SocketException'))              return 'Erreur réseau, vérifiez votre connexion.';
    if (raw.contains('500') ||
        raw.contains('AuthRetryableFetchError') ||
        raw.contains('unexpected_failure'))           return 'Erreur serveur (500). Vérifiez la configuration SMTP dans le dashboard Supabase.';
    if (raw.contains('rate limit') ||
        raw.contains('429'))                          return 'Trop de tentatives. Réessayez dans quelques minutes.';
    if (raw.contains('invalid email'))                return 'Adresse email invalide.';
    if (raw.contains('weak_password'))                return 'Mot de passe trop faible (min. 8 caractères).';
    return raw.replaceFirst('Exception: ', '').replaceFirst('AuthException: ', '');
  }

  Future<void> _pickAvatar(ImageSource source) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: source, imageQuality: 85, maxWidth: 400);
    if (picked == null) return;
    setState(() => _avatarFile = File(picked.path));
  }

  void _showAvatarSourceSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A1A2E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            SizedBox(height: 24),
            _SheetOption(icon: Icons.photo_library_rounded, label: context.read<LanguageProvider>().l10n.t('photo_gallery'),
              onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.gallery); }),
            SizedBox(height: 12),
            _SheetOption(icon: Icons.camera_alt_rounded, label: context.read<LanguageProvider>().l10n.t('photo_camera'),
              onTap: () { Navigator.pop(context); _pickAvatar(ImageSource.camera); }),
            if (_avatarFile != null) ...[
              SizedBox(height: 12),
              _SheetOption(icon: Icons.delete_outline_rounded, label: context.read<LanguageProvider>().l10n.t('photo_delete'),
                color: AppTheme.red,
                onTap: () { Navigator.pop(context); setState(() => _avatarFile = null); }),
            ],
          ]),
        ),
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    setState(() { _googleLoading = true; _loginError = ''; _regError = ''; });
    try {
      // [FIX-OAUTH] Le PKCE est activé globalement via AuthFlowType.pkce dans main.dart.
      // response_type=code force le flow code (PKCE) côté Google/Supabase.
      await Supabase.instance.client.auth.signInWithOAuth(
        OAuthProvider.google,
        redirectTo: 'com.arich.iptv://auth-callback',
        authScreenLaunchMode: LaunchMode.externalApplication,
        queryParams: {'response_type': 'code'},
      );
      // signInWithOAuth lance le navigateur et revient immédiatement.
      // La session sera créée asynchrone via le deep link → _authSubscription
      // ou le resume check dans didChangeAppLifecycleState s'en chargent.
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(_friendlyError(e.toString()), style: GoogleFonts.poppins()),
        backgroundColor: AppTheme.red,
      ));
    } finally {
      // Ne pas remettre _googleLoading = false ici — on reste en "loading"
      // jusqu'au retour OAuth (didChangeAppLifecycleState le remet à false).
      // Cela évite que le bouton redevienne cliquable pendant que l'user
      // est dans le navigateur Google.
    }
  }

  Future<void> _forgotPassword() async {
    final email = _loginEmailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _loginError = context.read<LanguageProvider>().l10n.t('auth_invalid_email'));
      return;
    }
    setState(() { _loginLoading = true; _loginError = ''; });
    try {
      await Supabase.instance.client.auth.resetPasswordForEmail(
        email,
        redirectTo: 'com.arich.iptv://auth-callback',
      );
      if (!mounted) return;
      setState(() => _loginLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('${context.read<LanguageProvider>().l10n.t('reset_email_sent')} $email',
            style: GoogleFonts.poppins()),
        backgroundColor: AppTheme.success,
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loginLoading = false;
        _loginError   = _friendlyError(e.toString());
      });
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    context.watch<LanguageProvider>();
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppTheme.background,
        resizeToAvoidBottomInset: true,
        body: Stack(children: [
          // [PERF] RepaintBoundary — les particules ne causent plus de repaint sur tout le Stack
          Positioned.fill(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _bgCtrl,
                builder: (_, __) => CustomPaint(
                  painter: _BgParticlesPainter(particles: _particles, t: _bgCtrl.value),
                ),
              ),
            ),
          ),
          // Glow haut-gauche
          Positioned(
            top: -100, left: -100,
            child: Container(
              width: 400, height: 400,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.violet.withOpacity(0.13),
                  Colors.transparent,
                ]),
              ),
            ),
          ),
          // Glow bas-droite
          Positioned(
            bottom: -80, right: -80,
            child: Container(
              width: 350, height: 350,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [
                  AppTheme.red.withOpacity(0.09),
                  Colors.transparent,
                ]),
              ),
            ),
          ),

          // [LS] Layout conditionnel
          isLandscape
              ? _buildLandscapeLayout()
              : _buildPortraitLayout(),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // [LS] LANDSCAPE — 2 colonnes : brand gauche + form droite
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLandscapeLayout() {
    return SafeArea(
      child: Row(
        children: [
          // Colonne gauche — Brand / Hero
          Expanded(
            flex: 4,
            child: _buildLandscapeBrand(),
          ),

          // Séparateur
          Container(
            width: 1,
            margin: const EdgeInsets.symmetric(vertical: 24),
            color: Colors.white.withOpacity(0.06),
          ),

          // Colonne droite — Formulaire
          Expanded(
            flex: 5,
            child: _buildLandscapeForm(),
          ),
        ],
      ),
    );
  }

  Widget _buildLandscapeBrand() {
    final l = _l;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 20),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Logo + nom
          Row(children: [
            Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 20, spreadRadius: 2),
                  BoxShadow(color: AppTheme.red.withOpacity(0.2), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Image.asset('assets/logo.png', width: 52, height: 52, fit: BoxFit.cover),
              ),
            ).animate().scale(
                begin: const Offset(0.7, 0.7), end: const Offset(1, 1),
                duration: 500.ms, curve: Curves.elasticOut),
            SizedBox(width: 14),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              ShaderMask(
                shaderCallback: (b) => AppTheme.gradientPrimary
                    .createShader(Rect.fromLTWH(0, 0, b.width, b.height)),
                child: Text(context.read<LanguageProvider>().l10n.t('app_name'),
                  style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 22,
                    fontWeight: FontWeight.w800, letterSpacing: -0.3,
                  )),
              ),
              Text(context.read<LanguageProvider>().l10n.t('premium_iptv'),
                style: GoogleFonts.poppins(
                  color: AppTheme.textMuted, fontSize: 11, letterSpacing: 1.2)),
            ]).animate().fadeIn(delay: 150.ms),
          ]),

          const SizedBox(height: 36),

          // Titre dynamique
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
            child: Text(
              key: ValueKey(_displayLogin),
              _displayLogin ? context.read<LanguageProvider>().l10n.t('auth_login_subtitle') : context.read<LanguageProvider>().l10n.t('auth_register_subtitle'),
              style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700,
                height: 1.3,
              ),
            ),
          ).animate().fadeIn(delay: 200.ms),

          const SizedBox(height: 16),

          // Feature chips
          Wrap(
            spacing: 10, runSpacing: 8,
            children: [
              _FeatureChip(icon: Icons.live_tv_rounded, label: context.read<LanguageProvider>().l10n.t('feature_live')),
              _FeatureChip(icon: Icons.movie_rounded, label: context.read<LanguageProvider>().l10n.t('feature_movies')),
              _FeatureChip(icon: Icons.tv_rounded, label: context.read<LanguageProvider>().l10n.t('feature_series')),
              _FeatureChip(icon: Icons.devices_rounded, label: context.read<LanguageProvider>().l10n.t('feature_multiscreen')),
            ],
          ).animate().fadeIn(delay: 300.ms),

          const SizedBox(height: 24),

          // Accent décoratif
          Container(
            height: 3, width: 48,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientHorizontal,
              borderRadius: BorderRadius.circular(2),
            ),
          ).animate().scaleX(begin: 0, end: 1, alignment: Alignment.centerLeft,
              delay: 400.ms, duration: 400.ms, curve: Curves.easeOutCubic),
        ],
      ),
    );
  }

  Widget _buildLandscapeForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedBuilder(
            animation: _flipAngle,
            builder: (_, __) {
              final angle = _flipAngle.value;
              final isSecondHalf = angle > math.pi / 2;
              final displayAngle = isSecondHalf ? angle - math.pi : angle;
              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(displayAngle),
                alignment: Alignment.center,
                child: _displayLogin
                    ? _buildLoginCard()
                    : _buildRegisterCard(),
              );
            },
          ),
          const SizedBox(height: 12),
          _buildToggle(),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PORTRAIT — layout original inchangé
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildPortraitLayout() {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(children: [
          _buildHeader(),
          const SizedBox(height: 40),
          AnimatedBuilder(
            animation: _flipAngle,
            builder: (_, __) {
              final angle = _flipAngle.value;
              final isSecondHalf = angle > math.pi / 2;
              final displayAngle = isSecondHalf ? angle - math.pi : angle;
              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(displayAngle),
                alignment: Alignment.center,
                child: _displayLogin
                    ? _buildLoginCard()
                    : _buildRegisterCard(),
              );
            },
          ),
          const SizedBox(height: 24),
          _buildToggle(),
        ]),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HEADER PORTRAIT
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildHeader() {
    final l = _l;
    return Column(children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 28, spreadRadius: 4),
            BoxShadow(color: AppTheme.red.withOpacity(0.2), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset('assets/logo.png', width: 80, height: 80, fit: BoxFit.cover),
        ),
      ).animate()
        .scale(begin: const Offset(0.7, 0.7), end: const Offset(1, 1),
            duration: 600.ms, curve: Curves.elasticOut),

      SizedBox(height: 14),

      Text(context.read<LanguageProvider>().l10n.t('app_name'),
        style: GoogleFonts.poppins(
          color: Colors.white, fontSize: 24,
          fontWeight: FontWeight.w800, letterSpacing: -0.5,
        ),
      ).animate().fadeIn(delay: 200.ms),

      const SizedBox(height: 4),

      AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
        child: Text(
          key: ValueKey(_displayLogin),
          _displayLogin ? context.read<LanguageProvider>().l10n.t('auth_login_subtitle') : context.read<LanguageProvider>().l10n.t('auth_register_subtitle'),
          style: GoogleFonts.poppins(color: AppTheme.textSecondary, fontSize: 13),
        ),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // CARDS — login + register
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildLoginCard() {
    final l = _l;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: isLandscape ? 440 : 420),
      padding: EdgeInsets.all(isLandscape ? 16 : 28),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.violet.withOpacity(0.20)),
        boxShadow: [
          BoxShadow(color: AppTheme.violet.withOpacity(0.15), blurRadius: 40),
          const BoxShadow(color: Colors.black, blurRadius: 30, offset: Offset(0, 15)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        Text(context.read<LanguageProvider>().l10n.t('auth_login_title'),
          style: GoogleFonts.poppins(
            color: Colors.white, fontSize: isLandscape ? 15 : 18, fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: isLandscape ? 10 : 24),

        _buildGoogleButton(focusNode: _loginGoogleFocus)
            .animate().fadeIn(delay: 80.ms).slideY(begin: 0.08, end: 0, delay: 80.ms),
        SizedBox(height: isLandscape ? 10 : 20),

        _buildDivider(context.read<LanguageProvider>().l10n.t('or'))
            .animate().fadeIn(delay: 120.ms),
        SizedBox(height: isLandscape ? 10 : 20),

        _buildField(
          controller: _loginEmailCtrl,
          label: context.read<LanguageProvider>().l10n.t('auth_email'),
          icon: Icons.mail_outline_rounded,
          keyboardType: TextInputType.emailAddress,
          focusNode: _loginEmailFocus,
          onSubmit: () => FocusScope.of(context).requestFocus(_loginPassFocus),
        ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.06, end: 0, delay: 160.ms),
        SizedBox(height: 12),

        _buildField(
          controller: _loginPassCtrl,
          label: context.read<LanguageProvider>().l10n.t('auth_password'),
          icon: Icons.lock_outline_rounded,
          obscure: !_loginPassVisible,
          focusNode: _loginPassFocus,
          onSubmit: () => FocusScope.of(context).requestFocus(_loginBtnFocus),
          suffix: IconButton(
            icon: Icon(
              _loginPassVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
              color: AppTheme.textMuted, size: 20,
            ),
            onPressed: () => setState(() => _loginPassVisible = !_loginPassVisible),
          ),
        ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.06, end: 0, delay: 200.ms),

        _buildForgotButton(l),

        if (_loginError.isNotEmpty) _buildErrorBox(_loginError),
        SizedBox(height: isLandscape ? 6 : 8),

        _buildGradientButton(
          label: context.read<LanguageProvider>().l10n.t('auth_login_title'),
          loading: _loginLoading,
          onTap: _submitLogin,
          focusNode: _loginBtnFocus,
        ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.06, end: 0, delay: 240.ms),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0);
  }

  Widget _buildRegisterCard() {
    final l = _l;
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      width: double.infinity,
      constraints: BoxConstraints(maxWidth: isLandscape ? 480 : 420),
      padding: EdgeInsets.all(isLandscape ? 22 : 28),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.red.withOpacity(0.20)),
        boxShadow: [
          BoxShadow(color: AppTheme.red.withOpacity(0.12), blurRadius: 40),
          const BoxShadow(color: Colors.black, blurRadius: 30, offset: Offset(0, 15)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [

        Text(context.read<LanguageProvider>().l10n.t('auth_register_title'),
          style: GoogleFonts.poppins(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700,
          ),
        ),
        SizedBox(height: isLandscape ? 12 : 20),

        if (isLandscape)
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            _buildAvatarPicker()
                .animate().fadeIn(delay: 60.ms).scale(
                  begin: const Offset(0.9, 0.9), end: const Offset(1, 1),
                  delay: 60.ms, duration: 400.ms, curve: Curves.easeOutBack),
            const SizedBox(width: 16),
            Expanded(
              child: _buildGoogleButton(focusNode: _regGoogleFocus)
                  .animate().fadeIn(delay: 100.ms).slideY(begin: 0.08, end: 0, delay: 100.ms),
            ),
          ])
        else ...[
          _buildAvatarPicker()
              .animate().fadeIn(delay: 60.ms).scale(
                begin: const Offset(0.9, 0.9), end: const Offset(1, 1),
                delay: 60.ms, duration: 400.ms, curve: Curves.easeOutBack),
          const SizedBox(height: 20),
          _buildGoogleButton(focusNode: _regGoogleFocus)
              .animate().fadeIn(delay: 100.ms).slideY(begin: 0.08, end: 0, delay: 100.ms),
        ],

        SizedBox(height: isLandscape ? 14 : 20),
        _buildDivider(context.read<LanguageProvider>().l10n.t('or')).animate().fadeIn(delay: 130.ms),
        SizedBox(height: isLandscape ? 12 : 20),

        if (isLandscape) ...[
          Row(children: [
            Expanded(child: _buildField(
              controller: _regNameCtrl,
              label: context.read<LanguageProvider>().l10n.t('auth_fullname'),
              icon: Icons.person_outline_rounded,
              focusNode: _regNameFocus,
              onSubmit: () => FocusScope.of(context).requestFocus(_regEmailFocus),
            ).animate().fadeIn(delay: 160.ms)),
            SizedBox(width: 12),
            Expanded(child: _buildField(
              controller: _regEmailCtrl,
              label: context.read<LanguageProvider>().l10n.t('auth_email'),
              icon: Icons.mail_outline_rounded,
              keyboardType: TextInputType.emailAddress,
              focusNode: _regEmailFocus,
              onSubmit: () => FocusScope.of(context).requestFocus(_regPassFocus),
            ).animate().fadeIn(delay: 200.ms)),
          ]),
          SizedBox(height: 12),
          Row(children: [
            Expanded(child: _buildField(
              controller: _regPassCtrl,
              label: context.read<LanguageProvider>().l10n.t('auth_password_min'),
              icon: Icons.lock_outline_rounded,
              obscure: !_regPassVisible,
              focusNode: _regPassFocus,
              onSubmit: () => FocusScope.of(context).requestFocus(_regConfirmFocus),
              suffix: IconButton(
                icon: Icon(
                  _regPassVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                  color: AppTheme.textMuted, size: 20,
                ),
                onPressed: () => setState(() => _regPassVisible = !_regPassVisible),
              ),
            ).animate().fadeIn(delay: 240.ms)),
            SizedBox(width: 12),
            Expanded(child: _buildField(
              controller: _regConfirmCtrl,
              label: context.read<LanguageProvider>().l10n.t('auth_password_confirm'),
              icon: Icons.lock_outline_rounded,
              obscure: true,
              focusNode: _regConfirmFocus,
              onSubmit: () => FocusScope.of(context).requestFocus(_regBtnFocus),
            ).animate().fadeIn(delay: 280.ms)),
          ]),
        ] else ...[
          _buildField(
            controller: _regNameCtrl,
            label: context.read<LanguageProvider>().l10n.t('auth_fullname'),
            icon: Icons.person_outline_rounded,
            focusNode: _regNameFocus,
            onSubmit: () => FocusScope.of(context).requestFocus(_regEmailFocus),
          ).animate().fadeIn(delay: 160.ms).slideY(begin: 0.06, end: 0, delay: 160.ms),
          SizedBox(height: 12),

          _buildField(
            controller: _regEmailCtrl,
            label: context.read<LanguageProvider>().l10n.t('auth_email'),
            icon: Icons.mail_outline_rounded,
            keyboardType: TextInputType.emailAddress,
            focusNode: _regEmailFocus,
            onSubmit: () => FocusScope.of(context).requestFocus(_regPassFocus),
          ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.06, end: 0, delay: 200.ms),
          SizedBox(height: 12),

          _buildField(
            controller: _regPassCtrl,
            label: context.read<LanguageProvider>().l10n.t('auth_password_min'),
            icon: Icons.lock_outline_rounded,
            obscure: !_regPassVisible,
            focusNode: _regPassFocus,
            onSubmit: () => FocusScope.of(context).requestFocus(_regConfirmFocus),
            suffix: IconButton(
              icon: Icon(
                _regPassVisible ? Icons.visibility_off_rounded : Icons.visibility_rounded,
                color: AppTheme.textMuted, size: 20,
              ),
              onPressed: () => setState(() => _regPassVisible = !_regPassVisible),
            ),
          ).animate().fadeIn(delay: 240.ms).slideY(begin: 0.06, end: 0, delay: 240.ms),
          SizedBox(height: 12),

          _buildField(
            controller: _regConfirmCtrl,
            label: context.read<LanguageProvider>().l10n.t('auth_password_confirm'),
            icon: Icons.lock_outline_rounded,
            obscure: true,
            focusNode: _regConfirmFocus,
            onSubmit: () => FocusScope.of(context).requestFocus(_regBtnFocus),
          ).animate().fadeIn(delay: 280.ms).slideY(begin: 0.06, end: 0, delay: 280.ms),
        ],

        if (_regError.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildErrorBox(_regError),
        ],
        SizedBox(height: isLandscape ? 12 : 16),

        _buildGradientButton(
          label: context.read<LanguageProvider>().l10n.t('auth_create_account'),
          loading: _regLoading,
          onTap: _submitRegister,
          focusNode: _regBtnFocus,
          isRegister: true,
        ).animate().fadeIn(delay: 320.ms).slideY(begin: 0.06, end: 0, delay: 320.ms),

        SizedBox(height: 12),
        Text(
          context.read<LanguageProvider>().l10n.t('auth_terms'),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: AppTheme.textMuted, fontSize: 10, height: 1.5),
        ),
      ]),
    ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.04, end: 0);
  }

  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildToggle() {
    final l = _l;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      child: _TVFocusableText(
        key: ValueKey(_displayLogin),
        onTap: _isFlipping ? null : _flip,
        child: RichText(
          text: TextSpan(
            style: GoogleFonts.poppins(color: AppTheme.textSecondary, fontSize: 14),
            children: [
              TextSpan(
                text: _displayLogin
                    ? context.read<LanguageProvider>().l10n.t('auth_no_account')
                    : context.read<LanguageProvider>().l10n.t('auth_already_account'),
              ),
              TextSpan(
                text: _displayLogin
                    ? context.read<LanguageProvider>().l10n.t('auth_create_link')
                    : context.read<LanguageProvider>().l10n.t('auth_signin_link'),
                style: GoogleFonts.poppins(
                  color: AppTheme.violet,
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(delay: 400.ms);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // AVATAR PICKER
  // ─────────────────────────────────────────────────────────────────────────

  Color _avatarColor(String name) {
    if (name.isEmpty) return AppTheme.violet;
    const colors = [
      Color(0xFF7B2FFF), Color(0xFFFF2D55), Color(0xFF0099FF),
      Color(0xFFFF6B00), Color(0xFF00C896), Color(0xFFAA44FF),
    ];
    return colors[name.codeUnitAt(0) % colors.length];
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts[0].isEmpty) return '?';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts.last[0]}'.toUpperCase();
  }

  Widget _buildAvatarPicker() {
    // [PERF] ValueListenableBuilder → seul l'avatar se rebuilde quand le nom change
    // Plus de setState global sur tout l'écran à chaque frappe
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: _regNameCtrl,
      builder: (context, value, _) {
        final name     = value.text;
        final bgColor  = _avatarColor(name);
        final initials = _initials(name);
        final hasPhoto = _avatarFile != null;
        final isLandscape =
            MediaQuery.of(context).orientation == Orientation.landscape;
        final size = isLandscape ? 64.0 : 88.0;

        return Center(
          child: GestureDetector(
            onTap: _showAvatarSourceSheet,
            child: Stack(alignment: Alignment.bottomRight, children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOutCubic,
                width: size, height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasPhoto ? Colors.transparent : bgColor.withOpacity(0.18),
                  border: Border.all(
                    color: hasPhoto ? AppTheme.violet : bgColor.withOpacity(0.55),
                    width: 2.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: (hasPhoto ? AppTheme.violet : bgColor).withOpacity(0.28),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: ClipOval(
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    child: hasPhoto
                        ? Image.file(
                            _avatarFile!,
                            key: const ValueKey('photo'),
                            fit: BoxFit.cover, width: size, height: size,
                          )
                        : Center(
                            key: const ValueKey('initials'),
                            child: Text(
                              initials,
                              style: GoogleFonts.poppins(
                                color: bgColor,
                                fontSize: isLandscape ? 20 : 28,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                  ),
                ),
              ),
              Container(
                width: isLandscape ? 22 : 28,
                height: isLandscape ? 22 : 28,
                decoration: BoxDecoration(
                  gradient: AppTheme.gradientPrimary,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppTheme.surface, width: 2),
              boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 8)],
            ),
            child: Icon(Icons.camera_alt_rounded, color: Colors.white,
                size: isLandscape ? 11 : 14),
          ),
        ]),
      ),
    ); // Center
      }, // ValueListenableBuilder.builder
    ); // ValueListenableBuilder
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SHARED WIDGETS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildGoogleButton({required FocusNode focusNode}) {
    final l = _l;
    return _TVFocusableButton(
      focusNode: focusNode,
      onTap: _googleLoading ? null : _signInWithGoogle,
      builder: (focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 48,
        decoration: BoxDecoration(
          color: _googleLoading
              ? AppTheme.surfaceHigh.withOpacity(0.5)
              : AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: focused ? AppTheme.violet : Colors.white.withOpacity(0.08),
            width: focused ? 1.5 : 1,
          ),
          boxShadow: focused ? [BoxShadow(color: AppTheme.violet.withOpacity(0.3), blurRadius: 12)] : [],
        ),
        child: _googleLoading
            ? const Center(child: SizedBox(
                width: 20, height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation(Colors.white),
                )))
            : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                SizedBox(
                  width: 20, height: 20,
                  child: CustomPaint(painter: _GoogleLogoPainter()),
                ),
                SizedBox(width: 10),
                Text(
                  context.read<LanguageProvider>().l10n.t('auth_continue_google'),
                  style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500,
                  ),
                ),
              ]),
      ),
    );
  }

  Widget _buildDivider(String label) {
    return Row(children: [
      Expanded(child: Container(height: 1, color: Colors.white.withOpacity(0.07))),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(label,
          style: GoogleFonts.poppins(color: AppTheme.textMuted, fontSize: 12)),
      ),
      Expanded(child: Container(height: 1, color: Colors.white.withOpacity(0.07))),
    ]);
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool obscure = false,
    Widget? suffix,
    TextInputType? keyboardType,
    FocusNode? focusNode,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      focusNode: focusNode,
      textInputAction: onSubmit != null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: (_) => onSubmit?.call(),
      style: GoogleFonts.poppins(color: Colors.white, fontSize: 14),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20, color: AppTheme.textMuted),
        suffixIcon: suffix,
      ),
    );
  }

  Widget _buildForgotButton(AppL10n l) {
    return Align(
      alignment: Alignment.centerRight,
      child: _TVFocusableButton(
        focusNode: _loginForgotFocus,
        onTap: _forgotPassword,
        builder: (focused) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: focused ? BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.violet.withOpacity(0.4)),
          ) : null,
          child: Text(context.read<LanguageProvider>().l10n.t('auth_forgot_password'),
            style: GoogleFonts.poppins(color: AppTheme.violet, fontSize: 12)),
        ),
      ),
    );
  }

  Widget _buildGradientButton({
    required String label,
    required bool loading,
    required VoidCallback onTap,
    required FocusNode focusNode,
    bool isRegister = false,
  }) {
    return _TVFocusableButton(
      focusNode: focusNode,
      onTap: loading ? null : onTap,
      builder: (focused) => AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 52,
        decoration: BoxDecoration(
          gradient: loading ? null : (isRegister
              ? const LinearGradient(
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                  colors: [Color(0xFFFF2D55), Color(0xFF7B2FFF)],
                )
              : AppTheme.gradientHorizontal),
          color: loading ? AppTheme.surfaceHigh : null,
          borderRadius: BorderRadius.circular(14),
          boxShadow: loading ? [] : [
            BoxShadow(
              color: (isRegister ? AppTheme.red : AppTheme.violet)
                  .withOpacity(focused ? 0.6 : 0.38),
              blurRadius: focused ? 28 : 20,
              offset: const Offset(0, 6),
            ),
          ],
          border: focused
              ? Border.all(color: Colors.white.withOpacity(0.35), width: 2)
              : null,
        ),
        child: Center(
          child: loading
              ? const SizedBox(
                  width: 22, height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white)))
              : Text(label,
                  style: GoogleFonts.poppins(
                    color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15,
                  )),
        ),
      ),
    );
  }

  Widget _buildErrorBox(String msg) {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.red.withOpacity(0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.red.withOpacity(0.30)),
      ),
      child: Row(children: [
        Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 16),
        const SizedBox(width: 8),
        Expanded(child: Text(msg,
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 12))),
      ]),
    ).animate().fadeIn(duration: 200.ms).slideX(begin: 0.05, end: 0);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feature chip landscape brand
// ─────────────────────────────────────────────────────────────────────────────

class _FeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _FeatureChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white.withOpacity(0.05),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: Colors.white.withOpacity(0.08)),
    ),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, color: AppTheme.violet.withOpacity(0.8), size: 14),
      const SizedBox(width: 6),
      Text(label, style: const TextStyle(color: Colors.white60, fontSize: 12)),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// TV Helpers de focus réutilisables
// ─────────────────────────────────────────────────────────────────────────────

class _TVFocusableButton extends StatefulWidget {
  final FocusNode focusNode;
  final VoidCallback? onTap;
  final Widget Function(bool focused) builder;

  const _TVFocusableButton({
    required this.focusNode,
    required this.onTap,
    required this.builder,
  });

  @override
  State<_TVFocusableButton> createState() => _TVFocusableButtonState();
}

class _TVFocusableButtonState extends State<_TVFocusableButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter ||
             e.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.builder(_focused),
      ),
    );
  }
}

class _TVFocusableText extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;

  const _TVFocusableText({super.key, required this.onTap, required this.child});

  @override
  State<_TVFocusableText> createState() => _TVFocusableTextState();
}

class _TVFocusableTextState extends State<_TVFocusableText> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: _focused ? BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.violet.withOpacity(0.4)),
            color: AppTheme.violet.withOpacity(0.05),
          ) : null,
          child: widget.child,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Logo Google 4 couleurs via CustomPainter
// ─────────────────────────────────────────────────────────────────────────────

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r  = size.width / 2;
    final trackR  = r * 0.72;
    final strokeW = r * 0.38;

    void arc(double startDeg, double sweepDeg, Color color) {
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: trackR),
        startDeg * math.pi / 180,
        sweepDeg * math.pi / 180,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeW
          ..strokeCap = StrokeCap.butt,
      );
    }

    arc(-13,  90,  const Color(0xFF4285F4));
    arc(77,   100, const Color(0xFFEA4335));
    arc(177,  90,  const Color(0xFFFBBC05));
    arc(267,  90,  const Color(0xFF34A853));

    canvas.drawLine(
      Offset(cx, cy), Offset(cx + trackR + strokeW / 2, cy),
      Paint()
        ..color = const Color(0xFF4285F4)
        ..strokeWidth = strokeW * 0.75
        ..strokeCap = StrokeCap.square,
    );
    canvas.drawCircle(
      Offset(cx, cy), trackR - strokeW / 2 - 0.5,
      Paint()..color = const Color(0xFF1A1A1A),
    );
  }

  @override
  bool shouldRepaint(_GoogleLogoPainter old) => false;
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom sheet avatar
// ─────────────────────────────────────────────────────────────────────────────

class _SheetOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  const _SheetOption({
    required this.icon, required this.label, required this.onTap, this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? Colors.white;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: c.withOpacity(0.07),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.withOpacity(0.12)),
        ),
        child: Row(children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(width: 14),
          Text(label,
            style: GoogleFonts.poppins(color: c, fontSize: 15, fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Background particles
// ─────────────────────────────────────────────────────────────────────────────

class _BgParticle {
  final double x, y, size, speed, angle, opacity;
  final Color color;
  const _BgParticle({
    required this.x, required this.y, required this.size,
    required this.speed, required this.angle, required this.opacity,
    required this.color,
  });
}

class _BgParticlesPainter extends CustomPainter {
  final List<_BgParticle> particles;
  final double t;
  const _BgParticlesPainter({required this.particles, required this.t});

  @override
  void paint(Canvas canvas, Size size) {
    for (final p in particles) {
      final phase = (t * p.speed + p.angle) % (math.pi * 2);
      final x = p.x * size.width  + math.cos(phase) * 40;
      final y = p.y * size.height + math.sin(phase) * 30;
      canvas.drawCircle(
        Offset(x, y), p.size,
        Paint()..color = p.color.withOpacity(p.opacity),
      );
    }
  }

  @override
  bool shouldRepaint(_BgParticlesPainter old) => old.t != t;
}