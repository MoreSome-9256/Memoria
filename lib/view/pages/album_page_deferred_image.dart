/// 相册页延迟图片组件文件，承载按需加载的相册图片逻辑。

part of 'album_page.dart';

class _DeferredImageTicket {
  _DeferredImageTicket();

  bool started = false;
  bool completed = false;
}

class _DeferredImageLoadScheduler {
  static const int _maxConcurrent = 2;
  static final ValueNotifier<int> pendingCountListenable = ValueNotifier<int>(
    0,
  );
  static final Queue<(_DeferredImageTicket, VoidCallback)> _queue =
      Queue<(_DeferredImageTicket, VoidCallback)>();
  static int _active = 0;
  static int _pendingCount = 0;
  static bool _flushScheduled = false;

  static void enqueue(_DeferredImageTicket ticket, VoidCallback starter) {
    if (ticket.completed) {
      return;
    }
    _setPendingCount(_pendingCount + 1);
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

    final next = _pendingCount - 1;
    _setPendingCount(next < 0 ? 0 : next);
    _pump();
  }

  static void _setPendingCount(int value) {
    _pendingCount = value;
    _scheduleFlush();
  }

  static void _scheduleFlush() {
    if (_flushScheduled) {
      return;
    }
    _flushScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _flushScheduled = false;
      if (pendingCountListenable.value != _pendingCount) {
        pendingCountListenable.value = _pendingCount;
      }
    });
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

class _AlbumTagPhotoTile extends StatelessWidget {
  const _AlbumTagPhotoTile({
    required this.photo,
    required this.selectionMode,
    required this.deleteMode,
    required this.selected,
    required this.onTap,
  });

  final PhotoEntity photo;
  final bool selectionMode;
  final bool deleteMode;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final heroTag = 'album-tag-photo-${photo.id}';
    return RepaintBoundary(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Hero(
                tag: heroTag,
                child: _DeferredPathImage(
                  path: photo.path,
                  assetId: photo.assetId,
                  kind: MediaTypeHelper.fromStorageValue(
                    photo.mediaKind,
                    path: photo.path,
                  ),
                  thumbnailPath: photo.thumbnailPath,
                  fit: BoxFit.cover,
                ),
              ),
              if (selectionMode && !selected)
                Container(color: Colors.black.withValues(alpha: 0.32)),
              if (selectionMode)
                Positioned(
                  top: 8,
                  right: 8,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected
                          ? (deleteMode
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary)
                          : Colors.white.withValues(alpha: 0.88),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Icon(
                      selected
                          ? (deleteMode
                                ? Icons.delete_rounded
                                : Icons.check_rounded)
                          : Icons.add_rounded,
                      size: 16,
                      color: selected
                          ? Colors.white
                          : (deleteMode
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.primary),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeferredPathImage extends StatefulWidget {
  const _DeferredPathImage({
    required this.path,
    this.assetId,
    this.kind,
    this.thumbnailPath,
    this.fit = BoxFit.cover,
  });

  final String path;
  final String? assetId;
  final MemoriaMediaKind? kind;
  final String? thumbnailPath;
  final BoxFit fit;

  @override
  State<_DeferredPathImage> createState() => _DeferredPathImageState();
}

class _DeferredPathImageState extends State<_DeferredPathImage> {
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
    // Stagger decode starts and cap concurrency to avoid image decode spikes.
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
      return MediaThumbnail(
        path: widget.path,
        assetId: widget.assetId,
        kind: widget.kind,
        thumbnailPath: widget.thumbnailPath,
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
