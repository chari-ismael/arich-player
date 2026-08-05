// lib/ui/screens/license_screen.dart
//
// Arich Player ?? ?cran de Licence Premium
// Affiché au premier lancement ou depuis les Paramètres
// ??????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../services/device_service.dart';

class LicenseScreen extends StatefulWidget {
 /// Si true : affiché en pleine page (premier lancement).
 /// Si false : affiché depuis les Paramètres (drawer/bottom sheet).
  final bool isFullPage;
  final VoidCallback? onContinue;

  const LicenseScreen({
    super.key,
    this.isFullPage = true,
    this.onContinue,
  });

  @override
  State<LicenseScreen> createState() => _LicenseScreenState();
}

class _LicenseScreenState extends State<LicenseScreen>
    with SingleTickerProviderStateMixin {
  DeviceIdentity? _identity;
  Map<String, dynamic>? _licenseData;
  bool _loading = true;
  bool _macCopied = false;
  bool _keyCopied = false;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _loadIdentity();
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadIdentity() async {
    final identity = await DeviceService.getOrCreate();
    final license  = await DeviceService.getLicense(identity);
    if (mounted) {
      setState(() {
        _identity    = identity;
        _licenseData = license;
        _loading     = false;
      });
    }
  }

 // ??????????????????????????????????????????????????????????????????????????????????????????
 // HELPERS
 // ??????????????????????????????????????????????????????????????????????????????????????????

  String get _licenseStatus {
    final raw = _licenseData?['license']?['status'] as String? ?? 'trial';
    switch (raw) {
      case 'active':    return 'ACTIF';
      case 'trial':     return 'ESSAI';
      case 'expired':   return 'EXPIR�?';
      case 'suspended': return 'SUSPENDU';
      case 'banned':    return 'BANNI';
      default:          return 'INCONNU';
    }
  }

  Color get _statusColor {
    final raw = _licenseData?['license']?['status'] as String? ?? 'trial';
    switch (raw) {
      case 'active':    return const Color(0xFF00E676);
      case 'trial':     return AppTheme.gold;
      case 'expired':   return AppTheme.error;
      case 'suspended': return Colors.orange;
      case 'banned':    return AppTheme.error;
      default:          return Colors.grey;
    }
  }

  String get _expiresText {
    final raw = _licenseData?['license']?['expires_at'] as String?;
    if (raw == null) return 'Illimité';
    final dt = DateTime.tryParse(raw);
    if (dt == null) return 'Inconnu';
    final diff = dt.difference(DateTime.now());
    if (diff.isNegative) return 'Expiré';
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()} an(s)';
    if (diff.inDays > 0) return '${diff.inDays} jour(s)';
    return '${diff.inHours} heure(s)';
  }

  String get _planName =>
      _licenseData?['license']?['plan_name'] as String? ?? 'Essai gratuit';

  Future<void> _copy(String value, {required bool isMac}) async {
    await Clipboard.setData(ClipboardData(text: value));
    setState(() {
      if (isMac) { _macCopied = true; }
      else        { _keyCopied = true; }
    });
    await Future.delayed(const Duration(seconds: 2));
    if (mounted) setState(() { _macCopied = false; _keyCopied = false; });
  }

  Future<void> _openPanel() async {
    if (_identity == null) return;
    final url = Uri.parse(DeviceService.buildQrUrl(_identity!));
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

 // ??????????????????????????????????????????????????????????????????????????????????????????
 // BUILD
 // ??????????????????????????????????????????????????????????????????????????????????????????

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background,
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
          : _buildContent(),
    );
  }

  Widget _buildContent() {
    final identity = _identity!;
    final qrUrl    = DeviceService.buildQrUrl(identity);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
 // ???? AppBar ??????????????????????????????????????????????????????????????????????????????????????????????????????????????
        SliverAppBar(
          backgroundColor: Colors.transparent,
          expandedHeight: 0,
          floating: true,
          pinned: false,
          elevation: 0,
          leading: widget.isFullPage
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
          actions: [
            if (widget.isFullPage && widget.onContinue != null)
              TextButton(
                onPressed: widget.onContinue,
                child: const Text(
                  'Continuer �??',
                  style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
                ),
              ),
          ],
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
 // ???? Logo + Titre ????????????????????????????????????????????????????????????????????????????????????
                _buildHeader(),
                const SizedBox(height: 32),

 // ???? Badge status licence ????????????????????????????????????????????????????????????????????
                _buildStatusBadge(),
                const SizedBox(height: 28),

 // ???? Carte MAC + Key ??????????????????????????????????????????????????????????????????????????????
                _buildCredentialsCard(identity),
                const SizedBox(height: 24),

 // ???? QR Code ??????????????????????????????????????????????????????????????????????????????????????????????
                _buildQrCard(qrUrl),
                const SizedBox(height: 24),

 // ???? Infos device ??????????????????????????????????????????????????????????????????????????????????
                _buildDeviceInfo(identity),
                const SizedBox(height: 32),

 // ???? Bouton panel web ????????????????????????????????????????????????????????????????????????????
                _buildPanelButton(),
                const SizedBox(height: 16),

 // ???? Avertissement technique ??????????????????????????????????????????????????????????????
                _buildTechNote(),
                const SizedBox(height: 24),

 // ???? Bouton continuer ????????????????????????????????????????????????????????????????????????????
                if (widget.isFullPage && widget.onContinue != null)
                  _buildContinueButton(),
              ],
            ),
          ),
        ),
      ],
    );
  }

 // ??????????????????????????????????????????????????????????????????????????????????????????
 // WIDGETS COMPOSANTS
 // ??????????????????????????????????????????????????????????????????????????????????????????

  Widget _buildHeader() {
    return Column(
      children: [
 // Icône animée
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: AppTheme.gradientPrimary,
              boxShadow: [
                BoxShadow(
                  color: AppTheme.violet.withValues(
                      alpha: 0.3 + 0.2 * _pulseCtrl.value),
                  blurRadius: 24 + 8 * _pulseCtrl.value,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: const Icon(Icons.shield_rounded, color: Colors.white, size: 36),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          'Arich Player',
          style: TextStyle(
            color: Colors.white,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: 2.0,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Licence & Activation',
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.45),
            fontSize: 13,
            fontWeight: FontWeight.w400,
            letterSpacing: 0.5,
          ),
        ),
      ],
    ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.1, end: 0);
  }

  Widget _buildStatusBadge() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: _statusColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _statusColor.withValues(alpha: 0.4), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: _statusColor,
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(color: _statusColor, blurRadius: 6)],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '$_planName �?? $_licenseStatus',
                style: TextStyle(
                  color: _statusColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '($_expiresText)',
                style: TextStyle(
                  color: _statusColor.withValues(alpha: 0.7),
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    ).animate().fadeIn(delay: 200.ms);
  }

  Widget _buildCredentialsCard(DeviceIdentity identity) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.violet.withValues(alpha: 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.router_rounded, color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Identifiant Appareil',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const Spacer(),
              _infoBadge('Virtuelle'),
            ],
          ),
          const SizedBox(height: 18),

 // MAC Address
          _credentialRow(
            label: context.read<LanguageProvider>().l10n.t('license_mac'),
            value: identity.macAddress,
            icon: Icons.memory_rounded,
            isCopied: _macCopied,
            onCopy: () => _copy(identity.macAddress, isMac: true),
            color: AppTheme.violet,
          ),
          const SizedBox(height: 12),

 // Device Key
          _credentialRow(
            label: context.read<LanguageProvider>().l10n.t('license_device_key'),
            value: identity.deviceKey,
            icon: Icons.vpn_key_rounded,
            isCopied: _keyCopied,
            onCopy: () => _copy(identity.deviceKey, isMac: false),
            color: AppTheme.primary,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 300.ms).slideY(begin: 0.05, end: 0);
  }

  Widget _credentialRow({
    required String label,
    required String value,
    required IconData icon,
    required bool isCopied,
    required VoidCallback onCopy,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 10,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    fontFamily: 'monospace',
                  ),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: onCopy,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isCopied
                    ? const Color(0xFF00E676).withValues(alpha: 0.15)
                    : Colors.white.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                isCopied ? Icons.check_rounded : Icons.copy_rounded,
                color: isCopied ? const Color(0xFF00E676) : Colors.white54,
                size: 16,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQrCard(String qrUrl) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.qr_code_scanner_rounded,
                  color: AppTheme.primary, size: 16),
              const SizedBox(width: 8),
              const Text(
                'Scanner pour gérer votre abonnement',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
 // QR Code
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
            ),
            child: QrImageView(
              data: qrUrl,
              version: QrVersions.auto,
              size: 180,
              backgroundColor: Colors.white,
              eyeStyle: const QrEyeStyle(
                eyeShape: QrEyeShape.square,
                color: Color(0xFF0D0D1A),
              ),
              dataModuleStyle: const QrDataModuleStyle(
                dataModuleShape: QrDataModuleShape.square,
                color: Color(0xFF0D0D1A),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Pointez votre caméra ou appuyez pour ouvrir',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ).animate().fadeIn(delay: 400.ms).scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1));
  }

  Widget _buildDeviceInfo(DeviceIdentity identity) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surfaceHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Informations Appareil',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          _infoRow('Appareil', identity.deviceName),
          _infoRow('Modèle', identity.deviceModel),
          _infoRow('Marque', identity.deviceBrand),
          _infoRow('Android', identity.androidVersion),
        ],
      ),
    ).animate().fadeIn(delay: 500.ms);
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '�??' : value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPanelButton() {
    return GestureDetector(
      onTap: _openPanel,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: AppTheme.gradientPrimary,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppTheme.violet.withValues(alpha: 0.4),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.open_in_browser_rounded, color: Colors.white, size: 18),
            SizedBox(width: 10),
            Text(
              'Gérer mon abonnement',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 15,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
      ),
    ).animate().fadeIn(delay: 600.ms);
  }

  Widget _buildTechNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'L\'adresse MAC affichée est un identifiant virtuel unique généré par votre appareil '
              '(identique au fonctionnement de DuplexPlay et TiviMate). '
              'Elle reste stable tant que vous ne réinitialisez pas votre appareil en usine.',
              style: TextStyle(
                color: Colors.amber.withValues(alpha: 0.8),
                fontSize: 10,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    ).animate().fadeIn(delay: 700.ms);
  }

  Widget _buildContinueButton() {
    return GestureDetector(
      onTap: widget.onContinue,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppTheme.surfaceHigh,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
        ),
        child: const Text(
          'Continuer vers l\'application',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    ).animate().fadeIn(delay: 750.ms);
  }

  Widget _infoBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.amber,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}