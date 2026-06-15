// VLM 照片选择页面，辅助选择用于视觉语言分析的照片。

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../service/media_permission_service.dart';
import '../../utils/media_type_helper.dart';

class VlmPhotoPickerResult {
  const VlmPhotoPickerResult({
    required this.assetId,
    required this.path,
    required this.createdAt,
    this.mediaKind = MemoriaMediaKind.image,
  });

  final String assetId;
  final String path;
  final DateTime createdAt;
  final MemoriaMediaKind mediaKind;
}

class VlmPhotoPickerPage extends StatefulWidget {
  const VlmPhotoPickerPage({
    super.key,
    this.maxSelection = 9,
    this.title = '选择图片',
    this.requestType = RequestType.image,
  });

  final int maxSelection;
  final String title;
  final RequestType requestType;

  @override
  State<VlmPhotoPickerPage> createState() => _VlmPhotoPickerPageState();
}

class _VlmPhotoPickerPageState extends State<VlmPhotoPickerPage> {
  static const int _pageSize = 80;
  final List<AssetEntity> _assets = <AssetEntity>[];
  final Map<String, VlmPhotoPickerResult> _selectedResults =
      <String, VlmPhotoPickerResult>{};

  AssetPathEntity? _album;
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  bool _permissionDenied = false;
  int _page = 0;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _loadInitialAssets();
  }

  Future<void> _loadInitialAssets() async {
    setState(() {
      _isLoading = true;
      _errorText = null;
      _permissionDenied = false;
    });

    try {
      final permission = await MediaPermissionService.readPermissionState();
      if (!permission.isAuth && !permission.hasAccess) {
        if (!mounted) {
          return;
        }
        setState(() {
          _permissionDenied = true;
          _isLoading = false;
        });
        return;
      }

      final albums = await PhotoManager.getAssetPathList(
        type: widget.requestType,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorText = widget.requestType == RequestType.common
              ? '未找到可读取的媒体'
              : '未找到可读取的图片相册';
          _isLoading = false;
        });
        return;
      }

      _album = albums.first;
      _assets.clear();
      _page = 0;
      _hasMore = true;
      await _loadMoreAssets();
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '读取相册失败: $error';
        _isLoading = false;
      });
    }
  }

  Future<void> _requestPermission() async {
    final permission = await MediaPermissionService.requestPermission();
    if (!mounted) return;
    if (permission.hasAccess) {
      await _loadInitialAssets();
      return;
    }
    setState(() {
      _permissionDenied = true;
      _isLoading = false;
    });
  }

  Future<void> _loadMoreAssets() async {
    final album = _album;
    if (album == null || _isLoadingMore || !_hasMore) {
      return;
    }

    setState(() {
      _isLoadingMore = true;
    });

    try {
      final nextPage = await album.getAssetListPaged(
        page: _page,
        size: _pageSize,
      );
      if (!mounted) {
        return;
      }

      setState(() {
        _assets.addAll(nextPage);
        _page += 1;
        _hasMore = nextPage.length == _pageSize;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '加载更多媒体失败: $error';
        _isLoading = false;
        _isLoadingMore = false;
      });
    }
  }

  Future<void> _toggleSelectAsset(AssetEntity asset) async {
    final alreadySelected = _selectedResults.containsKey(asset.id);
    if (alreadySelected) {
      setState(() {
        _selectedResults.remove(asset.id);
      });
      return;
    }

    if (_selectedResults.length >= widget.maxSelection) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一次最多选择 ${widget.maxSelection} 个媒体')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      final mediaKind = asset.type == AssetType.video
          ? MemoriaMediaKind.video
          : asset.isLivePhoto
          ? MemoriaMediaKind.dynamicImage
          : MemoriaMediaKind.image;
      _selectedResults[asset.id] = VlmPhotoPickerResult(
        assetId: asset.id,
        path: '',
        createdAt: asset.createDateTime,
        mediaKind: mediaKind,
      );
    });
  }

  void _confirmSelection() {
    if (_selectedResults.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择至少一个媒体')));
      return;
    }

    Navigator.pop(context, _selectedResults.values.toList(growable: false));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: _selectedResults.isEmpty ? null : _confirmSelection,
            child: Text('完成(${_selectedResults.length})'),
          ),
          IconButton(
            onPressed: _isLoading ? null : _loadInitialAssets,
            icon: const Icon(Icons.refresh),
            tooltip: '刷新相册',
          ),
        ],
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_permissionDenied) {
      return _buildMessageState(
        context,
        title: '无法读取图片',
        message: '还没有拿到相册权限，请先允许应用访问媒体。',
        actionLabel: '允许访问照片',
        onPressed: _requestPermission,
      );
    }

    if (_errorText != null) {
      return _buildMessageState(
        context,
        title: '读取失败',
        message: _errorText!,
        actionLabel: '重试',
        onPressed: _loadInitialAssets,
      );
    }

    if (_assets.isEmpty) {
      return _buildMessageState(
        context,
        title: '没有可选图片',
        message: '当前相册中没有可用于 VLM 推理的媒体。',
        actionLabel: '刷新',
        onPressed: _loadInitialAssets,
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _assets.length + (_hasMore ? 1 : 0),
      itemBuilder: (BuildContext context, int index) {
        if (index >= _assets.length) {
          _loadMoreAssets();
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Center(child: CircularProgressIndicator()),
          );
        }

        final asset = _assets[index];
        final isSelected = _selectedResults.containsKey(asset.id);
        final selectedIndex = isSelected
            ? _selectedResults.keys.toList(growable: false).indexOf(asset.id) +
                  1
            : null;

        return GestureDetector(
          onTap: () => _toggleSelectAsset(asset),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildThumbnail(asset),
                if (asset.type == AssetType.video || asset.isLivePhoto)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Icon(
                        asset.type == AssetType.video
                            ? Icons.videocam
                            : Icons.motion_photos_on,
                        color: Colors.white,
                        size: 14,
                      ),
                    ),
                  ),
                if (isSelected)
                  Positioned.fill(child: Container(color: Colors.black26)),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Theme.of(context).colorScheme.primary
                          : Colors.black54,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      isSelected ? '#$selectedIndex' : '+',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildThumbnail(AssetEntity asset) {
    return FutureBuilder<Uint8List?>(
      future: asset.thumbnailDataWithSize(const ThumbnailSize.square(400)),
      builder: (BuildContext context, AsyncSnapshot<Uint8List?> snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const Center(
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          );
        }

        final bytes = snapshot.data;
        if (bytes == null || bytes.isEmpty) {
          return Container(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            alignment: Alignment.center,
            child: const Icon(Icons.broken_image_outlined),
          );
        }

        return Image.memory(bytes, fit: BoxFit.cover);
      },
    );
  }

  Widget _buildMessageState(
    BuildContext context, {
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onPressed,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton(onPressed: onPressed, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}
