// lib/ui/screens/login_screen.dart
//
// Arich Player — LoginScreen v3
//
// v3 :
// [QR] QR Login TV — génère un token, affiche le QR, écoute Supabase Realtime
//      Dès que le user scanne + se connecte sur tel → TV se connecte auto
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../models/playlist_account.dart';
import '../../services/device_service.dart';
import '../../services/supabase_service.dart';
import '../../services/tv_qr_login_service.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import 'auth_screen.dart';
import 'home_screen.dart';
import 'player_screen.dart';
import '../widgets/add_playlist_sheet.dart';

// ─────────────────────────────────────────────────────────────────────────────
// LOGIN SCREEN — point d'entrée
// ─────────────────────────────────────────────────────────────────────────────

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  // [FIX-v11] _view + _AddAccountView supprimés — l'ajout de playlist passe
  // maintenant par showAddPlaylistSheet (même widget que settings_screen).

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<PlaylistProvider>().syncOnResume();
    }
  }

  void _goHome() {
    // [FIX-FLASH] PageRouteBuilder + FadeTransition = pas de flash blanc
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const HomeScreen(),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 400),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    final isTV = size.width > 900;

    if (isTV) return _TVLoginScreen(onSuccess: _goHome);

    // [FIX-OAUTH] StreamBuilder sur authStateChanges → rebuild immédiat
    // quand la session OAuth Google est finalisée.
    return StreamBuilder<AuthState>(
      stream: SupabaseService.authStateChanges,
      builder: (context, snapshot) {
        // [FIX-v11] Race condition OAuth : isSignedIn peut être false pendant
        // quelques ms après l'event signedIn. On vérifie aussi currentSession
        // directement pour couvrir tous les cas (cold start, retour OAuth).
        final streamSignedIn = snapshot.hasData &&
            snapshot.data!.event == AuthChangeEvent.signedIn;
        final sessionExists =
            Supabase.instance.client.auth.currentSession != null;
        final isAuth = streamSignedIn || sessionExists;

        if (!isAuth) {
          return AuthScreen(onAuthSuccess: () => setState(() {}));
        }

        return Scaffold(
          backgroundColor: AppTheme.background,
          body: Stack(children: [
            _GlowBg(),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                  // [FIX-v11] Plus d'AnimatedSwitcher vers _AddAccountView —
                  // on affiche directement _AccountsView. Le bouton "Ajouter"
                  // ouvre showAddPlaylistSheet (cohérent avec settings_screen).
                  child: _AccountsView(
                    onAddNew: () async {
                      await showAddPlaylistSheet(context);
                      // Après fermeture du sheet, si une playlist vient d'être
                      // ajoutée et activée, on navigue vers HomeScreen.
                      if (!mounted) return;
                      final provider = context.read<PlaylistProvider>();
                      if (provider.activeAccount != null) _goHome();
                    },
                    onSuccess: _goHome,
                    onSignOut: () => setState(() {}),
                  ),
                ),
              ),
            ),
          ]),
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TV LOGIN — layout 2 colonnes
// ─────────────────────────────────────────────────────────────────────────────

class _TVLoginScreen extends StatefulWidget {
  final VoidCallback onSuccess;
  const _TVLoginScreen({required this.onSuccess});
  @override
  State<_TVLoginScreen> createState() => _TVLoginScreenState();
}

class _TVLoginScreenState extends State<_TVLoginScreen> with WidgetsBindingObserver {
  bool  _isLoadingAccount = false;
  String? _loadingId;
  String _errorMsg        = '';
  bool   _showAddForm     = false;
  int    _addTab          = 0;

  final _xtreamUrlCtrl  = TextEditingController();
  final _xtreamUserCtrl = TextEditingController();
  final _xtreamPassCtrl = TextEditingController();
  final _xtreamNameCtrl = TextEditingController();
  final _m3uUrlCtrl     = TextEditingController();
  final _m3uNameCtrl    = TextEditingController();

