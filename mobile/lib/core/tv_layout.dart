// lib/core/tv_layout.dart
//
// Arich Player — TV Layout v2
//
// Nouveautés v2 :
//   • Détection Tizen TV (Samsung SmartTV)
//   • Résolutions adaptatives 1080p / 4K (2160p)
//   • TVSizes dynamiques selon vraie résolution écran
//   • Extension BuildContext.isTV / .tvSizes / .isTizen
//   • TvBackHandler — gestion bouton back D-pad TV

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── TVDetector ────────────────────────────────────────────────────────────────

class TVDetector {
  static final TVDetector _instance = TVDetector._();
  factory TVDetector() => _instance;
  TVDetector._();

  bool _isTV     = false;
  bool _isTizen  = false;
  bool _is4K     = false;
  bool _initialized = false;

  bool get isTV    => _isTV;
  bool get isTizen => _isTizen;
  bool get is4K    => _is4K;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      if (Platform.isAndroid) {
        await _detectAndroidTV();
      } else if (Platform.operatingSystem == 'tizen') {
        await _detectTizenTV();
      }
    } catch (e) {
      debugPrint('[TVDetector] init error: $e');
    }
  }

  static const _kLeanbackChannel = MethodChannel('arich.iptv/device');

  Future<void> _detectAndroidTV() async {
    try {
      final result = await _kLeanbackChannel.invokeMethod<bool>('isAndroidTV');
      _isTV = result ?? false;
    } catch (_) {
      _isTV = false;
    }
  }

  static const _kTizenChannel = MethodChannel('arich.iptv/tizen');

  Future<void> _detectTizenTV() async {
    _isTizen = true;
    _isTV    = true;

    try {
      final resolution = await _kTizenChannel.invokeMethod<String>('getDisplayResolution');
      if (resolution != null) {
        final parts = resolution.split('x');
        if (parts.length == 2) {
          final height = int.tryParse(parts[1]) ?? 0;
          _is4K = height >= 2160;
        }
      }
    } catch (_) {
      _is4K = false;
    }
  }

  void updateFromMediaQuery(MediaQueryData mq) {
    if (!_isTizen) return;
    final physicalH = mq.size.height * mq.devicePixelRatio;
    _is4K = physicalH >= 2160;
  }
}

// ── TVSizes — dimensions adaptées TV ────────────────────────────────────────

class TVSizes {
  final double screenWidth;
  final double screenHeight;
  final bool isTV;
  final bool is4K;
  final bool isTizen;

  const TVSizes({
    required this.screenWidth,
    required this.screenHeight,
    required this.isTV,
    required this.is4K,
    required this.isTizen,
  });

  // ── Sidebar ───────────────────────────────────────────────────────────────
  double get sidebarWidth       => is4K ? 300.0 : isTizen ? 240.0 : 220.0;

  // ── Navbar ────────────────────────────────────────────────────────────────
  double get navbarHeight       => is4K ? 90.0  : isTizen ? 72.0  : 64.0;

  // ── Cards ─────────────────────────────────────────────────────────────────
  double get cardHeightWide     => is4K ? 130.0 : isTizen ? 100.0 : 72.0;
  double get cardHeightPortrait => is4K ? 260.0 : isTizen ? 210.0 : 160.0;
  double get cardWidthPortrait  => cardHeightPortrait * 0.67;
  double get cardGap            => is4K ? 18.0  : isTizen ? 14.0  : 10.0;

  // ── Cards — propriétés utilisées par home_screen / category_grid / widgets ─
  double get cardHeightLive     => is4K ? 140.0 : isTizen ? 108.0 : 90.0;
  double get cardWidthLandscape => is4K ? 220.0 : isTizen ? 170.0 : 140.0;
  double get cardSpacing        => is4K ? 16.0  : isTizen ? 12.0  : 8.0;
  double get radiusCard         => is4K ? 16.0  : isTizen ? 12.0  : 8.0;

  // ── Body padding ──────────────────────────────────────────────────────────
  double get bodyPadding        => is4K ? 48.0  : isTizen ? 32.0  : 16.0;

  // ── Boutons ───────────────────────────────────────────────────────────────
  double get btnSize            => is4K ? 80.0  : isTizen ? 64.0  : 46.0;
  double get iconSize           => is4K ? 36.0  : isTizen ? 28.0  : 20.0;
  double get btnRadius          => is4K ? 20.0  : isTizen ? 16.0  : 12.0;
  double get radiusButton       => is4K ? 20.0  : isTizen ? 16.0  : 12.0;

  // ── Focus ring ────────────────────────────────────────────────────────────
  double get focusRingWidth     => isTizen ? 3.5  : 2.5;
  double get focusRingBlur      => isTizen ? 12.0 : 8.0;
  double get focusScale         => is4K ? 1.08  : isTizen ? 1.06  : 1.04;
  double get focusGlowBlur      => is4K ? 20.0  : isTizen ? 16.0  : 12.0;
  double get focusGlowSpread    => is4K ? 4.0   : isTizen ? 3.0   : 2.0;
  double get focusBorderWidth   => is4K ? 3.0   : isTizen ? 2.5   : 2.0;

  // ── Nav tabs ──────────────────────────────────────────────────────────────
  double get navTabHPad         => is4K ? 28.0  : isTizen ? 20.0  : 14.0;
  double get navTabVPad         => is4K ? 14.0  : isTizen ? 10.0  : 7.0;
  double get fontNavTab         => is4K ? 18.0  : isTizen ? 15.0  : 12.0;

  // ── Texte ─────────────────────────────────────────────────────────────────
  double get titleFontSize      => is4K ? 36.0  : isTizen ? 28.0  : 24.0;
  double get subtitleFontSize   => is4K ? 22.0  : isTizen ? 18.0  : 14.0;
  double get bodyFontSize       => is4K ? 18.0  : isTizen ? 15.0  : 12.0;
  double get labelFontSize      => is4K ? 14.0  : isTizen ? 12.0  : 10.0;

