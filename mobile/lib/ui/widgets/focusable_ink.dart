// lib/ui/widgets/focusable_ink.dart
//
// Arich Player — FocusableInk v2
//
// Améliorations v2 :
// [1] Haptic feedback léger au tap (mobile)
// [2] withOpacity partout (cohérence avec le reste du codebase)
// [3] FocusableNavTab : indicateur actif gradient + animation scale
// [4] FocusableIconButton : padding adaptatif TV/mobile
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';
import '../../core/tv_layout.dart';

class FocusableInk extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool showFocusGlow;
  final double? borderRadius;
  final Color? focusColor;
  final bool autofocus;

  const FocusableInk({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.showFocusGlow = true,
    this.borderRadius,
    this.focusColor,
    this.autofocus = false,
  });

  @override
  State<FocusableInk> createState() => _FocusableInkState();
}

class _FocusableInkState extends State<FocusableInk>
    with SingleTickerProviderStateMixin {
  bool _isFocused = false;
  late final AnimationController _scaleCtrl;

  @override
  void initState() {
    super.initState();
    _scaleCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      reverseDuration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _scaleCtrl.dispose();
    super.dispose();
  }

  void _onFocusChange(bool focused) {
    if (!mounted) return;
    setState(() => _isFocused = focused);
    if (focused) {
      _scaleCtrl.forward();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.3,
        );
      });
    } else {
      _scaleCtrl.reverse();
    }
  }

  void _handleTap() {
    // [1] Haptic léger sur mobile
    HapticFeedback.lightImpact();
    widget.onTap?.call();
  }

  @override
  Widget build(BuildContext context) {
    final sizes = context.tvSizes;
    final glowColor = widget.focusColor ?? AppTheme.violet;
    final radius = widget.borderRadius ?? sizes.radiusButton;
    final scaleTarget = sizes.focusScale;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: _onFocusChange,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter ||
                event.logicalKey == LogicalKeyboardKey.space)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: AnimatedBuilder(
        animation: _scaleCtrl,
        builder: (context, child) {
          final scale = 1.0 + (scaleTarget - 1.0) * _scaleCtrl.value;
          return Transform.scale(scale: scale, child: child);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          decoration: widget.showFocusGlow && _isFocused
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  boxShadow: [
                    BoxShadow(
                      color: glowColor.withOpacity(0.55),
                      blurRadius: sizes.focusGlowBlur,
                      spreadRadius: sizes.focusGlowSpread,
                    ),
                  ],
                  border: Border.all(
                    color: glowColor.withOpacity(0.85),
                    width: sizes.focusBorderWidth,
                  ),
                )
              : BoxDecoration(borderRadius: BorderRadius.circular(radius)),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: widget.onTap != null ? _handleTap : null,
              onLongPress: widget.onLongPress,
              borderRadius: BorderRadius.circular(radius),
              splashColor: glowColor.withOpacity(0.15),
              highlightColor: glowColor.withOpacity(0.08),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FocusableIconButton
// ─────────────────────────────────────────────────────────────────────────────

class FocusableIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final double? size;
  final Color? color;
  final Color? focusColor;
  final bool autofocus;
  final EdgeInsets? padding;

  const FocusableIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.size,
    this.color,
    this.focusColor,
    this.autofocus = false,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final sizes = context.tvSizes;
    return FocusableInk(
      onTap: onTap,
      autofocus: autofocus,
      focusColor: focusColor,
      borderRadius: 100,
      child: Padding(
        padding: padding ?? EdgeInsets.all(sizes.isTV ? 10.0 : 6.0),
        child: Icon(icon, size: size ?? sizes.iconSize, color: color ?? Colors.white),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// FocusableNavTab — [3] indicateur actif gradient + scale
// ─────────────────────────────────────────────────────────────────────────────

class FocusableNavTab extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isActive;
  final VoidCallback onTap;
  final bool autofocus;

  const FocusableNavTab({
    super.key,
    required this.label,
    required this.icon,
    required this.isActive,
    required this.onTap,
    this.autofocus = false,
  });

  @override
  Widget build(BuildContext context) {
    final sizes = context.tvSizes;
    return FocusableInk(
      onTap: onTap,
      autofocus: autofocus,
      focusColor: AppTheme.violet,
      borderRadius: 100,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        padding: EdgeInsets.symmetric(
          horizontal: sizes.navTabHPad,
          vertical: sizes.navTabVPad,
        ),
        decoration: BoxDecoration(
          gradient: isActive
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    AppTheme.violet.withOpacity(0.22),
                    AppTheme.red.withOpacity(0.10),
                  ],
                )
              : null,
          color: isActive ? null : Colors.transparent,
          borderRadius: BorderRadius.circular(100),
          border: isActive
              ? Border.all(color: AppTheme.violet.withOpacity(0.35))
              : Border.all(color: Colors.transparent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: Icon(
                icon,
                key: ValueKey(isActive),
                size: sizes.isTV ? 20.0 : 16.0,
                color: isActive ? Colors.white : Colors.white38,
              ),
            ),
            SizedBox(width: sizes.isTV ? 10.0 : 6.0),
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 180),
              style: TextStyle(
                color: isActive ? Colors.white : Colors.white38,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                fontSize: sizes.fontNavTab,
              ),
              child: Text(label),
            ),
          ],
        ),
      ),
    );
  }
}