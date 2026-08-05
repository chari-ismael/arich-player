// lib/ui/widgets/license_gate.dart
//
// Arich Player — License Gate v2.0
//
// Verrou d'accès entièrement piloté par Supabase.
//
// COMMENT ÇA MARCHE :
//   • LicenseProvider lit app_config.license_enforcement depuis Supabase
//   • Si enforcement = false (défaut) → tout le monde passe, sans exception
//   • Si enforcement = true           → les licences expirées/suspendues sont bloquées
//   • Ce switch s'applique à TOUS les APKs (anciens et nouveaux) sans rebuild
//
// POUR ACTIVER LE BLOCAGE (quand tu veux monétiser) :
//   Dans Supabase SQL Editor :
//   UPDATE app_config SET value = 'true' WHERE key = 'license_enforcement';
//
// POUR DÉSACTIVER (retour mode open) :
//   UPDATE app_config SET value = 'false' WHERE key = 'license_enforcement';
//
// USAGE :
//   _go(const LicenseGate(child: HomeScreen()));
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme.dart';
import '../../providers/license_provider.dart';

class LicenseGate extends StatelessWidget {
  final Widget child;
  const LicenseGate({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer<LicenseProvider>(
      builder: (context, lp, _) {
        // Enforcement serveur OFF → accès libre pour tout le monde
        if (!lp.enforcementActive) return child;

        // Pendant le check initial → fail-open
        if (lp.isChecking && lp.license == null) return child;

        // Licence valide → accès normal
        if (lp.isValid) return child;

        // Licence invalide → écran de blocage
        return _BlockedScreen(suspended: lp.isSuspended);
      },
    );
  }
}

// ── Écran de blocage ──────────────────────────────────────────────────────────

class _BlockedScreen extends StatefulWidget {
  final bool suspended;
  const _BlockedScreen({required this.suspended});
  @override State<_BlockedScreen> createState() => _BlockedScreenState();
}

class _BlockedScreenState extends State<_BlockedScreen> {
  bool _retrying = false;

  Future<void> _retry() async {
    setState(() => _retrying = true);
    await context.read<LicenseProvider>().forceRefresh();
    if (mounted) setState(() => _retrying = false);
  }

  Future<void> _openRenew() async {
    final url = Uri.parse('https://arich.fr/premium');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openSupport() async {
    final url = Uri.parse('https://t.me/arichsupport');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lp = context.watch<LicenseProvider>();

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [

              // Icône
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (widget.suspended ? AppTheme.danger : AppTheme.gold)
                      .withOpacity(0.12),
                  border: Border.all(
                    color: (widget.suspended ? AppTheme.danger : AppTheme.gold)
                        .withOpacity(0.4),
                    width: 1.5),
                ),
                child: Icon(
                  widget.suspended
                      ? Icons.block_rounded
                      : Icons.lock_clock_rounded,
                  color: widget.suspended ? AppTheme.danger : AppTheme.gold,
                  size: 38,
                ),
              ).animate().scale(duration: 500.ms, curve: Curves.elasticOut),
              const SizedBox(height: 28),

              // Titre
              Text(
                widget.suspended ? 'Compte suspendu' : 'Accès expiré',
                style: const TextStyle(
                  color: Colors.white, fontSize: 24,
                  fontWeight: FontWeight.w800, letterSpacing: -0.3),
                textAlign: TextAlign.center,
              ).animate(delay: 150.ms).fadeIn().slideY(begin: 0.1),
              const SizedBox(height: 10),

              // Sous-titre
              Text(
                widget.suspended
                    ? 'Votre compte a été suspendu.\nContactez le support pour plus d\'informations.'
                    : 'Votre accès est terminé.\nPassez à Premium pour continuer à profiter de Arich Player.',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.5),
                  fontSize: 14, height: 1.6),
                textAlign: TextAlign.center,
              ).animate(delay: 200.ms).fadeIn(),
              const SizedBox(height: 16),

              // Badge plan actuel
              if (lp.license != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color:        AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(12),
                    border:       Border.all(color: AppTheme.border),
                  ),
                  child: Text(
                    'Plan actuel : ${lp.license!.planLabel}',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.6),
                      fontSize: 12, fontWeight: FontWeight.w500),
                  ),
                ).animate(delay: 250.ms).fadeIn(),
              const SizedBox(height: 36),

              // Bouton principal
              if (!widget.suspended)
                _BigButton(
                  label:    'Passer à Premium',
                  icon:     Icons.star_rounded,
                  gradient: AppTheme.gradientPrimary,
                  onTap:    _openRenew,
                ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.08),

              if (widget.suspended)
                _BigButton(
                  label:    'Contacter le support',
                  icon:     Icons.support_agent_rounded,
                  gradient: LinearGradient(
                    colors: [AppTheme.danger, AppTheme.danger.withOpacity(0.7)]),
                  onTap:    _openSupport,
                ).animate(delay: 300.ms).fadeIn().slideY(begin: 0.08),

              const SizedBox(height: 12),

              // Bouton retry
              GestureDetector(
                onTap: _retrying ? null : _retry,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  decoration: BoxDecoration(
                    color:        AppTheme.surfaceHigh,
                    borderRadius: BorderRadius.circular(14),
                    border:       Border.all(color: AppTheme.border),
                  ),
                  child: _retrying
                      ? const SizedBox(
                          height: 20,
                          child: Center(child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white54),
                          )))
                      : const Text('Vérifier à nouveau',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white54, fontSize: 14,
                            fontWeight: FontWeight.w600)),
                ),
              ).animate(delay: 380.ms).fadeIn(),
              const SizedBox(height: 12),

              // Support secondaire
              if (!widget.suspended)
                TextButton(
                  onPressed: _openSupport,
                  child: Text('Support & contact',
                    style: TextStyle(
                      color:           Colors.white.withOpacity(0.3),
                      fontSize:        12,
                      decoration:      TextDecoration.underline,
                      decorationColor: Colors.white.withOpacity(0.2))),
                ).animate(delay: 450.ms).fadeIn(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Bouton pleine largeur ─────────────────────────────────────────────────────

class _BigButton extends StatelessWidget {
  final String    label;
  final IconData  icon;
  final Gradient  gradient;
  final VoidCallback onTap;
  const _BigButton({required this.label, required this.icon,
    required this.gradient, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient:     gradient,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [BoxShadow(
            color:      AppTheme.violet.withOpacity(0.35),
            blurRadius: 20, offset: const Offset(0, 6))],
        ),
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(
            color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}