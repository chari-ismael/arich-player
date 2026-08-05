// lib/ui/widgets/parental_gate.dart

import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:provider/provider.dart';
import '../../core/theme.dart';
import '../../core/l10n.dart';
import '../../providers/language_provider.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Clés Hive
// ─────────────────────────────────────────────────────────────────────────────

const _kParentalHash    = 'pref_parental_pin_hash';  // SHA-256 du PIN
const _kParentalEnabled = 'pref_parental_enabled';   // bool
const _kLockMovies      = 'pref_lock_movies';        // bool
const _kLockSeries      = 'pref_lock_series';        // bool
const _kLockLive        = 'pref_lock_live';          // bool
const _kLockSettings    = 'pref_lock_settings';      // bool

// ─────────────────────────────────────────────────────────────────────────────
// Helpers publics — à appeler depuis n'importe quel écran
// ─────────────────────────────────────────────────────────────────────────────

class ParentalControl {
  static Box get _box => Hive.box('settings');


  static bool get isEnabled => _box.get(_kParentalEnabled, defaultValue: false) as bool;

 static String? get savedHash => _box.get(_kParentalHash) as String?;

  static bool get lockMovies   => _box.get(_kLockMovies,   defaultValue: false) as bool;
  static bool get lockSeries   => _box.get(_kLockSeries,   defaultValue: false) as bool;
  static bool get lockLive     => _box.get(_kLockLive,     defaultValue: false) as bool;
  static bool get lockSettings => _box.get(_kLockSettings, defaultValue: false) as bool;

 static String hash(String pin) {
    final bytes = utf8.encode(pin);
    return sha256.convert(bytes).toString();
  }

 static bool verify(String pin) {
    final saved = savedHash;
    if (saved == null) return false;
    return hash(pin) == saved;
  }

 static Future<void> setPin(String pin) async {
    await _box.put(_kParentalHash, hash(pin));
    await _box.put(_kParentalEnabled, true);
  }

 static Future<void> disable() async {
    await _box.delete(_kParentalHash);
    await _box.put(_kParentalEnabled, false);
    await _box.put(_kLockMovies,   false);
    await _box.put(_kLockSeries,   false);
    await _box.put(_kLockLive,     false);
    await _box.put(_kLockSettings, false);
  }

  static Future<void> setLocks({
    required bool movies,
    required bool series,
    required bool live,
    required bool settings,
  }) async {
    await _box.put(_kLockMovies,   movies);
    await _box.put(_kLockSeries,   series);
    await _box.put(_kLockLive,     live);
    await _box.put(_kLockSettings, settings);
  }

  static Future<bool> showGate(BuildContext context, {String mode = 'unlock'}) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => _PinGateDialog(mode: mode),
    );
    return result ?? false;
  }
}

class _PinGateDialog extends StatefulWidget {
  final String mode; 
  const _PinGateDialog({required this.mode});

  @override
  State<_PinGateDialog> createState() => _PinGateDialogState();
}