  // ── Player controls ───────────────────────────────────────────────────────
  double get playerBtnSize      => is4K ? 100.0 : isTizen ? 80.0  : 64.0;
  double get playerIconSize     => is4K ? 48.0  : isTizen ? 38.0  : 28.0;
  double get seekBtnSize        => is4K ? 80.0  : isTizen ? 64.0  : 48.0;
  double get seekIconSize       => is4K ? 42.0  : isTizen ? 34.0  : 26.0;
  double get sliderThumbRadius  => is4K ? 12.0  : isTizen ? 10.0  : 6.0;
  double get sliderTrackHeight  => is4K ? 5.0   : isTizen ? 4.0   : 2.5;

  // ── Padding global ────────────────────────────────────────────────────────
  EdgeInsets get screenPadding => is4K
      ? const EdgeInsets.all(40)
      : isTizen
          ? const EdgeInsets.all(28)
          : const EdgeInsets.all(16);

  EdgeInsets get contentPadding => is4K
      ? const EdgeInsets.symmetric(horizontal: 48, vertical: 24)
      : isTizen
          ? const EdgeInsets.symmetric(horizontal: 32, vertical: 18)
          : const EdgeInsets.symmetric(horizontal: 18, vertical: 12);

  // ── Carousel / Hero ───────────────────────────────────────────────────────
  double get carouselHeight     => is4K ? 400.0 : isTizen ? 300.0 : 260.0;
  double get heroSectionHeight  => is4K ? 360.0 : isTizen ? 280.0 : 240.0;
}

// ── Extension BuildContext ────────────────────────────────────────────────────

extension TVLayoutContext on BuildContext {
  bool get isTV    => TVDetector().isTV;
  bool get isTizen => TVDetector().isTizen;
  bool get is4K    => TVDetector().is4K;

  TVSizes get tvSizes {
    final mq  = MediaQuery.of(this);
    final det = TVDetector();
    return TVSizes(
      screenWidth:  mq.size.width,
      screenHeight: mq.size.height,
      isTV:         det.isTV,
      is4K:         det.is4K,
      isTizen:      det.isTizen,
    );
  }
}

// ── TvBackHandler — intercepte le bouton Back TV (D-pad / telecommande) ──────

class TvBackHandler extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;

  const TvBackHandler({
    super.key,
    required this.child,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent) return KeyEventResult.ignored;
        if (event.logicalKey == LogicalKeyboardKey.escape ||
            event.logicalKey == LogicalKeyboardKey.goBack ||
            event.logicalKey == LogicalKeyboardKey.browserBack) {
          if (onBack != null) {
            onBack!();
          } else {
            Navigator.maybePop(context);
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }
}

// ── TvFocusZone — zone de focus D-Pad ────────────────────────────────────────

class TvFocusZone extends StatelessWidget {
  final Widget child;
  final int order;
  const TvFocusZone({super.key, required this.child, required this.order});

  @override
  Widget build(BuildContext context) {
    return FocusTraversalOrder(
      order: NumericFocusOrder(order.toDouble()),
      child: child,
    );
  }
}

// ── FocusableTV — bouton avec highlight focus TV ──────────────────────────────

class FocusableTV extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool autofocus;
  final Color focusColor;
  final double borderRadius;
  final EdgeInsets? padding;

  const FocusableTV({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.autofocus = false,
    this.focusColor = const Color(0xFF7B2FFF),
    this.borderRadius = 12.0,
    this.padding,
  });

  @override
  State<FocusableTV> createState() => _FocusableTVState();
}

class _FocusableTVState extends State<FocusableTV> {
  bool _focused = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final isTizen  = context.isTizen;
    final sizes    = context.tvSizes;
    final hasFocus = _focused || _hovered;

    return Focus(
      autofocus: widget.autofocus,
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            (event.logicalKey == LogicalKeyboardKey.select ||
             event.logicalKey == LogicalKeyboardKey.enter)) {
          widget.onTap?.call();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit:  (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: widget.padding,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              border: hasFocus
                  ? Border.all(
                      color: widget.focusColor,
                      width: isTizen ? sizes.focusRingWidth : 2.0,
                    )
                  : Border.all(color: Colors.transparent),
              boxShadow: hasFocus
                  ? [
                      BoxShadow(
                        color: widget.focusColor.withOpacity(0.45),
                        blurRadius: isTizen ? sizes.focusRingBlur : 8.0,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

bool get isAnyTV => TVDetector().isTV;

double tvFontSize(BuildContext ctx, {
  required double mobile,
  double? tizen1080,
  double? tizen4K,
}) {
  final det = TVDetector();
  if (!det.isTV) return mobile;
  if (det.is4K)    return tizen4K    ?? mobile * 1.8;
  if (det.isTizen) return tizen1080  ?? mobile * 1.4;
  return mobile * 1.2;
}

EdgeInsets tvPadding(BuildContext ctx, EdgeInsets mobile) {
  final sizes = ctx.tvSizes;
  if (!sizes.isTV) return mobile;
  return EdgeInsets.only(
    left:   mobile.left   * (sizes.is4K ? 2.5 : sizes.isTizen ? 2.0 : 1.5),
    right:  mobile.right  * (sizes.is4K ? 2.5 : sizes.isTizen ? 2.0 : 1.5),
    top:    mobile.top    * (sizes.is4K ? 1.8 : sizes.isTizen ? 1.5 : 1.2),
    bottom: mobile.bottom * (sizes.is4K ? 1.8 : sizes.isTizen ? 1.5 : 1.2),
  );
}