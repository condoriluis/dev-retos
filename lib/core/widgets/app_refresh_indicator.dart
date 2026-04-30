import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

class AppRefreshIndicator extends StatelessWidget {
  final Future<void> Function() onRefresh;
  final Widget? child;
  final List<Widget>? slivers;

  const AppRefreshIndicator({
    super.key,
    required this.onRefresh,
    this.child,
    this.slivers,
  }) : assert(
         child != null || slivers != null,
         'Debe proporcionar un child o slivers',
       );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return CustomScrollView(
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      slivers: [
        CupertinoSliverRefreshControl(
          onRefresh: onRefresh,
          builder:
              (
                context,
                refreshState,
                pulledExtent,
                refreshTriggerPullDistance,
                refreshIndicatorExtent,
              ) {
                final double percentage =
                    (pulledExtent / refreshTriggerPullDistance).clamp(0.0, 1.0);

                return Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: List.generate(3, (index) {
                      return _AnimatedDot(
                        index: index,
                        percentage: percentage,
                        isRefreshing:
                            refreshState == RefreshIndicatorMode.refresh,
                        color: Color.lerp(
                          theme.colorScheme.primary,
                          theme.colorScheme.secondary,
                          index / 2,
                        )!,
                      );
                    }),
                  ),
                );
              },
        ),
        if (slivers != null) ...slivers!,
        if (child != null) SliverToBoxAdapter(child: child),
      ],
    );
  }
}

class _AnimatedDot extends StatefulWidget {
  final int index;
  final double percentage;
  final bool isRefreshing;
  final Color color;

  const _AnimatedDot({
    required this.index,
    required this.percentage,
    required this.isRefreshing,
    required this.color,
  });

  @override
  State<_AnimatedDot> createState() => _AnimatedDotState();
}

class _AnimatedDotState extends State<_AnimatedDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    if (widget.isRefreshing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(_AnimatedDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isRefreshing && !oldWidget.isRefreshing) {
      _controller.repeat(reverse: true);
    } else if (!widget.isRefreshing && oldWidget.isRefreshing) {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        double val = 0.0;
        if (widget.isRefreshing) {
          double delay = widget.index * 0.2;
          double animVal = (_controller.value + delay) % 1.0;
          val = (animVal < 0.5) ? (animVal * 2) : (2 - animVal * 2);
        } else {
          val = (widget.percentage * 1.5 - (widget.index * 0.2)).clamp(
            0.0,
            1.0,
          );
        }

        return Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 7 + (val * 5),
          height: 7 + (val * 5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.color.withOpacity(0.3 + (val * 0.7)),
            boxShadow: [
              if (val > 0.8)
                BoxShadow(
                  color: widget.color.withOpacity(0.4),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
            ],
          ),
        );
      },
    );
  }
}
