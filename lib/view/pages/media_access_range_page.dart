import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../service/album_selection_preference_service.dart';
import '../../service/media_access_grant_service.dart';

class MediaAccessRangePage extends StatefulWidget {
  const MediaAccessRangePage({super.key});

  @override
  State<MediaAccessRangePage> createState() => _MediaAccessRangePageState();
}

class _MediaAccessRangePageState extends State<MediaAccessRangePage> {
  bool _batteryOptimized = false;
  bool _loadingBattery = true;
  PermissionState? _permState;
  List<_AlbumItem> _albums = [];
  Set<String> _selectedIds = {};
  bool _loadingAlbums = true;

  @override
  void initState() {
    super.initState();
    _loadBatteryState();
    _loadPermissionAndAlbums();
  }

  Future<void> _loadBatteryState() async {
    if (!Platform.isAndroid) return;
    final optimized = await MediaAccessGrantService.instance
        .isIgnoringBatteryOptimizations();
    if (!mounted) return;
    setState(() {
      _batteryOptimized = optimized;
      _loadingBattery = false;
    });
  }

  Future<void> _loadPermissionAndAlbums() async {
    final state = await PhotoManager.requestPermissionExtend();
    final sel = await AlbumSelectionPreferenceService().loadSelection();
    if (!mounted) return;
    _permState = state;

    if (state.hasAccess) {
      final allAlbums = await PhotoManager.getAssetPathList(
        type: RequestType.common,
      );

      // 如果用户还没有主动选择过，自动匹配 DCIM / Camera
      if (sel.selectedAlbumIds.isEmpty) {
        final autoIds = <String>{};
        for (final album in allAlbums) {
          final lower = album.name.toLowerCase();
          if (lower == 'dcim' ||
              lower == 'camera' ||
              lower == '相机') {
            autoIds.add(album.id);
          }
        }
        _selectedIds = autoIds;
        if (autoIds.isNotEmpty) {
          await AlbumSelectionPreferenceService().saveSelection(
            selectedAlbumIds: autoIds.toList(growable: false),
          );
        }
      } else {
        _selectedIds = sel.selectedAlbumIds.toSet();
      }

      _albums = allAlbums.map((a) => _AlbumItem(
        id: a.id,
        name: a.name,
        assetCount: 0,
        isAll: a.isAll,
      )).toList();

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
    final result = await MediaAccessGrantService.instance
        .requestIgnoreBatteryOptimizations();
    if (!mounted) return;
    setState(() => _batteryOptimized = result);
    if (!result) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('用户拒绝了电池优化权限')),
      );
    }
  }

  Future<void> _requestPermission() async {
    final state = await PhotoManager.requestPermissionExtend();
    if (!mounted) return;
    setState(() => _permState = state);
    if (state.hasAccess) {
      await _loadPermissionAndAlbums();
    }
  }

  Future<void> _toggleAlbum(String id, bool selected) async {
    final next = Set<String>.from(_selectedIds);
    selected ? next.add(id) : next.remove(id);
    setState(() => _selectedIds = next);
    await AlbumSelectionPreferenceService().saveSelection(
      selectedAlbumIds: next.toList(growable: false),
    );
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
                      Icon(Icons.photo_library, color: theme.colorScheme.primary),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text('系统相册', style: theme.textTheme.titleMedium),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_permState == null)
                    const Center(child: CircularProgressIndicator(strokeWidth: 2))
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
                                ? (isLimited
                                    ? '已授权（部分访问）'
                                    : '已授权（全部访问）')
                                : '未授权',
                            style: theme.textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),
                    if (isLimited) ...[
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: () =>
                            MediaAccessGrantService.instance
                                .presentLimitedLibraryPicker(),
                        icon: const Icon(Icons.add_photo_alternate, size: 18),
                        label: const Text('选择更多照片'),
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

          // ── 相册列表 ──
          if (hasAccess) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.photo_album, color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Text('分析范围', style: theme.textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '选中需要进行分析的相册，未选中的相册将被跳过。',
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
                          onChanged: (val) => _toggleAlbum(
                            album.id,
                            val ?? false,
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
          ],

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
                        Icon(Icons.battery_charging_full,
                            color: theme.colorScheme.primary),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text('电池优化', style: theme.textTheme.titleMedium),
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
