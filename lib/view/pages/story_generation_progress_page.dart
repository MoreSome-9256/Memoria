// 故事生成进度页面，展示故事任务的实时执行状态。

import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../models/vo/photo.dart';
import '../../models/vo/story_generation_models.dart';
import '../../service/story_queue_service.dart';
import '../../service/story_video_preparation_service.dart';
import '../../service/story_generation_orchestrator.dart';
import '../../utils/media_type_helper.dart';
import '../widgets/media_thumbnail.dart';
import 'story_result_page.dart';

@visibleForTesting
Widget buildStoryGenerationPreviewImage({
  required List<Photo> selectedPhotos,
  required String previewAssetRef,
}) {
  final assetId = _StoryGenerationPreviewRef.parseAssetId(previewAssetRef);
  if (assetId != null) {
    for (final photo in selectedPhotos) {
      if (photo.id != assetId) {
        continue;
      }
      return MediaThumbnail(
        assetId: photo.id,
        kind: MediaTypeHelper.fromStorageValue(photo.mediaKind),
        thumbnailBytes: photo.thumbnailBytes,
        fit: BoxFit.cover,
        showBadge: false,
      );
    }
  }
  return const ColoredBox(
    color: Color(0xFFE9E3EA),
    child: Center(
      child: Icon(Icons.image_not_supported_outlined, color: Color(0xFF8A7D86)),
    ),
  );
}

class _StoryGenerationPreviewRef {
  const _StoryGenerationPreviewRef._();

  static String? parseAssetId(String value) {
    const assetPrefix = 'asset:';
    if (!value.startsWith(assetPrefix)) {
      return null;
    }
    final encodedAssetId = value.substring(assetPrefix.length);
    if (encodedAssetId.trim().isEmpty) {
      return null;
    }
    return Uri.decodeComponent(encodedAssetId);
  }
}

class StoryGenerationProgressPage extends StatefulWidget {
  const StoryGenerationProgressPage({super.key, required this.request});

  final StoryGenerationRequest request;

  @override
  State<StoryGenerationProgressPage> createState() =>
      _StoryGenerationProgressPageState();
}

