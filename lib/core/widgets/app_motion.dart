import 'package:flutter/material.dart';

/// Shared motion vocabulary for the app.
///
/// The surfaces animated with these helpers carry safety information, so motion
/// is deliberately short and always settles on its own: nothing here loops
/// forever, which keeps widget tests deterministic (`pumpAndSettle` returns)
/// and leaves no running tickers behind.
///
/// When the platform reports `MediaQueryData.disableAnimations` every helper
/// jumps straight to its final value.
abstract final class AppMotion {
  /// Small state changes: icon swaps, count changes, colour tints.
  static const Duration quick = Duration(milliseconds: 180);

  /// Default entrance duration for a single block of content.
  static const Duration standard = Duration(milliseconds: 320);

  /// Roomier entrance for hero content such as the temperature reading.
  static const Duration relaxed = Duration(milliseconds: 480);

  /// Delay added per item in a staggered group.
  static const Duration stagger = Duration(milliseconds: 55);

  /// Ceiling for stagger delays so long lists never crawl into view.
  static const Duration maxStagger = Duration(milliseconds: 320);

  /// Standard deceleration for entrances.
  static const Curve enter = Curves.easeOutCubic;

  /// Slight overshoot, used for "pop" emphasis on changing values.
  static const Curve pop = Curves.easeOutBack;

  /// Delay for the [index]-th item of a staggered group, capped at
  /// [maxStagger].
  static Duration staggerFor(int index) {
    if (index <= 0) return Duration.zero;
    final delay = stagger * index;
    return delay > maxStagger ? maxStagger : delay;
  }

  /// Whether the user asked for reduced motion on this platform.
  static bool isReducedMotion(BuildContext context) =>
      MediaQuery.maybeOf(context)?.disableAnimations ?? false;
}

/// Fades, slides and (optionally) scales [child] into place once.
///
/// Stagger a group of blocks by passing an increasing [delay] (see
/// [AppMotion.staggerFor]). The animation is one-shot: it does not replay when
/// the parent rebuilds, it only runs on the first build of this element.
class AnimatedEntrance extends StatefulWidget {
  const AnimatedEntrance({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.duration = AppMotion.standard,
    this.beginOffset = const Offset(0, 0.08),
    this.beginScale = 1.0,
    this.curve = AppMotion.enter,
  });

  final Widget child;

  /// Hold time before the entrance starts.
  final Duration delay;

  /// Length of the entrance itself, excluding [delay].
  final Duration duration;

  /// Where the block starts from, as a fraction of its own size.
  final Offset beginOffset;

  /// Starting scale. Values below 1 grow into place.
  final double beginScale;

  final Curve curve;

  @override
  State<AnimatedEntrance> createState() => _AnimatedEntranceState();
}

class _AnimatedEntranceState extends State<AnimatedEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  CurvedAnimation? _progress;
  late Animation<double> _opacity;
  late Animation<Offset> _position;
  late Animation<double> _scale;
  bool _honouredReducedMotion = false;

  Duration get _total => widget.delay + widget.duration;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: _total);
    _bindCurves();
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_honouredReducedMotion || !AppMotion.isReducedMotion(context)) return;
    _honouredReducedMotion = true;
    _controller.value = 1;
  }

  @override
  void didUpdateWidget(AnimatedEntrance oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay == widget.delay &&
        oldWidget.duration == widget.duration &&
        oldWidget.beginOffset == widget.beginOffset &&
        oldWidget.beginScale == widget.beginScale &&
        oldWidget.curve == widget.curve) {
      return;
    }
    _controller.duration = _total;
    _bindCurves();
    _controller.forward(from: 0);
  }

  @override
  void dispose() {
    _progress?.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _bindCurves() {
    final totalMicros = _total.inMicroseconds;
    // A zero-length slot has nothing to animate; land on the final frame.
    final start = totalMicros <= 0
        ? 1.0
        : (widget.delay.inMicroseconds / totalMicros).clamp(0.0, 1.0);
    _progress?.dispose();
    final progress = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, 1.0, curve: widget.curve),
    );
    _progress = progress;
    _opacity = progress;
    _position = Tween<Offset>(
      begin: widget.beginOffset,
      end: Offset.zero,
    ).animate(progress);
    _scale = Tween<double>(begin: widget.beginScale, end: 1).animate(progress);
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _position,
        child: widget.beginScale == 1.0
            ? widget.child
            : ScaleTransition(scale: _scale, child: widget.child),
      ),
    );
  }
}

/// Cross-fades between [child] values as [key] changes.
///
/// Pair it with an [AnimatedSwitcher]-style [key] (for example the value being
/// displayed) so a changed reading eases into place instead of snapping.
class AnimatedNumber extends StatelessWidget {
  const AnimatedNumber({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = AppMotion.relaxed,
    this.curve = AppMotion.enter,
    this.begin,
    this.textAlign,
  });

  /// Target value. Animated from the previously displayed value.
  final double value;

  /// Renders the (possibly fractional) animated value.
  final String Function(double value) format;

  final TextStyle? style;

  final Duration duration;

  final Curve curve;

  /// Starting value for the very first build. Defaults to [value], so a reading
  /// appears immediately and only later changes are tweened.
  final double? begin;

  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) {
      return Text(format(value), style: style, textAlign: textAlign);
    }
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: begin, end: value),
      duration: duration,
      curve: curve,
      builder: (context, animated, _) =>
          Text(format(animated), style: style, textAlign: textAlign),
    );
  }
}

/// Scales [child] down slightly while it is held, for tactile card feedback.
///
/// Uses a [Listener] rather than a gesture recogniser so it never competes with
/// the interactive widgets inside (buttons, ink wells, list tiles).
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.pressedScale = 0.975,
  });

  final Widget child;

  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => setState(() => _pressed = true),
      onPointerUp: (_) => setState(() => _pressed = false),
      onPointerCancel: (_) => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1.0,
        duration: AppMotion.quick,
        curve: AppMotion.enter,
        child: widget.child,
      ),
    );
  }
}

/// Replays a one-shot scale pop whenever [child] is rebuilt with a new [key].
///
/// Used where a value changes and should draw the eye (active alert count,
/// risk level) without introducing a permanently running animation.
class PopOnChange extends StatelessWidget {
  const PopOnChange({
    super.key,
    required this.identity,
    required this.child,
    this.beginScale = 0.88,
    this.duration = AppMotion.relaxed,
  });

  /// Changing this value restarts the pop.
  final Object identity;

  final Widget child;

  final double beginScale;

  final Duration duration;

  @override
  Widget build(BuildContext context) {
    if (AppMotion.isReducedMotion(context)) return child;
    return TweenAnimationBuilder<double>(
      key: ValueKey(identity),
      tween: Tween<double>(begin: beginScale, end: 1),
      duration: duration,
      curve: AppMotion.pop,
      builder: (context, scale, child) =>
          Transform.scale(scale: scale, child: child),
      child: child,
    );
  }
}