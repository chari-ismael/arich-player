import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class TvBackHandler extends StatelessWidget {
  final Widget child;
  final VoidCallback? onBack;

  const TvBackHandler({super.key, required this.child, this.onBack});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _handleBack(context),
        const SingleActivator(LogicalKeyboardKey.goBack): () => _handleBack(context),
      },
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.goBack) {
            _handleBack(context);
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: child,
      ),
    );
  }

  void _handleBack(BuildContext context) {
    if (onBack != null) {
      onBack!();
    } else {
      Navigator.of(context).maybePop();
    }
  }
}