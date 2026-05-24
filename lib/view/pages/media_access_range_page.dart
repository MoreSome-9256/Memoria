import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../service/media_access_grant_service.dart';

class MediaAccessRangePage extends StatefulWidget {
  const MediaAccessRangePage({super.key});

  @override
  State<MediaAccessRangePage> createState() => _MediaAccessRangePageState();
}

class _MediaAccessRangePageState extends State<MediaAccessRangePage> {
  MediaAccessGrantSnapshot? _snapshot;
  PermissionState? _photoPermission;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final snapshot = await MediaAccessGrantService.instance.loadSnapshot();
    PermissionState? permission;
    try {
      permission = await PhotoManager.getPermissionState(
        requestOption: const PermissionRequestOption(),
      );
    } catch (_) {
      permission = null;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _photoPermission = permission;
      _loading = false;
    });
  }

  Future<void> _addAutoSource() async {
    if (Platform.isAndroid) {
      await MediaAccessGrantService.instance.requestAndroidDirectoryGrant();
    } else {
      await PhotoManager.requestPermissionExtend();
    }
    await _reload();
  }

  Future<void> _addManualMedia() async {
    final result = await MediaAccessGrantService.instance.pickMedia();
    await _reload();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          result.addedAssetIds > 0
              ? '已手动加入 ${result.addedAssetIds} 个项目'
              : '没有新增项目',
        ),
      ),
    );
  }

  Future<void> _clearManualMedia() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空手动加入列表'),
        content: const Text('这只会移除 App 里的引用，不会删除原始照片或视频。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) {
      return;
    }
    await MediaAccessGrantService.instance.clearSelectedAssets();
    await _reload();
  }

  Future<void> _manageManualMedia() async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.7,
          minChildSize: 0.35,
          maxChildSize: 0.9,
          builder: (context, controller) {
            final entries = <_ManualMediaEntry>[
              for (final id in snapshot.selectedAssetIds)
                _ManualMediaEntry.asset(id),
              for (final path in snapshot.selectedFilePaths)
                _ManualMediaEntry.file(path),
            ];
            return Column(
              children: [
                ListTile(
                  title: const Text('手动加入的媒体'),
                  subtitle: Text('${entries.length} 项'),
                  trailing: IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),
                const Divider(height: 1),
                if (entries.isEmpty)
                  const Expanded(
                    child: Center(child: Text('当前没有手动加入的照片或视频')),
                  )
                else
                  Expanded(
                    child: ListView.builder(
                      controller: controller,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        final entry = entries[index];
                        return ListTile(
                          leading: Icon(
                            entry.isAsset
                                ? Icons.photo_library_outlined
                                : Icons.insert_drive_file_outlined,
                          ),
                          title: Text(
                            entry.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(entry.kindLabel),
                          trailing: TextButton(
                            onPressed: () async {
                              await MediaAccessGrantService.instance
                                  .removeSelectedManualMedia(
                                    assetId: entry.assetId,
                                    filePath: entry.filePath,
                                  );
                              if (!context.mounted) return;
                              Navigator.pop(context);
                              await _reload();
                              if (!mounted) return;
                              unawaited(_manageManualMedia());
                            },
                            child: const Text('移除'),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _saveDefaultRules({
    bool? excludeScreenshots,
    bool? excludeScreenRecordings,
    bool? excludeSmallMedia,
    bool? excludeDuplicates,
    List<String>? excludedMediaTypes,
  }) async {
    final snapshot = _snapshot;
    if (snapshot == null) {
      return;
    }
    await MediaAccessGrantService.instance.setDefaultExclusionRules(
      excludeScreenshots: excludeScreenshots ?? snapshot.excludeScreenshots,
      excludeScreenRecordings:
          excludeScreenRecordings ?? snapshot.excludeScreenRecordings,
      excludeSmallMedia: excludeSmallMedia ?? snapshot.excludeSmallMedia,
      excludeDuplicates: excludeDuplicates ?? snapshot.excludeDuplicates,
      excludedMediaTypes: excludedMediaTypes ?? snapshot.excludedMediaTypes,
    );
    await _reload();
  }

  Future<void> _removeSource(String sourceId) async {
    final choice = await showDialog<_RemoveSourceChoice>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('移除此自动来源'),
        content: const Text('你可以只停止后续分析，也可以同时删除这个来源已生成的分析结果。原始图片和视频不会被删除。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _RemoveSourceChoice.keepResults),
            child: const Text('保留结果'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, _RemoveSourceChoice.deleteResults),
            child: const Text('删除结果'),
          ),
        ],
      ),
    );
    if (choice == null) {
      return;
    }
    await MediaAccessGrantService.instance.removeAndroidDirectoryGrant(
      sourceId,
    );
    await _reload();
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          choice == _RemoveSourceChoice.deleteResults
              ? '已移除来源。分析结果删除会在后台清理任务中执行。'
              : '已停止后续分析，已有分析结果保留。',
        ),
      ),
    );
  }

  Future<void> _openSourceDetail(String sourceId) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => MediaSourceDetailPage(sourceId: sourceId),
      ),
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return Scaffold(
      appBar: AppBar(title: const Text('授权媒体来源')),
      body: _loading || snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                _SectionHeader(
                  title: '自动分析来源',
                  description:
                      '这些来源中的新图片和视频会在你导入新项目时自动加入分析队列。你可以排除其中的子文件夹或部分内容。',
                ),
                if (Platform.isAndroid) ...[
                  for (final sourceId in snapshot.androidTreeUris)
                    _AutoSourceTile(
                      title: snapshot.displayNameForSource(sourceId),
                      subtitle: _sourceSubtitle(snapshot, sourceId),
                      onManage: () => _openSourceDetail(sourceId),
                    ),
                  OutlinedButton.icon(
                    onPressed: _addAutoSource,
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('添加自动来源'),
                  ),
                ] else ...[
                  _IosPhotoAccessActions(
                    permission: _photoPermission,
                    selectedCount: snapshot.manualMediaCount,
                    onRequestFull: () async {
                      await PhotoManager.requestPermissionExtend();
                      await _reload();
                    },
                    onAddMore: _addManualMedia,
                    onManageLimited: () async {
                      await MediaAccessGrantService.instance
                          .presentLimitedLibraryPicker();
                      await _reload();
                    },
                  ),
                ],
                const SizedBox(height: 24),
                _SectionHeader(
                  title: '手动加入的媒体',
                  description: '适合微信、QQ、下载图等只有少量需要分析的内容。这里的项目不会自动扩展到整个文件夹。',
                ),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.playlist_add_check),
                        title: Text(
                          '手动加入的照片/视频：${snapshot.manualMediaCount} 项',
                        ),
                        subtitle: const Text('如果系统无法长期访问，后续可能需要重新选择。'),
                      ),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: _addManualMedia,
                            child: const Text('添加更多'),
                          ),
                          TextButton(
                            onPressed: _manageManualMedia,
                            child: const Text('管理'),
                          ),
                          TextButton(
                            onPressed: snapshot.manualMediaCount == 0
                                ? null
                                : _clearManualMedia,
                            child: const Text('清空手动加入列表'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: '排除规则',
                  description: '这些内容即使位于已授权来源中，也不会进入分析队列。',
                ),
                _RuleSwitch(
                  title: '排除截图',
                  value: snapshot.excludeScreenshots,
                  onChanged: (value) =>
                      _saveDefaultRules(excludeScreenshots: value),
                ),
                _RuleSwitch(
                  title: '排除屏幕录制',
                  value: snapshot.excludeScreenRecordings,
                  onChanged: (value) =>
                      _saveDefaultRules(excludeScreenRecordings: value),
                ),
                _RuleSwitch(
                  title: '排除小尺寸图片，例如小于 512px',
                  value: snapshot.excludeSmallMedia,
                  onChanged: (value) =>
                      _saveDefaultRules(excludeSmallMedia: value),
                ),
                _RuleSwitch(
                  title: '排除重复项',
                  value: snapshot.excludeDuplicates,
                  onChanged: (value) =>
                      _saveDefaultRules(excludeDuplicates: value),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      CheckboxListTile(
                        title: const Text('排除 GIF'),
                        value: snapshot.excludedMediaTypes.contains('gif'),
                        onChanged: (value) {
                          final next = <String>{...snapshot.excludedMediaTypes};
                          value == true ? next.add('gif') : next.remove('gif');
                          _saveDefaultRules(
                            excludedMediaTypes: next.toList(growable: false),
                          );
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('排除视频'),
                        value: snapshot.excludedMediaTypes.contains('video'),
                        onChanged: (value) {
                          final next = <String>{...snapshot.excludedMediaTypes};
                          value == true
                              ? next.add('video')
                              : next.remove('video');
                          _saveDefaultRules(
                            excludedMediaTypes: next.toList(growable: false),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                _SectionHeader(
                  title: '系统访问权限',
                  description: '这里显示系统层面已经允许 App 访问哪些内容。',
                ),
                _SystemPermissionCard(
                  snapshot: snapshot,
                  photoPermission: _photoPermission,
                  onAddFolder: _addAutoSource,
                  onAddMore: _addManualMedia,
                  onOpenSettings: PhotoManager.openSetting,
                  onRemoveSource: _removeSource,
                ),
              ],
            ),
    );
  }

  String _sourceSubtitle(MediaAccessGrantSnapshot snapshot, String sourceId) {
    final excluded = snapshot.excludedSubpathCount(sourceId);
    final included = snapshot.includedSubpathCount(sourceId);
    final enabled = snapshot.isAutoSourceEnabled(sourceId);
    final parts = <String>[
      enabled ? '状态：自动包含新项目' : '状态：已暂停',
      if (included > 0) '只分析：$included 条',
      if (excluded > 0) '排除规则：$excluded 条',
    ];
    return parts.join(' · ');
  }
}

class MediaSourceDetailPage extends StatefulWidget {
  const MediaSourceDetailPage({super.key, required this.sourceId});

  final String sourceId;

  @override
  State<MediaSourceDetailPage> createState() => _MediaSourceDetailPageState();
}

class _MediaSourceDetailPageState extends State<MediaSourceDetailPage> {
  MediaAccessGrantSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final snapshot = await MediaAccessGrantService.instance.loadSnapshot();
    if (!mounted) {
      return;
    }
    setState(() => _snapshot = snapshot);
  }

  Future<void> _addExcludedSubpath() async {
    final controller = TextEditingController();
    final subpath = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('排除此子文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '子文件夹名称或相对路径',
            hintText: '例如 a/b',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('排除'),
          ),
        ],
      ),
    );
    if (subpath == null || subpath.trim().isEmpty) {
      return;
    }
    await MediaAccessGrantService.instance.addExcludedSubpath(
      widget.sourceId,
      subpath,
    );
    await _reload();
  }

  Future<void> _setOnlyIncludedSubpaths() async {
    final snapshot = _snapshot;
    final existing =
        snapshot?.includedSubpathsBySource[widget.sourceId]?.join('\n') ?? '';
    final controller = TextEditingController(text: existing);
    final raw = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('只分析选中的子文件夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          decoration: const InputDecoration(
            labelText: '每行一个子文件夹',
            hintText: '例如 a/a',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (raw == null) {
      return;
    }
    final subpaths = raw
        .split(RegExp(r'[\r\n,，]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    await MediaAccessGrantService.instance.setIncludedSubpaths(
      widget.sourceId,
      subpaths,
    );
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final title =
        snapshot?.displayNameForSource(widget.sourceId) ?? widget.sourceId;
    final included =
        snapshot?.includedSubpathsBySource[widget.sourceId] ?? const <String>[];
    final excluded =
        snapshot?.excludedSubpathsBySource[widget.sourceId] ?? const <String>[];
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: snapshot == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
              children: [
                ListTile(title: Text(title), subtitle: const Text('类型：自动来源')),
                SwitchListTile(
                  title: const Text('自动导入新项目'),
                  value: snapshot.isAutoSourceEnabled(widget.sourceId),
                  onChanged: (value) async {
                    await MediaAccessGrantService.instance.setAutoSourceEnabled(
                      widget.sourceId,
                      value,
                    );
                    await _reload();
                  },
                ),
                SwitchListTile(
                  title: const Text('包含子文件夹'),
                  value: snapshot.includesChildren(widget.sourceId),
                  onChanged: (value) async {
                    await MediaAccessGrantService.instance
                        .setSourceIncludesChildren(widget.sourceId, value);
                    await _reload();
                  },
                ),
                const ListTile(
                  title: Text('已分析项目数'),
                  trailing: Text('按下次扫描更新'),
                ),
                const ListTile(
                  title: Text('待分析项目数'),
                  trailing: Text('按下次扫描更新'),
                ),
                const ListTile(title: Text('无法访问项目数'), trailing: Text('0')),
                const Divider(height: 28),
                Text('子文件夹列表', style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                if (included.isEmpty && excluded.isEmpty)
                  const ListTile(
                    title: Text('当前没有单独排除的子文件夹'),
                    subtitle: Text('例如授权 MYFILE/a 后，可以在这里排除 MYFILE/a/b。'),
                  ),
                for (final path in included)
                  ListTile(
                    leading: const Icon(Icons.check_circle_outline),
                    title: Text(path),
                    subtitle: const Text('已包含'),
                  ),
                for (final path in excluded)
                  ListTile(
                    leading: const Icon(Icons.block_outlined),
                    title: Text(path),
                    subtitle: const Text('已排除'),
                    trailing: TextButton(
                      onPressed: () async {
                        await MediaAccessGrantService.instance
                            .removeExcludedSubpath(widget.sourceId, path);
                        await _reload();
                      },
                      child: const Text('重新包含'),
                    ),
                  ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _addExcludedSubpath,
                  icon: const Icon(Icons.playlist_remove_outlined),
                  label: const Text('排除此来源中的某个子文件夹'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _setOnlyIncludedSubpaths,
                  icon: const Icon(Icons.filter_alt_outlined),
                  label: const Text('仅分析选中的子文件夹'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: () async {
                    await MediaAccessGrantService.instance.setAutoSourceEnabled(
                      widget.sourceId,
                      false,
                    );
                    await _reload();
                  },
                  icon: const Icon(Icons.pause_circle_outline),
                  label: const Text('暂停此来源'),
                ),
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () async {
                    await MediaAccessGrantService.instance
                        .removeAndroidDirectoryGrant(widget.sourceId);
                    if (!context.mounted) return;
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.link_off_outlined),
                  label: const Text('撤销系统访问，高级操作'),
                ),
              ],
            ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(description, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _AutoSourceTile extends StatelessWidget {
  const _AutoSourceTile({
    required this.title,
    required this.subtitle,
    required this.onManage,
  });

  final String title;
  final String subtitle;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.folder_open_outlined),
        title: Text(title),
        subtitle: Text('$subtitle\n已分析：按下次扫描更新 · 待分析：按下次扫描更新'),
        isThreeLine: true,
        trailing: TextButton(onPressed: onManage, child: const Text('管理')),
      ),
    );
  }
}

class _RuleSwitch extends StatelessWidget {
  const _RuleSwitch({
    required this.title,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: SwitchListTile(
        title: Text(title),
        value: value,
        onChanged: onChanged,
      ),
    );
  }
}

class _IosPhotoAccessActions extends StatelessWidget {
  const _IosPhotoAccessActions({
    required this.permission,
    required this.selectedCount,
    required this.onRequestFull,
    required this.onAddMore,
    required this.onManageLimited,
  });

  final PermissionState? permission;
  final int selectedCount;
  final Future<void> Function() onRequestFull;
  final Future<void> Function() onAddMore;
  final Future<void> Function() onManageLimited;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Column(
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: Text('当前照片权限：${_permissionLabel(permission)}'),
            subtitle: Text(
              permission == PermissionState.limited
                  ? '已选择项目数量：$selectedCount。新照片不会自动进入可分析范围，需要手动添加更多。'
                  : '如果允许访问全部照片，实际分析范围仍由排除规则决定。',
            ),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onRequestFull,
                child: const Text('允许访问全部照片'),
              ),
              TextButton(onPressed: onAddMore, child: const Text('选择部分照片和视频')),
              TextButton(
                onPressed: onManageLimited,
                child: const Text('管理已选择的照片和视频'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SystemPermissionCard extends StatelessWidget {
  const _SystemPermissionCard({
    required this.snapshot,
    required this.photoPermission,
    required this.onAddFolder,
    required this.onAddMore,
    required this.onOpenSettings,
    required this.onRemoveSource,
  });

  final MediaAccessGrantSnapshot snapshot;
  final PermissionState? photoPermission;
  final Future<void> Function() onAddFolder;
  final Future<void> Function() onAddMore;
  final Future<void> Function() onOpenSettings;
  final Future<void> Function(String sourceId) onRemoveSource;

  @override
  Widget build(BuildContext context) {
    if (Platform.isAndroid) {
      return Card(
        child: Column(
          children: [
            ListTile(
              title: Text('已授权文件夹数量：${snapshot.androidTreeUris.length}'),
              subtitle: Text(
                '已授权单独媒体数量：${snapshot.manualMediaCount}\n是否有全量媒体访问权限：否',
              ),
              isThreeLine: true,
            ),
            for (final sourceId in snapshot.androidTreeUris)
              ListTile(
                dense: true,
                title: Text(snapshot.displayNameForSource(sourceId)),
                trailing: TextButton(
                  onPressed: () => onRemoveSource(sourceId),
                  child: const Text('撤销访问'),
                ),
              ),
            OverflowBar(
              alignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: onAddFolder,
                  child: const Text('添加文件夹访问'),
                ),
                TextButton(
                  onPressed: onOpenSettings,
                  child: const Text('打开系统设置'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Card(
      child: Column(
        children: [
          ListTile(
            title: Text('当前照片权限：${_permissionLabel(photoPermission)}'),
            subtitle: photoPermission == PermissionState.authorized
                ? const Text('App 可以读取整个照片库，但实际分析范围由上面的规则决定。')
                : Text('已选择项目数量：${snapshot.manualMediaCount}'),
          ),
          OverflowBar(
            alignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: onOpenSettings,
                child: const Text('管理系统照片权限'),
              ),
              TextButton(onPressed: onAddMore, child: const Text('添加更多照片和视频')),
            ],
          ),
        ],
      ),
    );
  }
}

String _permissionLabel(PermissionState? permission) {
  return switch (permission) {
    PermissionState.authorized => 'Full',
    PermissionState.limited => 'Limited',
    PermissionState.denied => 'None',
    PermissionState.restricted => 'None',
    PermissionState.notDetermined => 'None',
    _ => 'Unknown',
  };
}

enum _RemoveSourceChoice { keepResults, deleteResults }

class _ManualMediaEntry {
  const _ManualMediaEntry._({this.assetId, this.filePath});

  factory _ManualMediaEntry.asset(String id) =>
      _ManualMediaEntry._(assetId: id);
  factory _ManualMediaEntry.file(String path) =>
      _ManualMediaEntry._(filePath: path);

  final String? assetId;
  final String? filePath;

  bool get isAsset => assetId != null;
  String get label => filePath ?? assetId ?? '';
  String get kindLabel => isAsset ? '系统照片项目' : '文件路径项目';
}