class _PinGateDialogState extends State<_PinGateDialog>
    with SingleTickerProviderStateMixin {
  String _pin = '';
  String _error = '';
  late AnimationController _shakeCtrl;
  late Animation<double> _shakeAnim;

  AppL10n get _l => context.read<LanguageProvider>().l10n;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _shakeAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _shakeCtrl, curve: Curves.elasticOut),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _addDigit(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = '';
    });
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _verify);
    }
  }

  void _removeDigit() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _verify() {
    HapticFeedback.lightImpact();
    if (ParentalControl.verify(_pin)) {
      Navigator.of(context).pop(true);
    } else {
      _shakeCtrl.forward(from: 0);
      setState(() {
        _error = _l.t('parental_wrong_pin');
        _pin = '';
      });
      HapticFeedback.heavyImpact();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;
    final l = _l;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 80 : 32,
        vertical: isLandscape ? 16 : 60,
      ),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: 360,
          maxHeight: isLandscape ? 320 : 520,
        ),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.violet.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: AppTheme.violet.withOpacity(0.15), blurRadius: 40),
            const BoxShadow(color: Colors.black54, blurRadius: 20),
          ],
        ),
        child: isLandscape ? _buildLandscape(l) : _buildPortrait(l),
      ),
    );
  }

  Widget _buildPortrait(AppL10n l) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildHeader(l),
          const SizedBox(height: 28),
          _buildDots(),
          const SizedBox(height: 8),
          _buildErrorText(),
          const SizedBox(height: 24),
          _buildKeypad(),
          const SizedBox(height: 16),
          _buildCancelBtn(l),
        ],
      ),
    );
  }

  Widget _buildLandscape(AppL10n l) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildHeader(l),
                const SizedBox(height: 20),
                _buildDots(),
                const SizedBox(height: 8),
                _buildErrorText(),
                const SizedBox(height: 12),
                _buildCancelBtn(l),
              ],
            ),
          ),
          const SizedBox(width: 20),
          Expanded(flex: 5, child: _buildKeypad()),
        ],
      ),
    );
  }

  Widget _buildHeader(AppL10n l) {
    return Column(
      children: [
        Container(
          width: 52, height: 52,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: AppTheme.violet.withOpacity(0.4), blurRadius: 16)],
          ),
          child: const Icon(Icons.lock_rounded, color: Colors.white, size: 24),
        ),
        const SizedBox(height: 14),
        Text(
          l.t('parental_lock_title'),
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l.t('parental_enter_pin'),
          style: GoogleFonts.poppins(
            color: AppTheme.textSecondary,
            fontSize: 13,
          ),
        ),
      ],
    );
  }

  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _shakeAnim,
      builder: (_, child) {
        final shake = (_shakeAnim.value * 12 * (1 - _shakeAnim.value)).toInt().toDouble();
        return Transform.translate(
          offset: Offset(shake * (_shakeCtrl.status == AnimationStatus.forward ? 1 : -1), 0),
          child: child,
        );
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = i < _pin.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? AppTheme.violet : Colors.transparent,
              border: Border.all(
                color: filled ? AppTheme.violet : Colors.white38,
                width: 2,
              ),
              boxShadow: filled
                  ? [BoxShadow(color: AppTheme.violet.withOpacity(0.5), blurRadius: 8)]
                  : [],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildErrorText() {
    return SizedBox(
      height: 18,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: _error.isNotEmpty
            ? Text(
                _error,
                key: ValueKey(_error),
                style: GoogleFonts.poppins(
                  color: AppTheme.error,
                  fontSize: 12,
                ),
              )
            : const SizedBox.shrink(),
      ),
    );
  }

  Widget _buildKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keys.map((row) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: row.map((k) {
            if (k.isEmpty) return const SizedBox(width: 72, height: 56);
            return _KeypadButton(
              label: k,
              isDelete: k == '⌫',
              onTap: () => k == '⌫' ? _removeDigit() : _addDigit(k),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildCancelBtn(AppL10n l) {
    return TextButton(
      onPressed: () => Navigator.of(context).pop(false),
      child: Text(
        l.t('cancel'),
        style: GoogleFonts.poppins(color: AppTheme.textMuted, fontSize: 13),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Bouton du pavé numérique
// ─────────────────────────────────────────────────────────────────────────────

class _KeypadButton extends StatefulWidget {
  final String label;
  final bool isDelete;
  final VoidCallback onTap;

  const _KeypadButton({
    required this.label,
    required this.onTap,
    this.isDelete = false,
  });

  @override
  State<_KeypadButton> createState() => _KeypadButtonState();
}

class _KeypadButtonState extends State<_KeypadButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
        HapticFeedback.selectionClick();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        width: 72,
        height: 56,
        margin: const EdgeInsets.all(5),
        decoration: BoxDecoration(
          color: _pressed
              ? AppTheme.violet.withOpacity(0.3)
              : Colors.white.withOpacity(0.07),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: _pressed
                ? AppTheme.violet.withOpacity(0.6)
                : Colors.white.withOpacity(0.08),
          ),
          boxShadow: _pressed
              ? [BoxShadow(color: AppTheme.violet.withOpacity(0.2), blurRadius: 8)]
              : [],
        ),
        child: Center(
          child: widget.isDelete
              ? const Icon(Icons.backspace_outlined, color: Colors.white70, size: 20)
              : Text(
                  widget.label,
                  style: GoogleFonts.poppins(
                    color: Colors.white,
                    fontSize: 22,
                    fontWeight: FontWeight.w500,
                  ),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Dialog création/modification PIN (avec confirmation)
// ─────────────────────────────────────────────────────────────────────────────

class PinSetupDialog extends StatefulWidget {
  /// Si true : on est en mode "modifier" (vérifier l'ancien PIN d'abord)
  final bool isEdit;
  const PinSetupDialog({super.key, this.isEdit = false});

  @override
  State<PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<PinSetupDialog>
    with SingleTickerProviderStateMixin {
  // Étapes: 'enter' (nouveau) → 'confirm' (re-saisir)
  String _step = 'enter';
  String _firstPin = '';
  String _pin = '';
  String _error = '';
  late AnimationController _shakeCtrl;

  AppL10n get _l => context.read<LanguageProvider>().l10n;

  @override
  void initState() {
    super.initState();
    _shakeCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
  }

  @override
  void dispose() {
    _shakeCtrl.dispose();
    super.dispose();
  }

  void _addDigit(String d) {
    if (_pin.length >= 4) return;
    setState(() {
      _pin += d;
      _error = '';
    });
    if (_pin.length == 4) {
      Future.delayed(const Duration(milliseconds: 150), _next);
    }
  }

  void _removeDigit() {
    if (_pin.isEmpty) return;
    setState(() => _pin = _pin.substring(0, _pin.length - 1));
  }

  void _next() {
    if (_step == 'enter') {
      setState(() {
        _firstPin = _pin;
        _pin = '';
        _step = 'confirm';
      });
    } else {
      if (_pin == _firstPin) {
        Navigator.of(context).pop(_pin);
      } else {
        _shakeCtrl.forward(from: 0);
        setState(() {
          _error = _l.t('parental_pin_mismatch');
          _pin = '';
          _step = 'enter';
          _firstPin = '';
        });
        HapticFeedback.heavyImpact();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = _l;
    final isLandscape = MediaQuery.of(context).orientation == Orientation.landscape;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isLandscape ? 80 : 32,
        vertical: isLandscape ? 16 : 60,
      ),
      child: Container(
        constraints: BoxConstraints(maxWidth: 360, maxHeight: isLandscape ? 320 : 520),
        decoration: BoxDecoration(
          color: const Color(0xFF0F0F1A),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: AppTheme.violet.withOpacity(0.3)),
          boxShadow: [
            BoxShadow(color: AppTheme.violet.withOpacity(0.15), blurRadius: 40),
            const BoxShadow(color: Colors.black54, blurRadius: 20),
          ],
        ),
        child: Padding(
          padding: EdgeInsets.all(isLandscape ? 20 : 28),
          child: isLandscape ? _buildLandscape(l) : _buildPortrait(l),
        ),
      ),
    );
  }

  Widget _buildPortrait(AppL10n l) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHeader(l),
        const SizedBox(height: 28),
        _buildDots(),
        const SizedBox(height: 8),
        _buildError(),
        const SizedBox(height: 24),
        _buildKeypad(),
        const SizedBox(height: 16),
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(l.t('cancel'),
              style: GoogleFonts.poppins(color: AppTheme.textMuted, fontSize: 13)),
        ),
      ],
    );
  }

  Widget _buildLandscape(AppL10n l) {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildHeader(l),
              const SizedBox(height: 20),
              _buildDots(),
              const SizedBox(height: 8),
              _buildError(),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(context).pop(null),
                child: Text(l.t('cancel'),
                    style: GoogleFonts.poppins(color: AppTheme.textMuted, fontSize: 13)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(flex: 5, child: _buildKeypad()),
      ],
    );
  }

  Widget _buildHeader(AppL10n l) {
    final title = _step == 'enter'
        ? l.t(widget.isEdit ? 'settings_pin_edit' : 'settings_pin_title')
        : l.t('parental_pin_confirm');
    return Column(
      children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            gradient: AppTheme.gradientPrimary,
            shape: BoxShape.circle,
          ),
          child: Icon(
            _step == 'enter' ? Icons.lock_outline_rounded : Icons.lock_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(height: 12),
        Text(title,
            style: GoogleFonts.poppins(
                color: Colors.white, fontSize: 17, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        // Indicateur d'étape
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepDot(active: _step == 'enter', done: _step == 'confirm'),
            const SizedBox(width: 6),
            _StepDot(active: _step == 'confirm', done: false),
          ],
        ),
      ],
    );
  }

  Widget _buildDots() {
    return AnimatedBuilder(
      animation: _shakeCtrl,
      builder: (_, child) {
        final t = _shakeCtrl.value;
        final shake = (t * 10 * (1 - t) * 2).toDouble();
        return Transform.translate(offset: Offset(shake, 0), child: child);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(4, (i) {
          final filled = i < _pin.length;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.symmetric(horizontal: 8),
            width: 16, height: 16,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: filled ? AppTheme.violet : Colors.transparent,
              border: Border.all(
                color: filled ? AppTheme.violet : Colors.white38, width: 2),
              boxShadow: filled
                  ? [BoxShadow(color: AppTheme.violet.withOpacity(0.5), blurRadius: 8)]
                  : [],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildError() {
    return SizedBox(
      height: 18,
      child: _error.isNotEmpty
          ? Text(_error,
              style: GoogleFonts.poppins(color: AppTheme.error, fontSize: 12))
          : null,
    );
  }

  Widget _buildKeypad() {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keys.map((row) => Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: row.map((k) {
          if (k.isEmpty) return const SizedBox(width: 72, height: 56);
          return _KeypadButton(
            label: k,
            isDelete: k == '⌫',
            onTap: () => k == '⌫' ? _removeDigit() : _addDigit(k),
          );
        }).toList(),
      )).toList(),
    );
  }
}

class _StepDot extends StatelessWidget {
  final bool active;
  final bool done;
  const _StepDot({required this.active, required this.done});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: done
            ? AppTheme.violet
            : active
                ? AppTheme.violet
                : Colors.white24,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}