  final _focusRefresh = FocusNode();
  final _focusAddBtn  = FocusNode();
  final _fnXtreamUrl  = FocusNode();
  final _fnXtreamUser = FocusNode();
  final _fnXtreamPass = FocusNode();
  final _fnXtreamName = FocusNode();
  final _fnM3uUrl     = FocusNode();
  final _fnM3uName    = FocusNode();
  final _fnTabXtream  = FocusNode();
  final _fnTabM3u     = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<PlaylistProvider>().syncFromSupabase(context);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _xtreamUrlCtrl.dispose(); _xtreamUserCtrl.dispose();
    _xtreamPassCtrl.dispose(); _xtreamNameCtrl.dispose();
    _m3uUrlCtrl.dispose(); _m3uNameCtrl.dispose();
    _focusRefresh.dispose(); _focusAddBtn.dispose();
    _fnXtreamUrl.dispose(); _fnXtreamUser.dispose();
    _fnXtreamPass.dispose(); _fnXtreamName.dispose();
    _fnM3uUrl.dispose(); _fnM3uName.dispose();
    _fnTabXtream.dispose(); _fnTabM3u.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<PlaylistProvider>().syncOnResume();
    }
  }

  Future<void> _loadAccount(PlaylistAccount account) async {
    setState(() { _isLoadingAccount = true; _loadingId = account.id; _errorMsg = ''; });
    final iptvProvider     = context.read<IptvProvider>();
    final playlistProvider = context.read<PlaylistProvider>();
    bool success = false;

    if (account.type == PlaylistType.xtream) {
      success = await iptvProvider.login(account.serverUrl, account.username, account.password);
    } else {
      success = await iptvProvider.loginM3u(account.m3uUrl);
    }

    if (!mounted) return;
    setState(() { _isLoadingAccount = false; _loadingId = null; });
    if (success) {
      playlistProvider.setActive(account.id);
      widget.onSuccess();
    } else {
      setState(() => _errorMsg = iptvProvider.errorMessage);
    }
  }

  Future<void> _submitXtream() async {
    final rawUrl = _xtreamUrlCtrl.text.trim();
    if (rawUrl.isEmpty) {
      setState(() => _errorMsg = 'URL requise');
      return;
    }

    String url = rawUrl;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'http://$url';
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.host.isEmpty) {
      setState(() => _errorMsg = 'URL invalide (ex: http://serveur.com:8080)');
      return;
    }

    final user = _xtreamUserCtrl.text.trim();
    final pass = _xtreamPassCtrl.text.trim();
    if (user.isEmpty) {
      setState(() => _errorMsg = 'Utilisateur requis');
      return;
    }

    final name = _xtreamNameCtrl.text.trim().isEmpty ? _guessName(url) : _xtreamNameCtrl.text.trim();

    setState(() { _isLoadingAccount = true; _errorMsg = ''; });
    final iptvProvider = context.read<IptvProvider>();

    bool success;
    try {
      success = await iptvProvider.login(url, user, pass);
    } catch (e) {
      success = false;
      setState(() => _errorMsg = 'Erreur: ${e.toString()}');
    }

    if (!mounted) return;
    setState(() => _isLoadingAccount = false);
    if (success) {
      context.read<PlaylistProvider>().addXtream(
          name: name, serverUrl: url, username: user, password: pass, setActive: true);
      widget.onSuccess();
    } else if (_errorMsg.isEmpty) {
      setState(() => _errorMsg = iptvProvider.errorMessage);
    }
  }

  Future<void> _submitM3u() async {
    final url = _sanitizeUrl(_m3uUrlCtrl.text.trim());
    if (url.isEmpty) { setState(() => _errorMsg = 'URL requise'); return; }
    final name = _m3uNameCtrl.text.trim().isEmpty
        ? _guessName(url) : _m3uNameCtrl.text.trim();

    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null || parsedUri.host.isEmpty) {
      setState(() => _errorMsg = 'URL invalide. Collez l\'URL complète, ex :\nhttp://serveur.com:8080/get.php?username=…');
      return;
    }

    setState(() { _isLoadingAccount = true; _errorMsg = ''; });
    final iptvProvider = context.read<IptvProvider>();
    bool success = false;
    try {
      success = await iptvProvider.loginM3u(url);
    } catch (e) {
      success = false;
      setState(() => _errorMsg = 'Erreur de connexion : ${e.toString()}');
    }

    if (!mounted) return;
    setState(() => _isLoadingAccount = false);
    if (success) {
      context.read<PlaylistProvider>().addM3u(name: name, m3uUrl: url, setActive: true);
      widget.onSuccess();
    } else if (_errorMsg.isEmpty) {
      setState(() => _errorMsg = iptvProvider.errorMessage);
    }
  }

  String _sanitizeUrl(String url) {
    if (url.isEmpty) return url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) return 'http://$url';
    return url;
  }

  String _guessName(String url) {
    try { return Uri.parse(url).host.isNotEmpty ? Uri.parse(url).host : 'Ma Playlist'; }
    catch (_) { return 'Ma Playlist'; }
  }

  @override
  Widget build(BuildContext context) {
    // [PERF] context.read car la langue change rarement et ne justifie pas
    // un rebuild complet du layout TV à chaque notification LanguageProvider
    final l = context.read<LanguageProvider>().l10n;
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: Stack(children: [
        _GlowBg(),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 24),
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              SizedBox(width: 340, child: _buildLeftColumn(l)),
              const SizedBox(width: 32),
              Expanded(child: _buildRightColumn(l)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── COLONNE GAUCHE ────────────────────────────────────────────────────────

  Widget _buildLeftColumn(AppL10n l) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

      // Logo
      Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(12),
            boxShadow: AppTheme.glowViolet(intensity: 0.4, blur: 16),
          ),
          child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 26),
        ),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ShaderMask(
            shaderCallback: (b) => AppTheme.gradientPrimary.createShader(
                Rect.fromLTWH(0, 0, b.width, b.height)),
            child: const Text('Arich Player',
              style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w900,
                color: Colors.white, letterSpacing: 1.5,
              )),
          ),
          Text(context.read<LanguageProvider>().l10n.t('home_tv_mode'),
            style: TextStyle(
              fontSize: 11,
              color: Colors.white.withOpacity(0.35),
              letterSpacing: 1.2,
            )),
        ]),
      ]).animate().fadeIn(duration: 400.ms),

      const SizedBox(height: 20),

      // ── QR LOGIN WIDGET ───────────────────────────────────────────────────
      Expanded(
        child: _TvQrLoginWidget(
          onAuthenticated: (userId, email) async {
            if (!mounted) return;
            // Sync les playlists depuis Supabase maintenant qu'on est connecté
            await context.read<PlaylistProvider>().syncFromSupabase(context);
            if (!mounted) return;
            setState(() {});
          },
        ),
      ),
    ]);
  }

  // ── COLONNE DROITE ────────────────────────────────────────────────────────

  Widget _buildRightColumn(AppL10n l) {
    final accounts = context.watch<PlaylistProvider>().accounts;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Text(context.read<LanguageProvider>().l10n.t('playlist_saved'),
          style: const TextStyle(
            color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700,
          )),
        Spacer(),
        _TVButton(
          focusNode: _focusRefresh,
          label: context.read<LanguageProvider>().l10n.t('playlist_refresh'),
          icon: Icons.refresh_rounded,
          onTap: () => context.read<PlaylistProvider>().syncFromSupabase(context),
          compact: true,
        ),
        const SizedBox(width: 10),
        _TVButton(
          focusNode: _focusAddBtn,
          label: _showAddForm ? 'Annuler' : 'Ajouter',
          icon: _showAddForm ? Icons.close_rounded : Icons.add_rounded,
          onTap: () => setState(() { _showAddForm = !_showAddForm; _errorMsg = ''; }),
        ),
      ]).animate().fadeIn(delay: 200.ms),

      const SizedBox(height: 16),

      if (_errorMsg.isNotEmpty)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.red.withOpacity(0.10),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.red.withOpacity(0.3)),
          ),
          child: Row(children: [
            Icon(Icons.error_outline_rounded, color: AppTheme.red, size: 16),
            const SizedBox(width: 8),
            Expanded(child: Text(_errorMsg,
                style: const TextStyle(color: Colors.white, fontSize: 12))),
            GestureDetector(
              onTap: () => setState(() => _errorMsg = ''),
              child: const Icon(Icons.close_rounded, color: AppTheme.textSecondary, size: 14),
            ),
          ]),
        ).animate().fadeIn(),

      if (_showAddForm) ...[
        _buildTVAddForm(l),
        const SizedBox(height: 16),
      ],

      Expanded(
        child: accounts.isEmpty && !_showAddForm
            ? _buildTVEmptyState(l)
            : ListView.separated(
                itemCount: accounts.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (ctx, i) {
                  final account = accounts[i];
                  return _TVAccountCard(
                    account: account,
                    isLoading:  _isLoadingAccount && _loadingId == account.id,
                    isDisabled: _isLoadingAccount && _loadingId != account.id,
                    onTap: () => _loadAccount(account),
                    onDelete: () => context.read<PlaylistProvider>().remove(account.id),
                  ).animate()
                    .fadeIn(delay: Duration(milliseconds: 250 + i * 70))
                    .slideX(begin: 0.06, end: 0, delay: Duration(milliseconds: 250 + i * 70));
                },
              ),
      ),
    ]);
  }

  Widget _buildTVEmptyState(AppL10n l) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 64, height: 64,
          decoration: BoxDecoration(
            color: AppTheme.violet.withOpacity(0.10),
            shape: BoxShape.circle,
            border: Border.all(color: AppTheme.violet.withOpacity(0.2)),
          ),
          child: Icon(Icons.playlist_add_rounded, color: AppTheme.violet, size: 32),
        ),
        SizedBox(height: 16),
        Text(context.read<LanguageProvider>().l10n.t('playlist_none'),
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
        SizedBox(height: 6),
        Text(context.read<LanguageProvider>().l10n.t('arich_signin_desc'),
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withOpacity(0.4), fontSize: 13, height: 1.6,
          )),
      ]),
    ).animate().fadeIn(delay: 300.ms);
  }

  Widget _buildTVAddForm(AppL10n l) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.violet.withOpacity(0.25)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _tabBtn('Xtream Codes', 0),
          const SizedBox(width: 8),
          _tabBtn('URL M3U', 1),
        ]),
        const SizedBox(height: 16),
        if (_addTab == 0) ...[
          _tvField(_xtreamUrlCtrl, 'URL Serveur', 'http://serveur.com:8080',
              Icons.dns_rounded, focusNode: _fnXtreamUrl, nextFocusNode: _fnXtreamUser),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: _tvField(_xtreamUserCtrl, 'Utilisateur', 'username',
                Icons.person_outline_rounded, focusNode: _fnXtreamUser, nextFocusNode: _fnXtreamPass)),
            const SizedBox(width: 10),
            Expanded(child: _tvField(_xtreamPassCtrl, 'Mot de passe', '••••••••',
                Icons.lock_outline_rounded, obscure: true, focusNode: _fnXtreamPass, nextFocusNode: _fnXtreamName)),
          ]),
          SizedBox(height: 10),
          _tvField(_xtreamNameCtrl, 'Nom (optionnel)', 'Mon IPTV',
              Icons.label_outline_rounded, focusNode: _fnXtreamName, onSubmit: _submitXtream),
          SizedBox(height: 16),
          _TVButton(label: context.read<LanguageProvider>().l10n.t('auth_signin_link'), icon: Icons.arrow_forward_rounded,
              onTap: _submitXtream, loading: _isLoadingAccount, primary: true),
        ] else ...[
          _tvField(_m3uNameCtrl, 'Nom (optionnel)', 'France IPTV',
              Icons.label_outline_rounded, focusNode: _fnM3uName, nextFocusNode: _fnM3uUrl),
          SizedBox(height: 10),
          _tvField(_m3uUrlCtrl, 'URL M3U / M3U_PLUS', 'http://serveur.com/get.php?...',
              Icons.link_rounded, focusNode: _fnM3uUrl, onSubmit: _submitM3u),
          SizedBox(height: 16),
          _TVButton(label: context.read<LanguageProvider>().l10n.t('login_load_save'), icon: Icons.download_rounded,
              onTap: _submitM3u, loading: _isLoadingAccount, primary: true),
        ],
      ]),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: -0.04, end: 0);
  }

  Widget _tabBtn(String label, int index) {
    final sel       = _addTab == index;
    final focusNode = index == 0 ? _fnTabXtream : _fnTabM3u;
    return Focus(
      focusNode: focusNode,
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter)) {
          setState(() { _addTab = index; _errorMsg = ''; });
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: () => setState(() { _addTab = index; _errorMsg = ''; }),
        child: Builder(builder: (ctx) {
          final isFocused = Focus.of(ctx).hasFocus;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            decoration: BoxDecoration(
              gradient: sel ? AppTheme.gradientPrimary : null,
              color: sel ? null : AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(8),
              border: isFocused
                  ? Border.all(color: AppTheme.violet, width: 1.5)
                  : null,
              boxShadow: isFocused
                  ? AppTheme.glowViolet(intensity: 0.25, blur: 10)
                  : [],
            ),
            child: Text(label, style: TextStyle(
              color: sel ? Colors.white : AppTheme.textSecondary,
              fontSize: 12,
              fontWeight: sel ? FontWeight.w600 : FontWeight.w400,
            )),
          );
        }),
      ),
    );
  }

  Widget _tvField(
    TextEditingController ctrl, String label, String hint, IconData icon, {
    bool obscure = false,
    FocusNode? focusNode,
    FocusNode? nextFocusNode,
    VoidCallback? onSubmit,
  }) {
    return TextField(
      controller: ctrl, obscureText: obscure, focusNode: focusNode,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      textInputAction: nextFocusNode != null ? TextInputAction.next : TextInputAction.done,
      onSubmitted: (_) {
        if (nextFocusNode != null) FocusScope.of(context).requestFocus(nextFocusNode);
        else onSubmit?.call();
      },
      decoration: InputDecoration(
        labelText: label, hintText: hint,
        prefixIcon: Icon(icon, color: AppTheme.textSecondary, size: 18),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// QR LOGIN WIDGET — affiché dans la colonne gauche TV
// ─────────────────────────────────────────────────────────────────────────────

enum _QrState { loading, ready, success, expired, error }

class _TvQrLoginWidget extends StatefulWidget {
  final void Function(String userId, String? email) onAuthenticated;
  const _TvQrLoginWidget({required this.onAuthenticated});

  @override
  State<_TvQrLoginWidget> createState() => _TvQrLoginWidgetState();
}

class _TvQrLoginWidgetState extends State<_TvQrLoginWidget>
    with SingleTickerProviderStateMixin {

  final _service = TvQrLoginService();
  _QrState _state = _QrState.loading;
  String? _authEmail;

  late final AnimationController _successCtrl;
  late final Animation<double>    _successScale;

  // Expiry countdown
  static const _totalSeconds = 600; // 10 min
  int _secondsLeft = _totalSeconds;
  bool _timerRunning = false;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = CurvedAnimation(
      parent: _successCtrl, curve: Curves.elasticOut);
    _init();
  }

  Future<void> _init() async {
    setState(() => _state = _QrState.loading);
    try {
      await _service.generateSession();
      _service.watchSession(
        onAuthenticated: (userId, email) {
          if (!mounted) return;
          setState(() { _state = _QrState.success; _authEmail = email; });
          _successCtrl.forward(from: 0);
          HapticFeedback.heavyImpact();
          widget.onAuthenticated(userId, email);
        },
        onExpired: () {
          if (!mounted) return;
          setState(() => _state = _QrState.expired);
        },
      );
      if (mounted) {
        setState(() { _state = _QrState.ready; _secondsLeft = _totalSeconds; });
        _startCountdown();
      }
    } catch (e) {
      if (mounted) setState(() => _state = _QrState.error);
    }
  }

  void _startCountdown() {
    if (_timerRunning) return;
    _timerRunning = true;
    Future.doWhile(() async {
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return false;
      if (_state != _QrState.ready) { _timerRunning = false; return false; }
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) {
        setState(() => _state = _QrState.expired);
        _timerRunning = false;
        return false;
      }
      return true;
    });
  }

  @override
  void dispose() {
    _successCtrl.dispose();
    _service.dispose();
    super.dispose();
  }

  String get _countdown {
    final m = _secondsLeft ~/ 60;
    final s = _secondsLeft % 60;
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  Color get _countdownColor {
    if (_secondsLeft > 120) return AppTheme.success;
    if (_secondsLeft > 30)  return const Color(0xFFFFD60A);
    return AppTheme.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _state == _QrState.success
              ? AppTheme.success.withOpacity(0.4)
              : AppTheme.border,
        ),
        boxShadow: _state == _QrState.success
            ? [BoxShadow(color: AppTheme.success.withOpacity(0.15), blurRadius: 24)]
            : [],
      ),
      padding: const EdgeInsets.all(20),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 350),
        transitionBuilder: (child, anim) => FadeTransition(
          opacity: anim,
          child: ScaleTransition(scale: Tween(begin: 0.92, end: 1.0).animate(anim), child: child),
        ),
        child: _buildContent(),
      ),
    ).animate().fadeIn(delay: 200.ms).slideY(begin: 0.05, end: 0, delay: 200.ms);
  }

  Widget _buildContent() {
    switch (_state) {
      case _QrState.loading:
        return _buildLoading();
      case _QrState.ready:
        return _buildReady();
      case _QrState.success:
        return _buildSuccess();
      case _QrState.expired:
        return _buildExpired();
      case _QrState.error:
        return _buildError();
    }
  }

  // ── Loading ──────────────────────────────────────────────────────────────

  Widget _buildLoading() {
    return SizedBox(
      key: const ValueKey('loading'),
      child: Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const CircularProgressIndicator(color: AppTheme.violet, strokeWidth: 2),
          const SizedBox(height: 16),
          Text(context.read<LanguageProvider>().l10n.t('login_qr_generating'),
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
        ]),
      ),
    );
  }

  // ── Ready — QR affiché ───────────────────────────────────────────────────

  Widget _buildReady() {
    return Column(
      key: const ValueKey('ready'),
      children: [
        // Header
        Row(children: [
          Container(
            width: 32, height: 32,
            decoration: BoxDecoration(
              gradient: AppTheme.gradientPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.qr_code_scanner_rounded, color: Colors.white, size: 16),
          ),
          SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(context.read<LanguageProvider>().l10n.t('login_qr_title'),
              style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
            Text(context.read<LanguageProvider>().l10n.t('login_qr_scan'),
              style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 10)),
          ])),
          // Countdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: _countdownColor.withOpacity(0.12),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _countdownColor.withOpacity(0.3)),
            ),
            child: Text(_countdown,
              style: TextStyle(
                color: _countdownColor, fontSize: 11,
                fontWeight: FontWeight.w700, fontFeatures: [const FontFeature.tabularFigures()],
              )),
          ),
        ]),

        const SizedBox(height: 14),

        // Info box
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppTheme.violet.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.violet.withOpacity(0.2)),
          ),
          child: Row(children: [
            const Icon(Icons.smartphone_rounded, color: AppTheme.violet, size: 14),
            const SizedBox(width: 8),
            Expanded(child: Text(
              'Scannez → connectez-vous sur votre téléphone → la TV se connecte automatiquement',
              style: TextStyle(
                color: Colors.white.withOpacity(0.7), fontSize: 10, height: 1.5),
            )),
          ]),
        ),

        const SizedBox(height: 14),

        // QR code
        Expanded(
          child: Center(
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: AppTheme.violet.withOpacity(0.25), blurRadius: 20),
                ],
              ),
              child: QrImageView(
                data: _service.qrUrl,
                version: QrVersions.auto,
                backgroundColor: Colors.white,
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Steps
        _buildSteps(),
      ],
    );
  }

  Widget _buildSteps() {
    final steps = [
      ('1', 'Ouvrez l\'appareil photo'),
      ('2', 'Scannez le QR code'),
      ('3', 'Connectez-vous'),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: steps.map((s) => Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(child: Text(s.$1,
            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700))),
        ),
        const SizedBox(height: 4),
        Text(s.$2,
          style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 9),
          textAlign: TextAlign.center),
      ])).toList(),
    );
  }

  // ── Success ──────────────────────────────────────────────────────────────

  Widget _buildSuccess() {
    return Column(
      key: const ValueKey('success'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        ScaleTransition(
          scale: _successScale,
          child: Container(
            width: 72, height: 72,
            decoration: BoxDecoration(
              color: AppTheme.success.withOpacity(0.12),
              shape: BoxShape.circle,
              border: Border.all(color: AppTheme.success.withOpacity(0.4), width: 2),
            ),
            child: Icon(Icons.check_rounded, color: AppTheme.success, size: 38),
          ),
        ),
        SizedBox(height: 20),
        Text(context.read<LanguageProvider>().l10n.t('login_qr_connected'),
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        if (_authEmail != null) ...[
          Text(_authEmail!,
            style: TextStyle(color: AppTheme.violet, fontSize: 13, fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
        ],
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: AppTheme.success.withOpacity(0.10),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6, height: 6,
              decoration: BoxDecoration(
                color: AppTheme.success, shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: 6),
            Text(context.read<LanguageProvider>().l10n.t('login_qr_syncing'),
              style: TextStyle(color: AppTheme.success, fontSize: 11)),
          ]),
        ),
      ],
    );
  }

  // ── Expired ──────────────────────────────────────────────────────────────

  Widget _buildExpired() {
    return Column(
      key: const ValueKey('expired'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 56, height: 56,
          decoration: BoxDecoration(
            color: const Color(0xFFFFD60A).withOpacity(0.12),
            shape: BoxShape.circle,
            border: Border.all(color: Color(0xFFFFD60A).withOpacity(0.4)),
          ),
          child: Icon(Icons.timer_off_rounded, color: Color(0xFFFFD60A), size: 28),
        ),
        SizedBox(height: 16),
        Text(context.read<LanguageProvider>().l10n.t('login_qr_expired'),
          style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700)),
        SizedBox(height: 6),
        Text(context.read<LanguageProvider>().l10n.t('login_qr_expired_sub'),
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
          textAlign: TextAlign.center),
        SizedBox(height: 20),
        _TVButton(
          label: context.read<LanguageProvider>().l10n.t('login_qr_new'),
          icon: Icons.refresh_rounded,
          onTap: _init,
          primary: true,
        ),
      ],
    );
  }

  // ── Error ────────────────────────────────────────────────────────────────

  Widget _buildError() {
    return Column(
      key: ValueKey('error'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.wifi_off_rounded, color: AppTheme.textMuted, size: 40),
        SizedBox(height: 16),
        Text(context.read<LanguageProvider>().l10n.t('login_qr_error'),
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        SizedBox(height: 6),
        Text(context.read<LanguageProvider>().l10n.t('login_qr_error_sub'),
          style: TextStyle(color: Colors.white.withOpacity(0.4), fontSize: 12),
          textAlign: TextAlign.center),
        SizedBox(height: 20),
        _TVButton(label: context.read<LanguageProvider>().l10n.t('login_retry'), icon: Icons.refresh_rounded, onTap: _init),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TV ACCOUNT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _TVAccountCard extends StatefulWidget {
  final PlaylistAccount account;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _TVAccountCard({
    required this.account, required this.isLoading,
    required this.isDisabled, required this.onTap, required this.onDelete,
  });

  @override
  State<_TVAccountCard> createState() => _TVAccountCardState();
}

class _TVAccountCardState extends State<_TVAccountCard> {
  bool _focused = false;
  bool _pressed = false;

  Color get _color {
    try { return Color(int.parse(widget.account.color.replaceFirst('#', '0xFF'))); }
    catch (_) { return AppTheme.primary; }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.read<LanguageProvider>().l10n;
    return Focus(
      onFocusChange: (f) {
        if (!mounted) return;
        setState(() => _focused = f);
        if (f) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(context,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic, alignment: 0.3);
          });
        }
      },
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (e is KeyDownEvent && e.logicalKey == LogicalKeyboardKey.delete) {
          widget.onDelete();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.isDisabled ? null : widget.onTap,
        onLongPress: widget.isDisabled ? null : widget.onDelete,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: AnimatedScale(
          scale: _pressed ? 0.97 : 1.0,
          duration: const Duration(milliseconds: 100),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _focused ? AppTheme.surfaceTop : AppTheme.surfaceHigh,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: _focused
                    ? AppTheme.violet
                    : widget.account.isActive
                        ? _color.withOpacity(0.5)
                        : Colors.white.withOpacity(0.06),
                width: _focused ? 1.5 : 1,
              ),
              boxShadow: _focused ? AppTheme.glowViolet(intensity: 0.3, blur: 16) : [],
            ),
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  color: _color.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _color.withOpacity(0.3)),
                ),
                child: widget.isLoading
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: CircularProgressIndicator(strokeWidth: 2, color: _color),
                      )
                    : Icon(widget.account.typeIcon, color: _color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Expanded(child: Text(widget.account.name,
                    style: const TextStyle(
                      color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis)),
                  if (widget.account.isActive)
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: _color.withOpacity(0.15), borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(context.read<LanguageProvider>().l10n.t('playlist_active'),
                        style: TextStyle(
                          color: _color, fontSize: 9, fontWeight: FontWeight.w700,
                        )),
                    ),
                ]),
                const SizedBox(height: 3),
                Text(widget.account.subtitle,
                  style: const TextStyle(color: AppTheme.textSecondary, fontSize: 11),
                  overflow: TextOverflow.ellipsis),
              ])),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.background, borderRadius: BorderRadius.circular(6),
                ),
                child: Text(widget.account.typeLabel,
                  style: const TextStyle(
                    color: AppTheme.textMuted, fontSize: 9,
                    fontWeight: FontWeight.w500, letterSpacing: 0.5,
                  )),
              ),
              const SizedBox(width: 8),
              widget.isLoading
                  ? const SizedBox(width: 16)
                  : AnimatedSwitcher(
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        key: ValueKey(_focused),
                        _focused ? Icons.play_arrow_rounded : Icons.arrow_forward_ios_rounded,
                        color: _focused ? AppTheme.violet : AppTheme.textMuted,
                        size: _focused ? 20 : 13,
                      ),
                    ),
            ]),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// TV BUTTON
