import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../service/album_selection_preference_service.dart';
import '../../service/photo_service.dart';
import '../../service/media_permission_service.dart';

class MediaAccessRangePage extends StatefulWidget {
  const MediaAccessRangePage({super.key});

  @override
  State<MediaAccessRangePage> createState() => _MediaAccessRangePageState();
}

class _MediaAccessRangePageState extends State<MediaAccessRangePage> {
  bool _batteryOptimized = false;
  bool _loadingBattery = true;
  PermissionState? _permState;
  bool? _hasLocationMetadataAccess;
  bool _requestingLocationMetadata = false;
  List<_AlbumItem> _albums = [];
  Set<String> _selectedIds = {};
  int _savedAlbumWhitelistCount = 0;
  bool _loadingAlbums = true;

  @override
  void initState() {
    super.initState();
    _loadBatteryState();
    _loadPermissionAndAlbums();
  }

  Future<void> _loadBatteryState() async {
    if (!Platform.isAndroid) return;
    final optimized = await Permission.ignoreBatteryOptimizations.isGranted;
    if (!mounted) return;
    setState(() {
      _batteryOptimized = optimized;
      _loadingBattery = false;
    });
  }

  Future<void> _loadPermissionAndAlbums() async {
    final state = await MediaPermissionService.readPermissionState();
    PermissionState? locationMetadataState;
    if (Platform.isAndroid && state.hasAccess) {
      locationMetadataState = state;
    }
    final hasLocationMetadataAccess = locationMetadataState == null
        ? null
        : await MediaPermissionService.hasLocationMetadataAccess();
    final sel = await AlbumSelectionPreferenceService().loadSelection();
    if (!mounted) return;
    _permState = state;
    _hasLocationMetadataAccess = hasLocationMetadataAccess;
    _savedAlbumWhitelistCount = sel.selectedAlbumIds.length;

    if (state.hasAccess) {
      final allAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
      );

      final savedIds = MediaPermissionService.effectiveAlbumWhitelist(
        state: state,
        savedAlbumIds: sel.selectedAlbumIds,
      );
      final selectedIds = <String>{};
      for (final album in allAlbums) {
        final lower = album.name.toLowerCase();
        if (savedIds.contains(album.id) ||
            savedIds.contains(album.name) ||
            savedIds.contains(lower)) {
          selectedIds.add(album.id);
        }
      }

      if (selectedIds.isNotEmpty && !setEquals(savedIds, selectedIds)) {
        await AlbumSelectionPreferenceService().saveSelection(
          selectedAlbumIds: selectedIds.toList(growable: false),
        );
        PhotoService().invalidateScanSessionCache();
      }
      _selectedIds = selectedIds;

      _albums = allAlbums
          .map(
            (a) => _AlbumItem(
              id: a.id,
              name: a.name,
              assetCount: 0,
              isAll: a.isAll,
            ),
          )
          .toList();

      // 加载计数
      for (var i = 0; i < _albums.length; i++) {
        try {
          _albums[i] = _albums[i].copyWith(
            assetCount: await allAlbums[i].assetCountAsync,
          );
        } catch (_) {}
      }
    }

