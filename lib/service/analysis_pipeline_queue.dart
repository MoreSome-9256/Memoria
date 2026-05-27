import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../models/entity/photo_entity.dart';

class PipelineQueueItem {
  const PipelineQueueItem({
    required this.photoId,
    required this.photo,
    required this.enqueuedAt,
  });

  final int photoId;
  final PhotoEntity photo;
  final DateTime enqueuedAt;
}

class AnalysisPipelineQueue {
  AnalysisPipelineQueue({
    this.capacity = 50,
    this.highWaterMark = 40,
  });

  final int capacity;
  final int highWaterMark;

  final Queue<PipelineQueueItem> _queue = Queue<PipelineQueueItem>();
  final _enqueueCompleters = <Completer<void>>[];
  final _dequeueCompleters = <Completer<PipelineQueueItem?>>[];
  bool _closed = false;

  int get size => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  bool get isFull => _queue.length >= capacity;
  bool get isClosed => _closed;
  bool get isHighWater => _queue.length >= highWaterMark;

  Future<void> enqueue(PipelineQueueItem item) async {
    while (_queue.length >= capacity && !_closed) {
      final completer = Completer<void>();
      _enqueueCompleters.add(completer);
      await completer.future;
    }

    if (_closed) return;

    _queue.addLast(item);

    while (_dequeueCompleters.isNotEmpty) {
      final completer = _dequeueCompleters.removeAt(0);
      if (!completer.isCompleted) {
        completer.complete(_queue.removeFirst());
      }
    }
  }

  Future<PipelineQueueItem?> dequeue() async {
    if (_queue.isNotEmpty) {
      return _queue.removeFirst();
    }

    if (_closed) return null;

    final completer = Completer<PipelineQueueItem?>();
    _dequeueCompleters.add(completer);
    return completer.future;
  }

  void close() {
    _closed = true;

    for (final completer in _enqueueCompleters) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    }
    _enqueueCompleters.clear();

    for (final completer in _dequeueCompleters) {
      if (!completer.isCompleted) {
        completer.complete(null);
      }
    }
    _dequeueCompleters.clear();
  }

  void clear() {
    _queue.clear();
    close();
  }
}
