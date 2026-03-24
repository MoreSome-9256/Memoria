import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:photo_manager/photo_manager.dart';

class VlmPhotoPickerResult {
  const VlmPhotoPickerResult({
    required this.assetId,
    required this.path,
    required this.createdAt,
  });

  final String assetId;
  final String path;
  final DateTime createdAt;
}

class VlmPhotoPickerPage extends StatefulWidget {
  const VlmPhotoPickerPage({super.key});

  @override
  State<VlmPhotoPickerPage> createState() => _VlmPhotoPickerPageState();
}

class _VlmPhotoPickerPageState extends State<VlmPhotoPickerPage> {
  static const int _pageSize = 80;
  static const int _maxSelection = 9;

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
      final permission = await PhotoManager.requestPermissionExtend();
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
        type: RequestType.image,
        onlyAll: true,
      );
      if (albums.isEmpty) {
        if (!mounted) {
          return;
        }
        setState(() {
          _errorText = '未找到可读取的图片相册';
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
        _errorText = '加载更多图片失败: $error';
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

    if (_selectedResults.length >= _maxSelection) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('一次最多选择 $_maxSelection 张图片')),
      );
      return;
    }

    final file = await asset.file;
    if (file == null || file.path.isEmpty || !File(file.path).existsSync()) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('无法读取这张图片的原始文件路径')),
      );
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _selectedResults[asset.id] = VlmPhotoPickerResult(
        assetId: asset.id,
        path: file.path,
        createdAt: asset.createDateTime,
      );
    });
  }

  void _confirmSelection() {
    if (_selectedResults.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先选择至少一张图片')),
      );
      return;
    }

    Navigator.pop(
      context,
      _selectedResults.values.toList(growable: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('选择图片'),
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
        message: '还没有拿到相册权限，请先允许应用访问图片。',
        actionLabel: '重新请求权限',
        onPressed: _loadInitialAssets,
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
        message: '当前相册中没有可用于 VLM 推理的图片。',
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
            ? _selectedResults.keys.toList(growable: false).indexOf(asset.id) + 1
            : null;

        return GestureDetector(
          onTap: () => _toggleSelectAsset(asset),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              fit: StackFit.expand,
              children: [
                _buildThumbnail(asset),
                if (isSelected)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black26,
                    ),
                  ),
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
                      isSelected
                          ? '#$selectedIndex'
                          : '+',
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
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
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
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: onPressed,
              child: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }
}