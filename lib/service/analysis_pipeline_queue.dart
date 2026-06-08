import 'dart:async';
import 'dart:collection';

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
  AnalysisPipelineQueue();

  final Queue<PipelineQueueItem> _queue = Queue<PipelineQueueItem>();
  final _dequeueCompleters = <Completer<PipelineQueueItem?>>[];
  bool _closed = false;

  int get size => _queue.length;
  bool get isEmpty => _queue.isEmpty;
  bool get isNotEmpty => _queue.isNotEmpty;
  bool get isClosed => _closed;

  void enqueue(PipelineQueueItem item) {
    if (_closed) return;

    while (_dequeueCompleters.isNotEmpty) {
      final completer = _dequeueCompleters.removeAt(0);
      if (!completer.isCompleted) {
        completer.complete(item);
        return;
      }
    }

    _queue.addLast(item);
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
