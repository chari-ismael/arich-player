// lib/ui/widgets/add_playlist_sheet.dart
// [v12] Refonte UI : overflow fix, boutons presse-papier, mémoire champs, style premium

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../providers/iptv_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../services/m3u_parser.dart';

// ── Clés SharedPreferences pour mémoriser les champs ──────────────────────
const _kPrefM3uUrl      = 'add_playlist_m3u_url';
const _kPrefXtUrl       = 'add_playlist_xt_url';
const _kPrefXtUser      = 'add_playlist_xt_user';
const _kPrefXtName      = 'add_playlist_xt_name';
const _kPrefLastTab     = 'add_playlist_last_tab';

Future<void> showAddPlaylistSheet(BuildContext context) async {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    useSafeArea: true,
    builder: (sheetContext) => AddPlaylistSheet(parentContext: context),
  );
}

class AddPlaylistSheet extends StatefulWidget {
  final BuildContext parentContext;
  const AddPlaylistSheet({super.key, required this.parentContext});

  @override
  State<AddPlaylistSheet> createState() => _AddPlaylistSheetState();
}

class _AddPlaylistSheetState extends State<AddPlaylistSheet>
    with SingleTickerProviderStateMixin {

  // ── Contrôleurs M3U ───────────────────────────────────────────────────────
  final _m3uUrlCtrl  = TextEditingController();
  final _m3uNameCtrl = TextEditingController();
  final _m3uFormKey  = GlobalKey<FormState>();

  // ── Contrôleurs Xtream ────────────────────────────────────────────────────
  final _xtNameCtrl = TextEditingController();
  final _xtUrlCtrl  = TextEditingController();
  final _xtUserCtrl = TextEditingController();
  final _xtPassCtrl = TextEditingController();
  final _xtFormKey  = GlobalKey<FormState>();

  bool _obscurePass = true;
  bool _loading     = false;
  String _errorMsg  = '';

  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _restoreFields();
  }

  @override
  void dispose() {
    _m3uUrlCtrl.dispose();
    _m3uNameCtrl.dispose();
    _xtNameCtrl.dispose();
    _xtUrlCtrl.dispose();
    _xtUserCtrl.dispose();
    _xtPassCtrl.dispose();
    _tabController.dispose();
    super.dispose();
  }

  // ── Mémoire des champs ────────────────────────────────────────────────────
  Future<void> _restoreFields() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _m3uUrlCtrl.text  = prefs.getString(_kPrefM3uUrl)  ?? '';
      _xtUrlCtrl.text   = prefs.getString(_kPrefXtUrl)   ?? '';
      _xtUserCtrl.text  = prefs.getString(_kPrefXtUser)  ?? '';
      _xtNameCtrl.text  = prefs.getString(_kPrefXtName)  ?? '';
      final lastTab     = prefs.getInt(_kPrefLastTab)     ?? 0;
      _tabController.index = lastTab;
    });
  }

  Future<void> _saveM3uFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefM3uUrl, _m3uUrlCtrl.text.trim());
    await prefs.setInt(_kPrefLastTab, 0);
  }

  Future<void> _saveXtreamFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kPrefXtUrl,  _xtUrlCtrl.text.trim());
    await prefs.setString(_kPrefXtUser, _xtUserCtrl.text.trim());
    await prefs.setString(_kPrefXtName, _xtNameCtrl.text.trim());
    await prefs.setInt(_kPrefLastTab, 1);
  }

  Future<void> _clearSavedFields() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kPrefM3uUrl);
    await prefs.remove(_kPrefXtUrl);
    await prefs.remove(_kPrefXtUser);
    await prefs.remove(_kPrefXtName);
  }

  // ── Presse-papier ─────────────────────────────────────────────────────────
  Future<void> _paste(TextEditingController ctrl) async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) return;
    ctrl.text = text;
    ctrl.selection = TextSelection.collapsed(offset: text.length);
    setState(() => _errorMsg = '');
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _sanitize(String url) {
    final u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) return 'http://$u';
    return u;
  }

  String _guessName(String url) {
    try {
      final host = Uri.parse(url).host;
      return host.isNotEmpty ? host : 'Ma Playlist';
    } catch (_) {
      return 'Ma Playlist';
    }
  }

  // ── Submit M3U ────────────────────────────────────────────────────────────
  Future<void> _submitM3u() async {
    if (!(_m3uFormKey.currentState?.validate() ?? false)) return;
    await _saveM3uFields();

    setState(() { _loading = true; _errorMsg = ''; });

    final url = _m3uUrlCtrl.text.trim();
    try {
      final iptvProvider = widget.parentContext.read<IptvProvider>();
      final ok = await iptvProvider.loginM3u(url);

      if (!ok) {
        setState(() {
          _errorMsg = iptvProvider.errorMessage.isNotEmpty
              ? iptvProvider.errorMessage
              : 'Impossible de charger la playlist';
          _loading = false;
        });
        return;
      }

      final playlistProvider = widget.parentContext.read<PlaylistProvider>();
      final name = _m3uNameCtrl.text.trim().isEmpty
          ? _guessName(url)
          : _m3uNameCtrl.text.trim();

      await playlistProvider.addM3u(
        name: name,
        m3uUrl: url,
        setActive: true,
      );

      await _clearSavedFields();

      if (mounted) {
        final count = iptvProvider.allLive.length;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('✅ $count chaînes chargées'),
          backgroundColor: const Color(0xFF4CAF50),
          duration: const Duration(seconds: 3),
        ));
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() { _errorMsg = e.toString(); _loading = false; });
    }
  }

  // ── Submit Xtream ─────────────────────────────────────────────────────────
  Future<void> _submitXtream() async {
    if (!(_xtFormKey.currentState?.validate() ?? false)) return;
    final url  = _sanitize(_xtUrlCtrl.text);
    final user = _xtUserCtrl.text.trim();
    final pass = _xtPassCtrl.text.trim();

    final parsedUri = Uri.tryParse(url);
    if (parsedUri == null ||
        parsedUri.host.isEmpty ||
        !M3uParser.isPlausibleHttpAuthority(parsedUri)) {
      setState(() => _errorMsg =
          'URL serveur invalide.\nExemple : http://serveur.com:8080');
      return;
    }

    await _saveXtreamFields();
    setState(() { _loading = true; _errorMsg = ''; });

    final iptv = widget.parentContext.read<IptvProvider>();
    final pp   = widget.parentContext.read<PlaylistProvider>();

    try {
      final ok = await iptv.login(url, user, pass);
      if (!mounted) return;
      setState(() => _loading = false);

      if (ok) {
        final name = _xtNameCtrl.text.trim().isEmpty
            ? _guessName(url)
            : _xtNameCtrl.text.trim();
        await pp.addXtream(
          name: name,
          serverUrl: url,
          username: user,
          password: pass,
          setActive: true,
        );
        await _clearSavedFields();
        if (mounted) Navigator.pop(context);
      } else {
        setState(() => _errorMsg = iptv.errorMessage);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() { _loading = false; _errorMsg = 'Erreur : $e'; });
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      // [FIX-OVERFLOW] padding bottom = clavier + safe area
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHandle(),
          _buildHeader(),
          _buildTabBar(),
          // [FIX-OVERFLOW] Expanded + SingleChildScrollView dans chaque onglet
          Flexible(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildM3uTab(),
                _buildXtreamTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHandle() => Padding(
    padding: const EdgeInsets.only(top: 12, bottom: 4),
    child: Container(
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );

  Widget _buildHeader() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
    child: Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF7B2FF7), Color(0xFFE91E8C)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7B2FF7).withOpacity(0.4),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: const Icon(Icons.playlist_add_rounded, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ajouter une playlist',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.2,
              ),
            ),
            Text(
              'M3U URL ou Xtream Codes',
              style: GoogleFonts.poppins(
                color: Colors.white38,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ],
    ),
  );

  Widget _buildTabBar() => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
    child: Container(
      height: 40,
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: _tabController,
        onTap: (_) => setState(() => _errorMsg = ''),
        indicator: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF7B2FF7), Color(0xFFE91E8C)],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: Colors.white38,
        labelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.poppins(
          fontSize: 13,
          fontWeight: FontWeight.w400,
        ),
        tabs: const [
          Tab(text: 'M3U URL'),
          Tab(text: 'Xtream Codes'),
        ],
      ),
    ),
  );

  // ── Onglet M3U ────────────────────────────────────────────────────────────
  Widget _buildM3uTab() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    child: Form(
      key: _m3uFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('URL de la playlist'),
          const SizedBox(height: 8),
          _fieldWithPaste(
            controller: _m3uUrlCtrl,
            hint: 'http://serveur.com/get.php?username=…&type=m3u_plus',
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'L\'URL est requise';
              if (!v.startsWith('http://') && !v.startsWith('https://'))
                return 'L\'URL doit commencer par http:// ou https://';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _fieldLabel('Nom (optionnel)'),
          const SizedBox(height: 8),
          _styledField(
            controller: _m3uNameCtrl,
            hint: 'Laissez vide pour auto-détection',
          ),
          const SizedBox(height: 20),
          if (_errorMsg.isNotEmpty) ...[_errorBox(), const SizedBox(height: 16)],
          _submitButton(label: 'Ajouter la playlist', onTap: _submitM3u),
          const SizedBox(height: 16),
          _tipBox(
            '💡 Format attendu',
            'http://serveur.com/get.php?username=XXX&password=YYY&type=m3u_plus',
          ),
        ],
      ),
    ),
  );

  // ── Onglet Xtream ─────────────────────────────────────────────────────────
  Widget _buildXtreamTab() => SingleChildScrollView(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
    child: Form(
      key: _xtFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _fieldLabel('URL du serveur'),
          const SizedBox(height: 8),
          _fieldWithPaste(
            controller: _xtUrlCtrl,
            hint: 'http://serveur.com:8080',
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'L\'URL est requise';
              final uri = Uri.tryParse(v.trim());
              if (uri == null || uri.host.isEmpty) return 'URL invalide';
              return null;
            },
          ),
          const SizedBox(height: 16),
          _fieldLabel('Nom d\'utilisateur'),
          const SizedBox(height: 8),
          _fieldWithPaste(
            controller: _xtUserCtrl,
            hint: 'username',
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Requis' : null,
          ),
          const SizedBox(height: 16),
          _fieldLabel('Mot de passe'),
          const SizedBox(height: 8),
          _passwordField(),
          const SizedBox(height: 16),
          _fieldLabel('Nom du compte (optionnel)'),
          const SizedBox(height: 8),
          _styledField(
            controller: _xtNameCtrl,
            hint: 'Ex : Mon abonnement principal',
          ),
          const SizedBox(height: 20),
          if (_errorMsg.isNotEmpty) ...[_errorBox(), const SizedBox(height: 16)],
          _submitButton(label: 'Se connecter', onTap: _submitXtream),
        ],
      ),
    ),
  );

  // ── Composants UI réutilisables ───────────────────────────────────────────

  Widget _fieldLabel(String text) => Text(
    text,
    style: GoogleFonts.poppins(
      color: Colors.white70,
      fontSize: 12,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.3,
    ),
  );

  InputDecoration _inputDecoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: GoogleFonts.poppins(color: Colors.white24, fontSize: 13),
    filled: true,
    fillColor: const Color(0xFF161616),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF2A2A2A)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFF7B2FF7), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE91E8C), width: 1.5),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE91E8C), width: 1.5),
    ),
    errorStyle: GoogleFonts.poppins(color: const Color(0xFFE91E8C), fontSize: 11),
  );

  Widget _styledField({
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
    bool enabled = true,
  }) =>
      TextFormField(
        controller: controller,
        enabled: !_loading && enabled,
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
        decoration: _inputDecoration(hint),
        validator: validator,
      );

  /// Champ texte + bouton coller intégré à droite
  Widget _fieldWithPaste({
    required TextEditingController controller,
    required String hint,
    String? Function(String?)? validator,
  }) =>
      Stack(
        children: [
          TextFormField(
            controller: controller,
            enabled: !_loading,
            style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
            decoration: _inputDecoration(hint).copyWith(
              // Laisser de la place pour le bouton coller
              suffixIcon: const SizedBox(width: 70),
            ),
            validator: validator,
          ),
          Positioned(
            right: 6,
            top: 0,
            bottom: 0,
            child: Center(
              child: _pasteButton(() => _paste(controller)),
            ),
          ),
        ],
      );

  Widget _pasteButton(VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF7B2FF7).withOpacity(0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFF7B2FF7).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.content_paste_rounded, color: Color(0xFF7B2FF7), size: 13),
          const SizedBox(width: 4),
          Text(
            'Coller',
            style: GoogleFonts.poppins(
              color: const Color(0xFF7B2FF7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );

  Widget _passwordField() => Stack(
    children: [
      TextFormField(
        controller: _xtPassCtrl,
        enabled: !_loading,
        obscureText: _obscurePass,
        style: GoogleFonts.poppins(color: Colors.white, fontSize: 13),
        decoration: _inputDecoration('password').copyWith(
          suffixIcon: const SizedBox(width: 70),
        ),
        validator: (v) =>
            (v == null || v.trim().isEmpty) ? 'Requis' : null,
      ),
      Positioned(
        right: 6,
        top: 0,
        bottom: 0,
        child: Center(
          child: GestureDetector(
            onTap: () => setState(() => _obscurePass = !_obscurePass),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.05),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Colors.white12),
              ),
              child: Icon(
                _obscurePass
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.white38,
                size: 15,
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _errorBox() => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFE91E8C).withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xFFE91E8C).withOpacity(0.25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.error_outline_rounded,
            color: Color(0xFFE91E8C), size: 16),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _errorMsg,
            style: GoogleFonts.poppins(
              color: const Color(0xFFE91E8C),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _submitButton({
    required String label,
    required VoidCallback onTap,
  }) =>
      SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: _loading ? null : onTap,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            padding: EdgeInsets.zero,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ).copyWith(
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return const Color(0xFF2A2A2A);
              }
              return null;
            }),
          ),
          child: Ink(
            decoration: _loading
                ? BoxDecoration(
                    color: const Color(0xFF2A2A2A),
                    borderRadius: BorderRadius.circular(12),
                  )
                : BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF7B2FF7), Color(0xFFE91E8C)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF7B2FF7).withOpacity(0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
            child: Center(
              child: _loading
                  ? Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white54),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Chargement…',
                          style: GoogleFonts.poppins(
                            color: Colors.white54,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    )
                  : Text(
                      label,
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
        ),
      );

  Widget _tipBox(String title, String content) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFF161616),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: Colors.white.withOpacity(0.05)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: GoogleFonts.poppins(
            color: const Color(0xFF7B2FF7),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          content,
          style: GoogleFonts.poppins(
            color: Colors.white38,
            fontSize: 11,
            height: 1.5,
          ),
        ),
      ],
    ),
  );
}