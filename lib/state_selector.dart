/// Rebuilds a widget only when a selected value from a Listenable changes.
library;

import 'package:flutter/widgets.dart';

class StateSelector<T> extends StatefulWidget {
  const StateSelector({
    super.key,
    required this.listenable,
    required this.select,
    required this.builder,
  });

  final Listenable listenable;
  final T Function() select;
  final Widget Function(BuildContext context, T value) builder;

  @override
  State<StateSelector<T>> createState() => _StateSelectorState<T>();
}

class _StateSelectorState<T> extends State<StateSelector<T>> {
  late T _value;

  @override
  void initState() {
    super.initState();
    _value = widget.select();
    widget.listenable.addListener(_handleChange);
  }

  @override
  void didUpdateWidget(StateSelector<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listenable != widget.listenable) {
      oldWidget.listenable.removeListener(_handleChange);
      widget.listenable.addListener(_handleChange);
    }
    _value = widget.select();
  }

  void _handleChange() {
    final next = widget.select();
    if (next == _value) return;
    setState(() => _value = next);
  }

  @override
  void dispose() {
    widget.listenable.removeListener(_handleChange);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _value);
}
