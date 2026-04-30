import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/entity/face_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../service/face_cluster_service.dart';
import '../../storage/objectbox/objectbox_service.dart';

class FaceClusterDebugPage extends StatefulWidget {
  const FaceClusterDebugPage({super.key});

  @override
  State<FaceClusterDebugPage> createState() => _FaceClusterDebugPageState();
}

class _FaceClusterDebugPageState extends State<FaceClusterDebugPage> {
  bool _isLoading = true;
  bool _isReclustering = false;
  bool _onlyLargeClusters = true;
  String? _error;
  FaceClusterDebugSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _reloadSnapshot();
  }

  Future<void> _reloadSnapshot() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final snapshot = await _buildSnapshot();
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _runRecluster() async {
    setState(() {
      _isReclustering = true;
      _error = null;
    });

    try {
      await FaceClusterService().reclusterAllFaces();
      await _reloadSnapshot();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isReclustering = false;
        });
      }
    }
  }

  Future<FaceClusterDebugSnapshot> _buildSnapshot() async {
    final store = ObjectBoxService().store;
    final faces = store.box<FaceEntity>().getAll();
    final photos = store.box<PhotoEntity>().getAll();
    final photoById = <int, PhotoEntity>{
      for (final photo in photos) photo.id: photo,
    };
    final faceClusterService = FaceClusterService();

    final grouped = <int?, List<FaceEntity>>{};
    for (final face in faces) {
      grouped.putIfAbsent(face.clusterId, () => <FaceEntity>[]).add(face);
    }

    final groups = <FaceClusterDebugGroup>[
      ...grouped.entries
          .where((entry) => entry.key != null)
          .map((entry) => _buildGroupFromFaces(
                kind: FaceClusterDebugGroupKind.cluster,
                clusterId: entry.key,
                faces: entry.value,
              )),
    ];

    final rejectedFaces = faces.where((face) {
      if (face.clusterId != null) {
        return false;
      }
      return faceClusterService.isRejectedPhotoForDebug(photoById[face.photoId]);
    }).toList(growable: false);

    final humanUnmatchedFaces = faces.where((face) {
      if (face.clusterId != null) {
        return false;
      }
      return faceClusterService.isAttachCandidateFaceForDebug(
        face,
        photo: photoById[face.photoId],
      );
    }).toList(growable: false);

    if (humanUnmatchedFaces.isNotEmpty) {
      groups.add(
        _buildGroupFromFaces(
          kind: FaceClusterDebugGroupKind.humanUnmatched,
          titleOverride: '真人未匹配',
          faces: humanUnmatchedFaces,
        ),
      );
    }

    if (rejectedFaces.isNotEmpty) {
      groups.add(
        _buildGroupFromFaces(
          kind: FaceClusterDebugGroupKind.rejected,
          titleOverride: '已拒绝',
          faces: rejectedFaces,
        ),
      );
    }

    groups.sort((left, right) {
      if (left.kind == FaceClusterDebugGroupKind.cluster &&
          right.kind != FaceClusterDebugGroupKind.cluster) {
        return -1;
      }
      if (left.kind != FaceClusterDebugGroupKind.cluster &&
          right.kind == FaceClusterDebugGroupKind.cluster) {
        return 1;
      }
      final sizeCompare = right.size.compareTo(left.size);
      if (sizeCompare != 0) {
        return sizeCompare;
      }
      return right.averageQuality.compareTo(left.averageQuality);
    });

    final clusteredCount = faces.where((face) => face.clusterId != null).length;
    return FaceClusterDebugSnapshot(
      totalFaces: faces.length,
      clusteredFaces: clusteredCount,
      unclusteredFaces: faces.length - clusteredCount,
      humanUnmatchedFaces: humanUnmatchedFaces.length,
      rejectedFaces: rejectedFaces.length,
      groups: groups,
    );
  }

  FaceClusterDebugGroup _buildGroupFromFaces({
    required FaceClusterDebugGroupKind kind,
    int? clusterId,
    String? titleOverride,
    required List<FaceEntity> faces,
  }) {
    final members = List<FaceEntity>.from(faces)
      ..sort((left, right) {
        final primaryCompare =
            (right.isPrimaryFace ? 1 : 0).compareTo(left.isPrimaryFace ? 1 : 0);
        if (primaryCompare != 0) {
          return primaryCompare;
        }
        return (right.qualityScore ?? 0.0).compareTo(left.qualityScore ?? 0.0);
      });
    final averageQuality = members.fold<double>(
          0.0,
          (sum, face) => sum + (face.qualityScore ?? 0.0),
        ) /
        members.length;

    return FaceClusterDebugGroup(
      kind: kind,
      titleOverride: titleOverride,
      clusterId: clusterId,
      averageQuality: averageQuality,
      embeddingModelVersion: members.first.embeddingModelVersion,
      members: members
          .map((face) => FaceClusterDebugMember(face: face))
          .toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final visibleGroups = snapshot == null
        ? const <FaceClusterDebugGroup>[]
        : (_onlyLargeClusters
              ? snapshot.groups
                    .where((group) => group.clusterId != null && group.size >= 2)
                    .toList(growable: false)
              : snapshot.groups);

    return Scaffold(
      appBar: AppBar(title: const Text('人脸聚类调试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('运行概览', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (snapshot != null) ...[
                    Text('总脸数: ${snapshot.totalFaces}'),
                    Text('已分簇: ${snapshot.clusteredFaces}'),
                    Text('未分簇: ${snapshot.unclusteredFaces}'),
                    Text('真人未匹配: ${snapshot.humanUnmatchedFaces}'),
                    Text('已拒绝: ${snapshot.rejectedFaces}'),
                    Text('簇数量: ${snapshot.groups.where((group) => group.clusterId != null).length}'),
                  ] else
                    const Text('暂无数据'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: _isReclustering ? null : _runRecluster,
                        icon: _isReclustering
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.refresh),
                        label: Text(_isReclustering ? '聚类中...' : '重新聚类'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _isLoading ? null : _reloadSnapshot,
                        icon: const Icon(Icons.sync),
                        label: const Text('刷新视图'),
                      ),
                      FilterChip(
                        label: const Text('仅看大簇'),
                        selected: _onlyLargeClusters,
                        onSelected: (value) {
                          setState(() {
                            _onlyLargeClusters = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_error!),
              ),
            ),
          ],
          const SizedBox(height: 12),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (visibleGroups.isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _onlyLargeClusters ? '没有达到最小规模的人脸簇' : '暂无人脸聚类结果',
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            )
          else
            ...visibleGroups.map(
              (group) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _FaceClusterCard(group: group),
              ),
            ),
        ],
      ),
    );
  }
}

