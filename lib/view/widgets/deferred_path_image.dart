/// 延迟加载路径图片组件，适合在列表或相册中按需解码。

import 'dart:async';
import 'dart:collection';
import 'package:flutter/widget_previews.dart';
import 'package:flutter/material.dart';

import 'path_image.dart';

class DeferredPathImage extends StatefulWidget {
  const DeferredPathImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
  });

  final String path;
  final BoxFit fit;

  @override
  State<DeferredPathImage> createState() => _DeferredPathImageState();
}

class _DeferredPathImageState extends State<DeferredPathImage> {
  final _DeferredImageTicket _ticket = _DeferredImageTicket();
  bool _ready = false;
  bool _firstFrameReported = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _DeferredImageLoadScheduler.enqueue(_ticket, _startDeferredLoad);
  }

  void _startDeferredLoad() {
    final delayMs = 30 + (widget.path.hashCode.abs() % 11) * 28;
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (!mounted || _ticket.completed) {
        return;
      }
      setState(() {
        _ready = true;
      });
    });
  }

  void _onFirstFrame() {
    if (_firstFrameReported) {
      return;
    }
    _firstFrameReported = true;
    _DeferredImageLoadScheduler.complete(_ticket);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _DeferredImageLoadScheduler.complete(_ticket);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_ready) {
      return PathImage(
        path: widget.path,
        fit: widget.fit,
        onFirstFrame: _onFirstFrame,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(color: Colors.grey.shade200),
      child: const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      ),
    );
  }
}

class _DeferredImageTicket {
  bool started = false;
  bool completed = false;
}

class _DeferredImageLoadScheduler {
  static const int _maxConcurrent = 4;
  static final Queue<(_DeferredImageTicket, VoidCallback)> _queue =
      Queue<(_DeferredImageTicket, VoidCallback)>();
  static int _active = 0;

  static void enqueue(_DeferredImageTicket ticket, VoidCallback starter) {
    if (ticket.completed) {
      return;
    }
    _queue.add((ticket, starter));
    _pump();
  }

  static void complete(_DeferredImageTicket ticket) {
    if (ticket.completed) {
      return;
    }
    ticket.completed = true;

    if (ticket.started && _active > 0) {
      _active -= 1;
    } else {
      _queue.removeWhere((entry) => identical(entry.$1, ticket));
    }

    _pump();
  }

  static void _pump() {
    while (_active < _maxConcurrent && _queue.isNotEmpty) {
      final (ticket, starter) = _queue.removeFirst();
      if (ticket.completed) {
        continue;
      }
      ticket.started = true;
      _active += 1;
      starter();
    }
  }
}