// ─────────────────────────────────────────────────────────────────────────────

class _TVButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool compact;
  final bool primary;
  final bool loading;
  final FocusNode? focusNode;

  const _TVButton({
    required this.label, required this.icon, required this.onTap,
    this.compact = false, this.primary = false,
    this.loading = false, this.focusNode,
  });

  @override
  State<_TVButton> createState() => _TVButtonState();
}

class _TVButtonState extends State<_TVButton> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: widget.focusNode,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.select ||
             e.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: widget.loading ? null : widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 12 : 16,
            vertical: widget.compact ? 8 : 10,
          ),
          decoration: BoxDecoration(
            gradient: (widget.primary || _focused) ? AppTheme.gradientPrimary : null,
            color: (widget.primary || _focused) ? null : AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused ? AppTheme.violet : Colors.white.withOpacity(0.08),
            ),
            boxShadow: _focused ? AppTheme.glowViolet(intensity: 0.3, blur: 12) : [],
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            widget.loading
                ? const SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : Icon(widget.icon, size: 15,
                    color: (widget.primary || _focused) ? Colors.white : AppTheme.textSecondary),
            const SizedBox(width: 6),
            Text(widget.label, style: TextStyle(
              color: (widget.primary || _focused) ? Colors.white : AppTheme.textSecondary,
              fontSize: 12, fontWeight: FontWeight.w600,
            )),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MOBILE — VUE LISTE DES COMPTES