    setState(() => _loadingAlbums = false);
  }

  Future<void> _requestBatteryOptimization() async {
    final result =
        await Permission.ignoreBatteryOptimizations.request() ==
        PermissionStatus.granted;
    if (!mounted) return;
    setState(() => _batteryOptimized = result);
    if (!result) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('用户拒绝了电池优化权限')));
    }
  }

  Future<void> _requestPermission() async {
    final state = await MediaPermissionService.requestAnalysisPermissions();
    if (!mounted) return;
    setState(() => _permState = state);
    if (state.hasAccess) {
      await _loadPermissionAndAlbums();
    }
  }

  Future<void> _requestLocationMetadataPermission() async {
    setState(() => _requestingLocationMetadata = true);
    try {
      final state = await MediaPermissionService.requestAnalysisPermissions();
      final hasLocationMetadataAccess =
          await MediaPermissionService.hasLocationMetadataAccess();
      if (!mounted) return;
      setState(() {
        _permState = state;
        _hasLocationMetadataAccess = hasLocationMetadataAccess;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            hasLocationMetadataAccess
                ? '已允许读取照片拍摄地点；重新分析时会补齐地点索引'
                : '未获得拍摄地点权限，地点搜索将只使用已有数据',
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _requestingLocationMetadata = false);
      }
    }
  }

  Future<void> _toggleAlbum(String id, bool selected) async {
    final next = Set<String>.from(_selectedIds);
    selected ? next.add(id) : next.remove(id);
    setState(() => _selectedIds = next);
    await AlbumSelectionPreferenceService().saveSelection(
      selectedAlbumIds: next.toList(growable: false),
    );
    PhotoService().invalidateScanSessionCache();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final perm = _permState;
    final hasAccess = perm?.hasAccess ?? false;
    final isLimited = perm?.isLimited ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('媒体访问权限')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── 系统相册权限 ──
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.photo_library,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('系统相册', style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_permState == null)
                    const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else ...[
                    Row(
                      children: [
                        Icon(
                          hasAccess
                              ? (isLimited
                                    ? Icons.warning_amber_rounded
                                    : Icons.check_circle)
                              : Icons.error_outline,
                          color: hasAccess
                              ? (isLimited ? Colors.orange : Colors.green)
                              : Colors.red,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasAccess
                                ? (isLimited ? '已授权（部分访问）' : '已授权（全部访问）')
                                : '未授权',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    if (isLimited) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          TextButton.icon(
                            onPressed: () async {
                              await MediaPermissionService.selectMorePhotos();
                              PhotoService().invalidateScanSessionCache();
                              if (!mounted) return;
                              setState(() => _loadingAlbums = true);
                              await _loadPermissionAndAlbums();
                            },
                            icon: const Icon(
                              Icons.add_photo_alternate,
                              size: 18,
                            ),
                            label: const Text('选择更多照片'),
                          ),
                          TextButton.icon(
                            onPressed: () async {
                              await MediaPermissionService.openSystemSettings();
                            },
                            icon: const Icon(Icons.settings_outlined, size: 18),
                            label: const Text('允许全部照片'),
                          ),
                        ],
                      ),
                    ],
                    if (!hasAccess) ...[
                      const SizedBox(height: 8),
                      FilledButton.tonalIcon(
                        onPressed: _requestPermission,
                        icon: const Icon(Icons.shield, size: 18),
                        label: const Text('授予权限'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          if (Platform.isAndroid && hasAccess) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.location_on_outlined,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '照片拍摄地点',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        Icon(
                          _hasLocationMetadataAccess ?? false
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: _hasLocationMetadataAccess ?? false
                              ? Colors.green
                              : Colors.orange,
                          size: 20,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Android 会单独保护照片原始文件中的 GPS。允许后，重新打标签会补齐地点、景区和附近地标索引；这不会获取设备实时位置。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (_hasLocationMetadataAccess == null)
                      const LinearProgressIndicator()
                    else if (_hasLocationMetadataAccess!)
                      Text(
                        '已允许读取拍摄地点',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: Colors.green,
                        ),
                      )
                    else
                      FilledButton.tonalIcon(
                        onPressed: _requestingLocationMetadata
                            ? null
                            : _requestLocationMetadataPermission,
                        icon: _requestingLocationMetadata
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.location_on_outlined, size: 18),
                        label: const Text('允许读取拍摄地点'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

          // ── 相册列表 ──
          if (hasAccess && !isLimited) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.photo_album,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Text('分析范围', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '未选择时使用系统当前允许访问的全部照片；选择相册后，将只分析白名单内的相册。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    if (_loadingAlbums)
                      const LinearProgressIndicator()
                    else if (_albums.isEmpty)
                      Text('没有找到相册', style: theme.textTheme.bodySmall)
                    else
                      ..._albums.map((album) {
                        // "所有照片" 虚拟相册不显示在列表中
                        if (album.isAll) return const SizedBox.shrink();
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(album.name),
                          subtitle: Text(
                            '${album.assetCount} 项',
                            style: theme.textTheme.bodySmall,
                          ),
                          value: _selectedIds.contains(album.id),
                          onChanged: (val) =>
                              _toggleAlbum(album.id, val ?? false),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (isLimited)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  '当前按系统选择的部分照片进行分析。部分授权下不叠加相册白名单，避免再次过滤已授权照片。'
                  '${_savedAlbumWhitelistCount > 0 ? ' 已保存的 $_savedAlbumWhitelistCount 个相册白名单会暂时停用，并在允许全部照片后自动恢复。' : ''}',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
            ),

          // ── 电池优化 ──
          if (Platform.isAndroid)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.battery_charging_full,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            '电池优化',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '允许后台持续分析照片，避免系统限制后台任务。',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    _loadingBattery
                        ? const LinearProgressIndicator()
                        : SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            title: const Text('忽略电池优化'),
                            value: _batteryOptimized,
                            onChanged: (_) => _requestBatteryOptimization(),
                          ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AlbumItem {
  final String id;
  final String name;
  final int assetCount;
  final bool isAll;

  const _AlbumItem({
    required this.id,
    required this.name,
    required this.assetCount,
    required this.isAll,
  });

  _AlbumItem copyWith({int? assetCount}) => _AlbumItem(
    id: id,
    name: name,
    assetCount: assetCount ?? this.assetCount,
    isAll: isAll,
  );
}
