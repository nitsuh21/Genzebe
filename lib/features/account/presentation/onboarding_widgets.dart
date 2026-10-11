import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:genzeb/design_system/theme.dart';

/// The first-run pages share one look: the icon's deep indigo edge to edge,
/// white type, and the coin's gold for accents. Same in light and dark mode.
class OnboardingPage extends StatelessWidget {
  const OnboardingPage({
    super.key,
    required this.picture,
    required this.title,
    required this.body,
    required this.actions,
    this.topBar,
    this.fitPicture = true,
  });

  /// Drawn at its natural size and scaled down to the room left above the
  /// words; it must not depend on incoming constraints.
  final Widget picture;

  /// False hands [picture] the room above the words as-is, for a list that
  /// scrolls instead of shrinking.
  final bool fitPicture;
  final String title;
  final String body;
  final Widget actions;
  final Widget? topBar;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: systemOverlayStyleFor(Brightness.dark),
      child: Scaffold(
        backgroundColor: kBrandIndigoDeep,
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final words = <Widget>[
                const SizedBox(height: 24),
                Text(
                  title,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.12,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  body,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.72),
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 28),
                actions,
              ];
              final art = fitPicture
                  ? FittedBox(fit: BoxFit.scaleDown, child: picture)
                  : picture;
              const padding = EdgeInsets.fromLTRB(24, 0, 24, 16);
              // Tall screens: the picture takes whatever the words leave.
              // Short ones (or very large text): a fixed picture and scroll.
              if (box.maxHeight >= 620) {
                return Padding(
                  padding: padding,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 56, child: topBar),
                      Expanded(child: Center(child: art)),
                      ...words,
                    ],
                  ),
                );
              }
              return SingleChildScrollView(
                padding: padding,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: 56, child: topBar),
                    SizedBox(height: 220, child: Center(child: art)),
                    ...words,
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// White, full-width, indigo label: the one thing to press on the page.
class OnboardingButton extends StatelessWidget {
  const OnboardingButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.busy = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: busy ? null : onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: kBrandIndigoDeep,
          disabledBackgroundColor: Colors.white.withValues(alpha: 0.7),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        child: busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.4,
                  color: kBrandIndigoDeep,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
      ),
    );
  }
}

/// Quiet text action on the indigo pages.
class OnboardingTextButton extends StatelessWidget {
  const OnboardingTextButton({
    super.key,
    required this.label,
    required this.onPressed,
  });

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
      ),
      child: Text(label),
    );
  }
}

/// Runs an entrance once, a beat after the first frame; jumps straight to
/// the end when the system asks for reduced motion.
mixin OnboardingEntrance<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  late final AnimationController entrance = AnimationController(
    vsync: this,
    duration: entranceDuration,
  );
  bool _entranceStarted = false;

  Duration get entranceDuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      entrance.value = 1;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(const Duration(milliseconds: 250), () {
        if (mounted) entrance.forward();
      });
    });
  }

  @override
  void dispose() {
    entrance.dispose();
    super.dispose();
  }

  /// [entrance] reshaped to run between [begin] and [end] (0..1).
  Animation<double> phase(double begin, double end,
          {Curve curve = Curves.easeOutCubic}) =>
      CurvedAnimation(
        parent: entrance,
        curve: Interval(begin, end, curve: curve),
      );
}
