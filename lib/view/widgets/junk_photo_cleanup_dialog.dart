import 'package:flutter/material.dart';

import '../../service/junk_photo_filter_service.dart';
import 'fullscreen_photo_viewer.dart';
import 'path_image.dart';

class JunkPhotoCleanupDialog extends StatefulWidget {
  const JunkPhotoCleanupDialog({super.key, required this.report});

  final JunkPhotoCleanupReport report;

  @override
  State<JunkPhotoCleanupDialog> createState() => _JunkPhotoCleanupDialogState();
}

class _JunkPhotoCleanupDialogState extends State<JunkPhotoCleanupDialog> {
  late final Set<int> _selectedPhotoIds = widget.report.candidates
      .map((candidate) => candidate.photoId)
      .toSet();
  String? _activeReasonLabel;

  void _toggle(int photoId, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selectedPhotoIds.add(photoId);
      } else {
        _selectedPhotoIds.remove(photoId);
      }
    });
  }

  void _selectAll() {
    final visibleCandidates = _filteredCandidates;
    setState(() {
      _selectedPhotoIds.addAll(visibleCandidates.map((item) => item.photoId));
    });
  }

  void _clearAll() {
    final visibleCandidates = _filteredCandidates;
    setState(() {
      if (_activeReasonLabel == null) {
        _selectedPhotoIds.clear();
      } else {
        _selectedPhotoIds.removeAll(
          visibleCandidates.map((item) => item.photoId),
        );
      }
    });
  }

  List<JunkPhotoCleanupCandidate> get _filteredCandidates {
    final activeReasonLabel = _activeReasonLabel;
    if (activeReasonLabel == null) {
      return widget.report.candidates;
    }

    return widget.report.candidates
        .where(
          (candidate) => candidate.reasons.any(
            (reason) => reason.label == activeReasonLabel,
          ),
        )
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final report = widget.report;
    final filteredCandidates = _filteredCandidates;
    final dialogSize = MediaQuery.of(context).size;
    final maxDialogWidth = dialogSize.width * 0.96;
    final maxDialogHeight = dialogSize.height * 0.84;
    final selectionSummary =
        '已选 ${_selectedPhotoIds.length} / ${report.totalCount}，当前显示 ${filteredCandidates.length} 张';

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxDialogWidth > 720 ? 720 : maxDialogWidth,
          maxHeight: maxDialogHeight,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isCompactLayout = constraints.maxWidth < 420;
            final gridColumnCount = constraints.maxWidth < 360 ? 2 : 3;

            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '检测到可清理照片',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '系统识别出 ${report.totalCount} 张低质量候选图片。'
                    '你可以勾选需要从本地数据库删除的记录，系统相册原图不会被删除。',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text('全部 ${report.totalCount}'),
                        selected: _activeReasonLabel == null,
                        onSelected: (_) {
                          setState(() {
                            _activeReasonLabel = null;
                          });
                        },
                      ),
                      ...(() {
                        final entries = report.reasonCounts.entries.toList()
                          ..sort((a, b) => b.value.compareTo(a.value));
                        return entries.map(
                          (entry) => ChoiceChip(
                            label: Text('${entry.key} ${entry.value}'),
                            selected: _activeReasonLabel == entry.key,
                            onSelected: (_) {
                              setState(() {
                                _activeReasonLabel =
                                    _activeReasonLabel == entry.key
                                    ? null
                                    : entry.key;
                              });
                            },
                          ),
                        );
                      })(),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isCompactLayout) ...[
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        TextButton(
                          onPressed: _selectAll,
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: _clearAll,
                          child: const Text('清空'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      selectionSummary,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ] else
                    Row(
                      children: [
                        TextButton(
                          onPressed: _selectAll,
                          child: const Text('全选'),
                        ),
                        TextButton(
                          onPressed: _clearAll,
                          child: const Text('清空'),
                        ),
                        const Spacer(),
                        Flexible(
                          child: Text(
                            selectionSummary,
                            textAlign: TextAlign.end,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: filteredCandidates.isEmpty
                        ? Center(
                            child: Text(
                              '当前筛选下暂无候选图片',
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(color: Colors.grey[600]),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.only(bottom: 4),
                            itemCount: filteredCandidates.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: gridColumnCount,
                                  mainAxisSpacing: 10,
                                  crossAxisSpacing: 10,
                                  childAspectRatio: 0.72,
                                ),
                            itemBuilder: (context, index) {
                              final candidate = filteredCandidates[index];
                              final selected = _selectedPhotoIds.contains(
                                candidate.photoId,
                              );
                              final heroTag =
                                  'junk-cleanup-${candidate.photoId}';

                              return Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: selected
                                        ? Theme.of(context).colorScheme.primary
                                        : Theme.of(context).dividerColor,
                                    width: selected ? 2 : 1,
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Expanded(
                                      child: Stack(
                                        children: [
                                          Positioned.fill(
                                            child: InkWell(
                                              borderRadius:
                                                  const BorderRadius.vertical(
                                                    top: Radius.circular(13),
                                                  ),
                                              onTap: () =>
                                                  showFullscreenPhotoViewer(
                                                    context,
                                                    path: candidate.path,
                                                    heroTag: heroTag,
                                                  ),
                                              child: ClipRRect(
                                                borderRadius:
                                                    const BorderRadius.vertical(
                                                      top: Radius.circular(13),
                                                    ),
                                                child: Hero(
                                                  tag: heroTag,
                                                  child: PathImage(
                                                    path: candidate.path,
                                                    fit: BoxFit.cover,
                                                  ),
                                                ),
                                              ),
                                            ),
                                          ),
                                          Positioned(
                                            top: 6,
                                            right: 6,
                                            child: Material(
                                              color: Colors.black.withValues(
                                                alpha: 0.42,
                                              ),
                                              shape: const CircleBorder(),
                                              child: Checkbox(
                                                value: selected,
                                                onChanged: (checked) => _toggle(
                                                  candidate.photoId,
                                                  checked,
                                                ),
                                                visualDensity:
                                                    VisualDensity.compact,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    InkWell(
                                      borderRadius: const BorderRadius.vertical(
                                        bottom: Radius.circular(13),
                                      ),
                                      onTap: () =>
                                          _toggle(candidate.photoId, !selected),
                                      child: Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                          8,
                                          8,
                                          8,
                                          10,
                                        ),
                                        child: Text(
                                          _formatTimestamp(candidate.timestamp),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 12),
                  OverflowBar(
                    alignment: MainAxisAlignment.end,
                    spacing: 12,
                    overflowSpacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('暂不处理'),
                      ),
                      FilledButton.icon(
                        onPressed: _selectedPhotoIds.isEmpty
                            ? null
                            : () => Navigator.of(
                                context,
                              ).pop(_selectedPhotoIds.toList(growable: false)),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('删除所选本地记录'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  String _formatTimestamp(int timestamp) {
    final dateTime = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final month = dateTime.month.toString().padLeft(2, '0');
    final day = dateTime.day.toString().padLeft(2, '0');
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '${dateTime.year}-$month-$day $hour:$minute';
  }
}
