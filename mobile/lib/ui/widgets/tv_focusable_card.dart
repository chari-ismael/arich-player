// lib/ui/widgets/tv_focusable_card.dart
//
// Arich Player — TvFocusableCard v2
//
// Améliorations v2 :
// [1] borderRadius paramétrable (défaut 15)
// [2] borderColor paramétrable (défaut AppTheme.violet)
// [3] autofocus support
// [4] onLongPress support
// [5] glowIntensity paramétrable selon le contexte
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/theme.dart';

class TvFocusableCard extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final double? width;
  final double? height;
  final double borderRadius;
  final Color? borderColor;
  final double glowIntensity;
  final bool autofocus;

  const TvFocusableCard({
    super.key,
    required this.child,
    required this.onTap,
    this.onLongPress,
    this.width,
    this.height,
    this.borderRadius = 15,
    this.borderColor,
    this.glowIntensity = 0.55,
    this.autofocus = false,
  });

  @override
  State<TvFocusableCard> createState() => _TvFocusableCardState();
}

class _TvFocusableCardState extends State<TvFocusableCard> {
  bool _isFocused = false;
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    final glowColor = widget.borderColor ?? AppTheme.violet;
    final innerRadius = (widget.borderRadius - 2).clamp(0.0, double.infinity);

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (hasFocus) {
        if (!mounted) return;
        setState(() => _isFocused = hasFocus);
        // Auto-scroll vers la card quand elle reçoit le focus via D-pad
        if (hasFocus) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            Scrollable.ensureVisible(
              context,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: 0.3,
            );
          });
        }
      },
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          setState(() => _isPressed = true);
          widget.onTap();
          return KeyEventResult.handled;
        }
        if (event is KeyUpEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
                event.logicalKey == LogicalKeyboardKey.enter)) {
          setState(() => _isPressed = false);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapUp: (_) => setState(() => _isPressed = false),
        onTapCancel: () => setState(() => _isPressed = false),
        onTap: widget.onTap,
        onLongPress: widget.onLongPress,
        child: AnimatedScale(
          scale: _isPressed ? 0.94 : (_isFocused ? 1.04 : 1.0),
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOutCubic,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: widget.width,
            height: widget.height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              boxShadow: [
                if (_isFocused)
                  BoxShadow(
                    color: glowColor.withOpacity(widget.glowIntensity),
                    blurRadius: 22,
                    spreadRadius: 2,
                    offset: const Offset(0, 4),
                  )
                else
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
              ],
              border: Border.all(
                color: _isFocused
                    ? glowColor
                    : Colors.white.withOpacity(0.06),
                width: _isFocused ? 2.0 : 1.0,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}