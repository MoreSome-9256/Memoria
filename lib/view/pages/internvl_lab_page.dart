import 'dart:io';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:photo_manager/photo_manager.dart';

import '../../models/entity/photo_entity.dart';
import '../../service/internvl_experiment_service.dart';
import '../../service/on_device_internvl_service.dart';
import '../../service/photo_service.dart';
import '../widgets/path_image.dart';
import 'vlm_photo_picker_page.dart';

/// “我的”页下的手机本地 VLM 推理页。
///
/// 这个页面遵循两个原则：
/// 1. 和正式功能隔离，不污染现有首页、故事流、聚类流。
/// 2. 把“路线选择、设备判断、图片测试”放在一个页面里，减少调试成本。
///
/// 当前选择的最实际路线是：
/// - 优先直接执行手机上的 llama-mtmd-cli
/// - HTTP 环回接口只作为备用验证路径
/// - 不先做 OPPO / MediaTek 专属 NPU 适配
///
/// 原因：
/// - 你的手机 RAM 够，1B Q4 从硬件角度有机会跑起来
/// - 真机测试已经证明 CLI 直跑可行，且比当前 llama-server 更稳定
/// - 厂商 NPU 方案需要单独 SDK、转换链和精度验证，第一阶段并不经济
class InternvlLabPage extends StatefulWidget {
  const InternvlLabPage({super.key});

  @override
  State<InternvlLabPage> createState() => _InternvlLabPageState();
}

class _InternvlLabPageState extends State<InternvlLabPage> {
  static const String _defaultHttpBaseUrl = String.fromEnvironment(
    'LLM_BASE_URL',
    defaultValue: 'https://api-inference.modelscope.cn/v1',
  );
  static const String _defaultHttpApiPath = String.fromEnvironment(
    'LLM_API_PATH',
    defaultValue: '/chat/completions',
  );
  static const String _defaultHttpModel = String.fromEnvironment(
    'LLM_MODEL',
    defaultValue: 'deepseek-ai/DeepSeek-V3.2',
  );
  static const String _defaultHttpApiKey = String.fromEnvironment(
    'LLM_API_KEY',
    defaultValue: '',
  );

  final TextEditingController _promptController = TextEditingController(
    text: '请用中文描述这张照片，并列出3个最确定的视觉事实。',
  );
  final TextEditingController _serverUrlController = TextEditingController(
    text: _buildDefaultServerUrl(),
  );
  final TextEditingController _modelController = TextEditingController(
    text: _defaultHttpModel,
  );

  final InternvlExperimentService _experimentService =
      InternvlExperimentService();

  OnDeviceInternvlProfile? _profile;
  OnDeviceInternvlBackendStatus? _backendStatus;
  OnDeviceInternvlCliDeploymentStatus? _cliDeploymentStatus;
  List<PhotoEntity> _recentPhotos = const <PhotoEntity>[];
  PhotoEntity? _selectedPhoto;
  bool _isLoading = true;
  bool _isTesting = false;
  String? _resolvedSelectedPath;
  String? _selectedPhotoSource;
  String? _responseText;
  String? _rawOutputText;
  String? _runSummaryText;
  String? _errorText;

  static String _buildDefaultServerUrl() {
    final baseUrl = _defaultHttpBaseUrl.trim();
    final apiPath = _defaultHttpApiPath.trim();
    if (baseUrl.isEmpty) {
      return 'http://127.0.0.1:8080/v1/chat/completions';
    }

    if (apiPath.isEmpty) {
      return baseUrl;
    }

    final normalizedBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final normalizedPath = apiPath.startsWith('/') ? apiPath : '/$apiPath';
    return '$normalizedBase$normalizedPath';
  }

  @override
  void initState() {
    super.initState();
    _loadPageData();
  }