class _FaceClusterCard extends StatelessWidget {
  const _FaceClusterCard({required this.group});

  final FaceClusterDebugGroup group;

  @override
  Widget build(BuildContext context) {
    final title =
        group.titleOverride ?? (group.clusterId == null ? '未分簇' : '簇 ${group.clusterId}');

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('成员数: ${group.size}'),
            Text('平均质量: ${group.averageQuality.toStringAsFixed(3)}'),
            Text('模型版本: ${group.embeddingModelVersion}'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: group.members
                  .map((member) => _FaceMemberTile(member: member))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceMemberTile extends StatelessWidget {
  const _FaceMemberTile({required this.member});

  final FaceClusterDebugMember member;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 104,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 104,
            height: 104,
            child: _FaceCropPreview(member: member),
          ),
          const SizedBox(height: 6),
          Text(
            'face=${member.face.id}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'photo=${member.face.photoId}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            'q=${(member.face.qualityScore ?? 0).toStringAsFixed(3)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          Text(
            member.face.isPrimaryFace ? '主脸' : '普通脸',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: member.face.isPrimaryFace
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey.shade700,
                ),
          ),
        ],
      ),
    );
  }
}

class _FaceCropPreview extends StatelessWidget {
  const _FaceCropPreview({required this.member});

  final FaceClusterDebugMember member;

  @override
  Widget build(BuildContext context) {
    final debugCropPath = member.face.debugCropPath;
    if (debugCropPath == null || debugCropPath.isEmpty) {
      return _fallback();
    }

    final file = File(debugCropPath);
    if (!file.existsSync()) {
      return _fallback();
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Image.file(
        file,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => _fallback(),
      ),
    );
  }

  Widget _fallback() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade300,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.broken_image_outlined),
    );
  }
}

class FaceClusterDebugSnapshot {
  const FaceClusterDebugSnapshot({
    required this.totalFaces,
    required this.clusteredFaces,
    required this.unclusteredFaces,
    required this.humanUnmatchedFaces,
    required this.rejectedFaces,
    required this.groups,
  });

  final int totalFaces;
  final int clusteredFaces;
  final int unclusteredFaces;
  final int humanUnmatchedFaces;
  final int rejectedFaces;
  final List<FaceClusterDebugGroup> groups;
}

enum FaceClusterDebugGroupKind {
  cluster,
  humanUnmatched,
  rejected,
}

class FaceClusterDebugGroup {
  const FaceClusterDebugGroup({
    required this.kind,
    this.titleOverride,
    required this.clusterId,
    required this.averageQuality,
    required this.embeddingModelVersion,
    required this.members,
  });

  final FaceClusterDebugGroupKind kind;
  final String? titleOverride;
  final int? clusterId;
  final double averageQuality;
  final String embeddingModelVersion;
  final List<FaceClusterDebugMember> members;

  int get size => members.length;
}

class FaceClusterDebugMember {
  const FaceClusterDebugMember({
    required this.face,
  });

  final FaceEntity face;
}