class _StoryGenerationProgressPageState
    extends State<StoryGenerationProgressPage> {
  StoryGenerationProgressState? _state;
  bool _isRunning = false;
  bool _hasCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runGeneration();
    });
  }

  Future<void> _runGeneration() async {
    if (_isRunning) {
      return;
    }

    setState(() {
      _isRunning = true;
      _hasCompleted = false;
      _state = null;
    });

    try {
      final output = await StoryGenerationOrchestrator().generateStory(
        request: widget.request,
        onProgress: (state) {
          if (!mounted) {
            return;
          }
          setState(() {
            _state = state;
          });
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isRunning = false;
        _hasCompleted = true;
      });

      StoryVideoPreparationResult? videoPreparation;
      try {
        videoPreparation = await StoryVideoPreparationService().prepare(
          request: widget.request,
          story: output.story,
          photos: output.photos,
          onStatus: (status) {
            if (!mounted) {
              return;
            }
            setState(() {
              _state = StoryGenerationProgressState(
                steps: _state?.steps ?? const <StoryGenerationProgressStep>[],
                headline: status,
                isCompleted: false,
              );
            });
          },
        );
      } catch (_) {
        videoPreparation = null;
      }

      if (!mounted) {
        return;
      }

      StoryQueueService().clear();

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => StoryResultPage.fromStoryEntity(
            storyEntity: output.story,
            photos: output.photos,
            storyTemplateId: widget.request.storyTemplateId,
            customMusicPath: videoPreparation?.customMusicPath,
            dynamicBeatData: videoPreparation?.dynamicBeatData,
            videoCaptions: videoPreparation?.captions,
            photoOverrides: widget.request.selectedPhotos,
            isHorizontal: widget.request.isHorizontal,
            targetPlatform: widget.request.targetPlatform,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _isRunning = false;
        _state = StoryGenerationProgressState(
          steps: _state?.steps ?? const <StoryGenerationProgressStep>[],
          headline: '故事生成失败，请重试或返回修改输入。你选中的图片还在队列里面哦~',
          errorMessage: error.toString(),
          isCompleted: false,
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final steps = _visibleSteps(
      state?.steps ?? const <StoryGenerationProgressStep>[],
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF8F3F5),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('正在生成故事'),
      ),
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color(0xFFF9EEF5),
              Color(0xFFF4F2FF),
              Color(0xFFF7FBFF),
            ],
          ),
        ),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          children: [
            Text(
              widget.request.title,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              state?.headline ?? '正在准备故事素材',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[700],
                height: 1.45,
              ),
            ),
            if (widget.request.semanticSearchQuery?.trim().isNotEmpty ==
                true) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.75),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2C0D3)),
                ),
                child: Text(
                  '搜索线索：${widget.request.semanticSearchQuery!.trim()}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF7E4864),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 22),
            for (var index = 0; index < steps.length; index++)
              _ProgressStepCard(
                step: steps[index],
                isLast: index == steps.length - 1,
                previewBuilder: _buildPreviewImage,
              ),
            if (_isRunning) ...[
              const SizedBox(height: 12),
              Center(
                child: Text(
                  '正在为你编织图文并茂的故事...',
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.grey[700]),
                ),
              ),
            ],
            if (state?.errorMessage != null && !_isRunning) ...[
              const SizedBox(height: 18),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3F2),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFFD2CC)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '生成失败',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFB42318),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state!.errorMessage!,
                      style: const TextStyle(
                        color: Color(0xFF7A271A),
                        height: 1.45,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        FilledButton(
                          onPressed: _runGeneration,
                          child: const Text('重新生成'),
                        ),
                        const SizedBox(width: 10),
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('返回修改'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (_hasCompleted) const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  List<StoryGenerationProgressStep> _visibleSteps(
    List<StoryGenerationProgressStep> steps,
  ) {
    if (steps.isEmpty) {
      return steps;
    }
    final firstPendingIndex = steps.indexWhere(
      (step) => step.status == StoryGenerationProgressStatus.pending,
    );
    if (firstPendingIndex == -1) {
      return steps;
    }
    final visibleCount = (firstPendingIndex + 1).clamp(1, steps.length);
    return steps.take(visibleCount).toList(growable: false);
  }

  Widget _buildPreviewImage(String previewAssetRef) {
    return buildStoryGenerationPreviewImage(
      selectedPhotos: widget.request.selectedPhotos,
      previewAssetRef: previewAssetRef,
    );
  }
}

class _ProgressStepCard extends StatefulWidget {
  const _ProgressStepCard({
    required this.step,
    required this.isLast,
    required this.previewBuilder,
  });

  final StoryGenerationProgressStep step;
  final bool isLast;
  final Widget Function(String previewAssetRef) previewBuilder;

  @override
  State<_ProgressStepCard> createState() => _ProgressStepCardState();
}

class _ProgressStepCardState extends State<_ProgressStepCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant _ProgressStepCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.step.status == StoryGenerationProgressStatus.inProgress) {
      _controller.repeat();
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(widget.step.status);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            _buildLeadingVisual(color),
            if (!widget.isLast)
              Container(
                width: 2,
                height: 34,
                margin: const EdgeInsets.symmetric(vertical: 6),
                color: const Color(0xFFD9C6D3),
              ),
          ],
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.74),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: Colors.white),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x12000000),
                  blurRadius: 16,
                  offset: Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.step.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (widget.step.detail?.trim().isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.step.detail!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[700],
                      height: 1.45,
                    ),
                  ),
                ],
                if (widget.step.previewAssetIds.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 84,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: widget.step.previewAssetIds.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: SizedBox(
                            width: 120,
                            child: widget.previewBuilder(
                              widget.step.previewAssetIds[index],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
                if (widget.step.bullets.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  for (final bullet in widget.step.bullets)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '• $bullet',
                        style: Theme.of(
                          context,
                        ).textTheme.bodyMedium?.copyWith(height: 1.45),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLeadingVisual(Color color) {
    final previewAssetId = widget.step.previewAssetIds.isNotEmpty
        ? widget.step.previewAssetIds.first
        : null;
    final shouldSpin =
        widget.step.status == StoryGenerationProgressStatus.inProgress;

    if (previewAssetId != null) {
      final image = ClipOval(
        child: SizedBox(
          width: 34,
          height: 34,
          child: widget.previewBuilder(previewAssetId),
        ),
      );

      return Container(
        width: 42,
        height: 42,
        alignment: Alignment.center,
        child: shouldSpin
            ? AnimatedBuilder(
                animation: _controller,
                child: image,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _controller.value * math.pi * 2,
                    child: child,
                  );
                },
              )
            : Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: color.withValues(alpha: 0.18)),
                ),
                child: image,
              ),
      );
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        shape: BoxShape.circle,
      ),
      child: shouldSpin
          ? AnimatedBuilder(
              animation: _controller,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _controller.value * math.pi * 2,
                  child: child,
                );
              },
              child: Icon(
                _statusIcon(widget.step.status),
                color: color,
                size: 20,
              ),
            )
          : Icon(_statusIcon(widget.step.status), color: color, size: 20),
    );
  }

  Color _statusColor(StoryGenerationProgressStatus status) {
    switch (status) {
      case StoryGenerationProgressStatus.pending:
        return const Color(0xFFB9A9B4);
      case StoryGenerationProgressStatus.inProgress:
        return const Color(0xFF7F56D9);
      case StoryGenerationProgressStatus.completed:
        return const Color(0xFF12B76A);
      case StoryGenerationProgressStatus.failed:
        return const Color(0xFFF04438);
    }
  }

  IconData _statusIcon(StoryGenerationProgressStatus status) {
    switch (status) {
      case StoryGenerationProgressStatus.pending:
        return Icons.more_horiz_rounded;
      case StoryGenerationProgressStatus.inProgress:
        return Icons.autorenew_rounded;
      case StoryGenerationProgressStatus.completed:
        return Icons.check_rounded;
      case StoryGenerationProgressStatus.failed:
        return Icons.close_rounded;
    }
  }
}