// ─────────────────────────────────────────────────────────────────────────────

class _AccountsView extends StatefulWidget {
  final VoidCallback onAddNew;
  final VoidCallback onSuccess;
  final VoidCallback onSignOut;
  const _AccountsView({super.key, required this.onAddNew, required this.onSuccess, required this.onSignOut});

  @override
  State<_AccountsView> createState() => _AccountsViewState();
}

class _AccountsViewState extends State<_AccountsView> {
  bool    _isLoading = false;
  String? _loadingId;
  bool    _isSyncing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncPlaylists());
  }

  Future<void> _syncPlaylists() async {
    setState(() => _isSyncing = true);
    await context.read<PlaylistProvider>().syncFromSupabase(context);
    if (mounted) setState(() => _isSyncing = false);
  }

  Future<void> _loadAccount(PlaylistAccount account) async {
    setState(() { _isLoading = true; _loadingId = account.id; });
    final iptvProvider     = context.read<IptvProvider>();
    final playlistProvider = context.read<PlaylistProvider>();
    bool success = false;
    if (account.type == PlaylistType.xtream) {
      success = await iptvProvider.login(account.serverUrl, account.username, account.password);
    } else {
      success = await iptvProvider.loginM3u(account.m3uUrl);
    }
    if (!mounted) return;
    setState(() { _isLoading = false; _loadingId = null; });
    if (success) {
      playlistProvider.setActive(account.id);
      widget.onSuccess();
    } else {
      _showError(iptvProvider.errorMessage);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: AppTheme.red,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      margin: const EdgeInsets.all(16),
    ));
  }

  void _confirmDelete(BuildContext context, PlaylistAccount account) {
    final l = context.read<LanguageProvider>().l10n;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('${context.read<LanguageProvider>().l10n.t('delete')} ?',
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Text('${context.read<LanguageProvider>().l10n.t('delete')} "${account.name}" ?',
          style: GoogleFonts.poppins(color: AppTheme.textSecondary, fontSize: 13)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text(context.read<LanguageProvider>().l10n.t('cancel'),
              style: GoogleFonts.poppins(color: AppTheme.textSecondary))),
          TextButton(
            onPressed: () {
              context.read<PlaylistProvider>().remove(account.id);
              Navigator.pop(ctx);
            },
            child: Text(context.read<LanguageProvider>().l10n.t('delete'),
              style: GoogleFonts.poppins(color: AppTheme.red, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l        = context.read<LanguageProvider>().l10n;
    final accounts = context.watch<PlaylistProvider>().accounts;
    final user     = SupabaseService.currentUser;
    final email    = user?.email ?? '';

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _buildLogo().animate()
        .scale(begin: const Offset(0.8, 0.8), end: const Offset(1, 1),
            duration: 600.ms, curve: Curves.elasticOut),
      const SizedBox(height: 20),
      _buildAccountHeader(l, email),
      const SizedBox(height: 24),

      if (accounts.isEmpty) ...[
        _buildEmptyState(l),
      ] else ...[
        Row(children: [
          Text(context.read<LanguageProvider>().l10n.t('settings_playlists'),
            style: GoogleFonts.poppins(
              color: AppTheme.textSecondary, fontSize: 12,
              fontWeight: FontWeight.w500, letterSpacing: 1.2,
            )),
          const Spacer(),
          if (_isSyncing)
            const SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.violet))
          else
            GestureDetector(
              onTap: _syncPlaylists,
              child: const Icon(Icons.refresh_rounded, color: AppTheme.textSecondary, size: 18),
            ),
        ]).animate().fadeIn(delay: 300.ms),
        const SizedBox(height: 12),

        ...accounts.asMap().entries.map((entry) {
          final i       = entry.key;
          final account = entry.value;
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _AccountCard(
              account: account,
              isLoading:  _isLoading && _loadingId == account.id,
              isDisabled: _isLoading && _loadingId != account.id,
              onTap:    () => _loadAccount(account),
              onDelete: () => _confirmDelete(context, account),
            ),
          ).animate()
            .fadeIn(delay: Duration(milliseconds: 350 + i * 60))
            .slideY(begin: 0.06, end: 0, delay: Duration(milliseconds: 350 + i * 60));
        }),
        const SizedBox(height: 16),
      ],

      _buildAddButton(l),
      const SizedBox(height: 12),
      _buildDirectButton(l),
    ]);
  }

  Widget _buildLogo() {
    final l = context.read<LanguageProvider>().l10n;
    return Column(children: [
      Container(
        width: 80, height: 80,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(color: AppTheme.violet.withOpacity(0.45), blurRadius: 28, spreadRadius: 4),
            BoxShadow(color: AppTheme.red.withOpacity(0.20), blurRadius: 14, offset: const Offset(0, 6)),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: Image.asset('assets/logo.png', width: 80, height: 80, fit: BoxFit.cover),
        ),
      ),
      const SizedBox(height: 14),
      Text('Arich Player',
        style: GoogleFonts.poppins(
          color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.5,
        )).animate().fadeIn(delay: 200.ms),
      SizedBox(height: 3),
      Text(context.read<LanguageProvider>().l10n.t('tagline'),
        style: GoogleFonts.poppins(color: AppTheme.textSecondary, fontSize: 12),
      ).animate().fadeIn(delay: 300.ms),
    ]);
  }

  Widget _buildAccountHeader(AppL10n l, String email) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.violet.withOpacity(0.40), width: 1.5),
        boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.10), blurRadius: 16)],
      ),
      child: Row(children: [
        Container(
          width: 38, height: 38,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.person_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(email,
            style: GoogleFonts.poppins(
              color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis),
          Row(children: [
            Icon(Icons.circle, color: AppTheme.success, size: 7),
            SizedBox(width: 5),
            Flexible(child: Text(context.read<LanguageProvider>().l10n.t('auth_connected'),
              style: GoogleFonts.poppins(color: AppTheme.success, fontSize: 11), overflow: TextOverflow.ellipsis)),
          ]),
        ])),
        AnimatedRotation(
          turns: _isSyncing ? 1 : 0,
          duration: const Duration(milliseconds: 800),
          child: GestureDetector(
            onTap: _isSyncing ? null : _syncPlaylists,
            child: Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                color: AppTheme.violet.withOpacity(0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(Icons.sync_rounded, color: AppTheme.violet, size: 18),
            ),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () async {
            await SupabaseService.signOut();
            widget.onSignOut();
          },
          child: Container(
            width: 34, height: 34,
            decoration: BoxDecoration(
              color: AppTheme.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(Icons.logout_rounded, color: AppTheme.red, size: 17),
          ),
        ),
      ]),
    ).animate().fadeIn(delay: 150.ms).slideY(begin: 0.05, end: 0, delay: 150.ms);
  }

  Widget _buildEmptyState(AppL10n l) {
    return Container(
      padding: const EdgeInsets.all(28),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(children: [
        Icon(Icons.playlist_add_rounded, color: AppTheme.textMuted, size: 48),
        SizedBox(height: 14),
        Text(context.read<LanguageProvider>().l10n.t('playlist_none'),
          style: GoogleFonts.poppins(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
        SizedBox(height: 6),
        Text(context.read<LanguageProvider>().l10n.t('arich_signin_desc'),
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            color: AppTheme.textSecondary, fontSize: 12, height: 1.5,
          )),
      ]),
    ).animate().fadeIn(delay: 350.ms);
  }

  Widget _buildAddButton(AppL10n l) {
    return SizedBox(
      height: 52,
      child: ElevatedButton(
        onPressed: _isLoading ? null : widget.onAddNew,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white, foregroundColor: Colors.black,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          elevation: 0,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.add_rounded, size: 20),
          SizedBox(width: 8),
          Text(context.read<LanguageProvider>().l10n.t('playlist_add'),
            style: GoogleFonts.poppins(fontWeight: FontWeight.w600, fontSize: 14)),
        ]),
      ),
    ).animate().fadeIn(delay: 500.ms).slideY(begin: 0.06, end: 0, delay: 500.ms);
  }

  Widget _buildDirectButton(AppL10n l) {
    return SizedBox(
      height: 44,
      child: OutlinedButton(
        onPressed: _isLoading ? null : () => _showDirectDialog(context, l),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: Colors.white.withOpacity(0.15)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          foregroundColor: AppTheme.textSecondary,
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.link_rounded, size: 16),
          SizedBox(width: 8),
          Text(context.read<LanguageProvider>().l10n.t('playlist_url_m3u'), style: GoogleFonts.poppins(fontSize: 12)),
        ]),
      ),
    ).animate().fadeIn(delay: 560.ms);
  }

  void _showDirectDialog(BuildContext context, AppL10n l) {
    final urlCtrl   = TextEditingController();
    final titleCtrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(context.read<LanguageProvider>().l10n.t('login_m3u'),
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w600)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextFormField(
            controller: urlCtrl,
            style: const TextStyle(color: Colors.white),
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(
              labelText: 'URL M3U8',
              hintText: 'https://exemple.com/stream.m3u8',
              prefixIcon: Icon(Icons.link_rounded, color: AppTheme.textSecondary),
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: titleCtrl,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Titre (optionnel)',
              prefixIcon: Icon(Icons.title_rounded, color: AppTheme.textSecondary),
            ),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: Text(context.read<LanguageProvider>().l10n.t('cancel'),
              style: GoogleFonts.poppins(color: AppTheme.textSecondary))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.primary),
            onPressed: () async {
            final url = urlCtrl.text.trim();
            if (url.isEmpty) return;

            // 1. Validation de l'URL pour éviter les crashs si l'utilisateur tape n'importe quoi
            final parsedUri = Uri.tryParse(url);
            if (parsedUri == null || parsedUri.host.isEmpty) {
              ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(
                content: const Text('URL invalide. Vérifiez le format.'),
                backgroundColor: AppTheme.red,
              ));
              return;
            }

            // 2. Fermeture du dialogue
            Navigator.pop(ctx);

            // 3. Navigation avec une transition "Fade" (Fondu) élégante
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => PlayerScreen(
                  streamUrl: url,
                  title: titleCtrl.text.trim().isEmpty ? 'Lecture directe' : titleCtrl.text.trim(),
                  tabIndex: 1,
                ),
                transitionsBuilder: (_, anim, __, child) =>
                    FadeTransition(opacity: anim, child: child),
                transitionDuration: const Duration(milliseconds: 300),
              ),
            );
          },
            child: Text(context.read<LanguageProvider>().l10n.t('home_play'),
              style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────────────────────
// MOBILE — ACCOUNT CARD
// ─────────────────────────────────────────────────────────────────────────────

class _AccountCard extends StatelessWidget {
  final PlaylistAccount account;
  final bool isLoading;
  final bool isDisabled;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _AccountCard({
    required this.account, required this.isLoading,
    required this.isDisabled, required this.onTap, required this.onDelete,
  });

  Color get _color {
    try { return Color(int.parse(account.color.replaceFirst('#', '0xFF'))); }
    catch (_) { return AppTheme.primary; }
  }

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: isDisabled ? 0.45 : 1.0,
      child: GestureDetector(
        onTap: isDisabled ? null : onTap,
        onLongPress: isDisabled ? null : onDelete,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.surfaceHigh,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: account.isActive ? _color.withOpacity(0.6) : Colors.white.withOpacity(0.06),
              width: account.isActive ? 1.5 : 1,
            ),
            boxShadow: account.isActive
                ? [BoxShadow(color: _color.withOpacity(0.12), blurRadius: 12)]
                : [],
          ),
          child: Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                color: _color.withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _color.withOpacity(0.3)),
              ),
              child: isLoading
                  ? Padding(padding: const EdgeInsets.all(10),
                      child: CircularProgressIndicator(strokeWidth: 2.5, color: _color))
                  : Icon(account.typeIcon, color: _color, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Expanded(child: Text(account.name,
                  style: GoogleFonts.poppins(
                    color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis)),
                if (account.isActive)
                  Container(
                    padding: EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: _color.withOpacity(0.15), borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(context.read<LanguageProvider>().l10n.t('playlist_active'),
                      style: GoogleFonts.poppins(
                        color: _color, fontSize: 9, fontWeight: FontWeight.w700,
                      )),
                  ),
              ]),
              const SizedBox(height: 3),
              Text(account.subtitle,
                style: GoogleFonts.poppins(color: AppTheme.textSecondary, fontSize: 11),
                overflow: TextOverflow.ellipsis),
            ])),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: AppTheme.background, borderRadius: BorderRadius.circular(6),
              ),
              child: Text(account.typeLabel,
                style: GoogleFonts.poppins(
                  color: AppTheme.textMuted, fontSize: 9,
                  fontWeight: FontWeight.w500, letterSpacing: 0.5,
                )),
            ),
            const SizedBox(width: 8),
            isLoading
                ? const SizedBox(width: 16)
                : const Icon(Icons.arrow_forward_ios_rounded,
                    color: AppTheme.textMuted, size: 13),
          ]),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// GLOW BG
// ─────────────────────────────────────────────────────────────────────────────

class _GlowBg extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Stack(children: [
      Positioned(
        top: -80, left: -80,
        child: Container(
          width: 320, height: 320,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.violet.withOpacity(0.13),
              Colors.transparent,
            ]),
          ),
        ),
      ),
      Positioned(
        bottom: -60, right: -60,
        child: Container(
          width: 280, height: 280,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              AppTheme.red.withOpacity(0.08),
              Colors.transparent,
            ]),
          ),
        ),
      ),
    ]);
  }
}