  @override
  void dispose() {
    _promptController.dispose();
    _serverUrlController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadPageData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final profile = await OnDeviceInternvlService().probeDeviceProfile();
      final backendStatus = await OnDeviceInternvlService().getBackendStatus();
      final cliDeploymentStatus = await OnDeviceInternvlService().getCliDeploymentStatus();
      final allPhotos = await PhotoService().isar
          .collection<PhotoEntity>()
          .where()
          .sortByTimestampDesc()
          .findAll();
      final photos = allPhotos.take(20).toList(growable: false);

      String? resolvedPath;
      PhotoEntity? selectedPhoto;
      if (photos.isNotEmpty) {
        selectedPhoto = photos.first;
        resolvedPath = await _resolvePhotoPath(selectedPhoto);
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _profile = profile;
        _backendStatus = backendStatus;
        _cliDeploymentStatus = cliDeploymentStatus;
        _recentPhotos = photos;
        _selectedPhoto = selectedPhoto;
        _resolvedSelectedPath = resolvedPath;
        _selectedPhotoSource = selectedPhoto == null ? null : '来自最近照片缓存';
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '初始化实验页失败: $error';
        _isLoading = false;
      });
    }
  }

  Future<String?> _resolvePhotoPath(PhotoEntity photo) async {
    final asset = await AssetEntity.fromId(photo.assetId);
    final file = await asset?.file;
    if (file != null && file.path.isNotEmpty) {
      return file.path;
    }

    if (photo.path.isNotEmpty && File(photo.path).existsSync()) {
      return photo.path;
    }

    return null;
  }

  Future<void> _selectPhoto(PhotoEntity photo) async {
    final resolvedPath = await _resolvePhotoPath(photo);
    if (!mounted) {
      return;
    }

    setState(() {
      _selectedPhoto = photo;
      _resolvedSelectedPath = resolvedPath;
      _selectedPhotoSource = resolvedPath == null ? null : '来自最近照片缓存';
      _responseText = null;
      _rawOutputText = null;
      _runSummaryText = null;
      _errorText = resolvedPath == null ? '无法读取这张照片的实际文件路径' : null;
    });
  }

  Future<void> _pickPhotoFromGallery() async {
    final result = await Navigator.push<VlmPhotoPickerResult>(
      context,
      MaterialPageRoute<VlmPhotoPickerResult>(
        builder: (BuildContext context) => const VlmPhotoPickerPage(),
      ),
    );
    if (!mounted || result == null) {
      return;
    }

    setState(() {
      _selectedPhoto = null;
      _resolvedSelectedPath = result.path;
      _selectedPhotoSource = '来自系统相册选择';
      _responseText = null;
      _rawOutputText = null;
      _runSummaryText = null;
      _errorText = null;
    });
  }

  Future<void> _runCliExperiment() async {
    final resolvedPath = _resolvedSelectedPath;
    final profile = _profile;
    final cliDeploymentStatus = _cliDeploymentStatus;
    if (resolvedPath == null) {
      setState(() {
        _errorText = '请先选择一张可访问的照片';
      });
      return;
    }

    if (cliDeploymentStatus == null || !cliDeploymentStatus.isRunnable) {
      setState(() {
        _errorText = cliDeploymentStatus?.summary ?? '手机侧本地 CLI 尚未部署完整';
      });
      return;
    }

    final prompt = _promptController.text.trim();
    if (prompt.isEmpty) {
      setState(() {
        _errorText = '测试指令不能为空';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _responseText = null;
      _rawOutputText = null;
      _runSummaryText = null;
      _errorText = null;
    });

    try {
      final usedThreads = profile?.recommendedThreads ?? 4;
      final usedContextSize = profile?.recommendedContextSize ?? 2048;
      final result = await OnDeviceInternvlService().runCliExperiment(
        imagePath: resolvedPath,
        prompt: prompt,
        threads: usedThreads,
        contextSize: usedContextSize,
      );

      if (!mounted) {
        return;
      }

      if (result == null) {
        setState(() {
          _errorText = '未拿到 Android 侧 CLI 返回结果';
          _isTesting = false;
        });
        return;
      }

      setState(() {
        _responseText = result.answer.isNotEmpty ? result.answer : result.rawOutput;
        _rawOutputText = result.rawOutput;
        _runSummaryText =
            '本次耗时 ${(result.durationMs / 1000).toStringAsFixed(1)} 秒 · '
            '线程 $usedThreads · 上下文 $usedContextSize · '
            '退出码 ${result.exitCode}';
        _errorText = result.success ? null : 'CLI 执行失败: ${result.error}';
        _isTesting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '本地 CLI 测试失败: $error';
        _isTesting = false;
      });
    }
  }

  Future<void> _runHttpExperiment() async {
    final resolvedPath = _resolvedSelectedPath;
    if (resolvedPath == null) {
      setState(() {
        _errorText = '请先选择一张可访问的照片';
      });
      return;
    }

    final prompt = _promptController.text.trim();
    final serverUrl = _serverUrlController.text.trim();
    final model = _modelController.text.trim();
    if (prompt.isEmpty || serverUrl.isEmpty || model.isEmpty) {
      setState(() {
        _errorText = '服务地址、模型名和测试指令都不能为空';
      });
      return;
    }

    setState(() {
      _isTesting = true;
      _responseText = null;
      _rawOutputText = null;
      _runSummaryText = null;
      _errorText = null;
    });

    try {
      final response = await _experimentService.analyzeImage(
        serverUrl: serverUrl,
        model: model,
        prompt: prompt,
        imagePath: resolvedPath,
        apiKey: _defaultHttpApiKey,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _responseText = response;
        _runSummaryText = '本次通过备用 HTTP 接口完成了一次多模态请求';
        _isTesting = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorText = '测试失败: $error';
        _isTesting = false;
      });
    }
  }

  String _buildRouteSummary() {
    final profile = _profile;
    final cliDeploymentStatus = _cliDeploymentStatus;
    if (profile == null) {
      return '当前无法读取真机画像，但如果手机侧 CLI 已经部署完成，仍可先尝试单图直跑。';
    }

    if (cliDeploymentStatus?.isRunnable == true) {
      return '这台手机已经具备本地 CLI 直跑条件，优先走单图 CLI 测试；HTTP 环回接口仅作为备用联调路径。';
    }

    if (!profile.likelyEnoughRamFor1BQ4) {
      return '这台手机的当前内存余量对 1B Q4 不够稳，最实际路线是继续用外部服务，不建议强上本地多模态。';
    }

    if (!profile.npuAvailableThroughApp) {
      return '这台手机的 RAM 足够尝试 1B Q4；当前 App 还没有 OPPO/MediaTek NPU 通路，优先补齐并部署本地 CLI 文件后再测试。';
    }

    return '这台手机既有余量，也具备 NPU 条件，但从工程性价比看，仍建议先把本地 CLI 直跑路径稳定下来，再决定是否投入厂商 NPU 适配。';
  }

  String _buildFeasibilitySummary() {
    final profile = _profile;
    if (profile == null) {
      return '尚未拿到设备画像，无法判断。';
    }

    if (!profile.likelyEnoughRamFor1BQ4) {
      return '当前结论：不建议直接把 InternVL-3-1B Q4 压到手机本地。瓶颈主要会在 RAM 和连续推理稳定性。';
    }

    if (!profile.likelyEnoughRamForVision) {
      return '当前结论：可以尝试单图、短上下文的 InternVL-3-1B Q4，但应保守设置线程和上下文，避免多轮长对话。';
    }

    return '当前结论：这台手机有现实机会运行 InternVL-3-1B Q4 的单图测试。建议从 1 张图、2048~3072 context、4~6 线程开始。';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('VLM 推理')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildRouteCard(context),
                const SizedBox(height: 16),
                _buildDeviceCard(context),
                const SizedBox(height: 16),
                _buildBackendCard(context),
                const SizedBox(height: 16),
                _buildCliDeploymentCard(context),
                const SizedBox(height: 16),
                _buildServerCard(context),
                const SizedBox(height: 16),
                _buildPhotoPickerCard(context),
                const SizedBox(height: 16),
                _buildPromptCard(context),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _isTesting ? null : _runCliExperiment,
                  icon: _isTesting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow),
                  label: Text(_isTesting ? '推理中...' : '开始手机本地 VLM 推理'),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _isTesting ? null : _runHttpExperiment,
                  icon: const Icon(Icons.cloud_outlined),
                  label: const Text('走备用 HTTP 接口'),
                ),
                const SizedBox(height: 16),
                if (_runSummaryText != null)
                  _buildMessageCard(
                    context,
                    '运行摘要',
                    _runSummaryText!,
                    Theme.of(context).colorScheme.surfaceContainer,
                  ),
                if (_runSummaryText != null) const SizedBox(height: 16),
                if (_errorText != null) _buildMessageCard(context, '错误信息', _errorText!, Colors.red.shade50),
                if (_responseText != null) ...[
                  _buildMessageCard(
                    context,
                    '模型返回',
                    _responseText!,
                    Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                ],
                if (_rawOutputText != null && _rawOutputText!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _buildMessageCard(
                    context,
                    'CLI 原始输出',
                    _rawOutputText!,
                    Theme.of(context).colorScheme.surface,
                  ),
                ],
              ],
            ),
    );
  }

  Widget _buildRouteCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '当前推理模式',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text('手机本地 CLI 直跑（主路径）'),
            const SizedBox(height: 8),
            Text(_buildRouteSummary()),
          ],
        ),
      ),
    );
  }

  Widget _buildDeviceCard(BuildContext context) {
    final profile = _profile;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '设备能力判断',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(profile?.summary ?? '未获取到设备画像'),
            const SizedBox(height: 8),
            if (profile != null) ...[
              Text('总 RAM：${profile.totalRamMb} MB'),
              Text('建议线程：${profile.recommendedThreads}'),
              Text('建议上下文：${profile.recommendedContextSize}'),
              Text('1B Q4 可行性：${profile.likelyEnoughRamFor1BQ4 ? '可尝试' : '风险高'}'),
              Text('视觉余量：${profile.likelyEnoughRamForVision ? '相对充足' : '偏紧'}'),
              Text('App 已接入 NPU 通路：${profile.npuAvailableThroughApp ? '是' : '否'}'),
            ],
            const SizedBox(height: 8),
            Text(_buildFeasibilitySummary()),
          ],
        ),
      ),
    );
  }

  Widget _buildBackendCard(BuildContext context) {
    final backend = _backendStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地后端状态',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text('是否已接入手机本地 VLM 后端：${backend?.supportsDirectOnDeviceInternvl == true ? '是' : '否'}'),
            const SizedBox(height: 8),
            Text(backend?.reason ?? '未知'),
            const SizedBox(height: 8),
            Text('下一步：${backend?.nextStep ?? '未知'}'),
          ],
        ),
      ),
    );
  }

  Widget _buildCliDeploymentCard(BuildContext context) {
    final deployment = _cliDeploymentStatus;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '本地模型部署状态',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(deployment?.summary ?? '尚未读取到 CLI 部署状态'),
            if (deployment != null) ...[
              const SizedBox(height: 8),
              Text('可直接运行：${deployment.isRunnable ? '是' : '否'}'),
              Text('CLI 文件：${deployment.cliExists ? '已就位' : '缺失'}'),
              Text('动态库目录：${deployment.libDirExists ? '已就位' : '缺失'}'),
              Text('主模型：${deployment.modelExists ? '已就位' : '缺失'}'),
              Text('mmproj：${deployment.mmprojExists ? '已就位' : '缺失'}'),
              const SizedBox(height: 8),
              SelectableText('部署目录：${deployment.deployedRoot}'),
              if (deployment.missingItems.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('缺失项：${deployment.missingItems.join('；')}'),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildServerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '备用 HTTP 配置',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '这里保留为备用验证路径。默认会沿用启动 App 时传入的 LLM 配置；只有在你想联调别的 OpenAI 兼容接口时，才需要手动改这里。',
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _serverUrlController,
              decoration: const InputDecoration(
                labelText: '服务地址',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _modelController,
              decoration: const InputDecoration(
                labelText: '模型名',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoPickerCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '待分析图片',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _pickPhotoFromGallery,
                  icon: const Icon(Icons.photo_library_outlined),
                  label: const Text('从相册选择'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _selectedPhotoSource ?? '当前还没有选择图片',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_resolvedSelectedPath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 220,
                  width: double.infinity,
                  child: PathImage(
                    path: _resolvedSelectedPath!,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            else
              Container(
                height: 220,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text('暂无可测试图片'),
              ),
            const SizedBox(height: 12),
            if (_resolvedSelectedPath != null)
              SelectableText(
                '当前文件：$_resolvedSelectedPath',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (_resolvedSelectedPath != null) const SizedBox(height: 12),
            SizedBox(
              height: 96,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _recentPhotos.length,
                separatorBuilder: (_, _) => const SizedBox(width: 12),
                itemBuilder: (context, index) {
                  final photo = _recentPhotos[index];
                  final isSelected = photo.id == _selectedPhoto?.id;
                  return GestureDetector(
                    onTap: () => _selectPhoto(photo),
                    child: Container(
                      width: 96,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isSelected
                              ? Theme.of(context).colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: photo.path.isNotEmpty
                            ? PathImage(path: photo.path, fit: BoxFit.cover)
                            : Container(color: Colors.grey.shade300),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromptCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '提问内容',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _promptController,
              minLines: 4,
              maxLines: 8,
              decoration: const InputDecoration(
                hintText: '输入你希望 VLM 回答的问题，例如：这张图里有什么？画面在表达什么？',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageCard(
    BuildContext context,
    String title,
    String message,
    Color backgroundColor,
  ) {
    return Card(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SelectableText(message),
          ],
        ),
      ),
    );
  }
}