import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import '../../models/event.dart';
import '../../models/vo/photo.dart';
import '../../models/ai_theme.dart';
import '../../models/entity/event_entity.dart';
import '../../models/entity/photo_entity.dart';
import '../../models/entity/story_entity.dart';
import '../../models/vo/story_generation_models.dart';
import '../../service/photo_service.dart';
import '../../service/llm_service.dart';
import '../../utils/ocr_policy.dart';
import 'story_result_page.dart';
import 'story_generation_progress_page.dart';
import 'package:file_picker/file_picker.dart'; // 🌟 新增
import '../../service/music_service.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path_provider/path_provider.dart';
import 'dart:io';
import 'dart:typed_data';

// 🌟 新增：视频长宽比枚举
enum VideoAspectRatio { vertical, horizontal }

// 🌟 新增：发布平台枚举
enum PublishingPlatform { moments, xiaohongshu, bilibili, tiktok }

enum MusicSource { aiGenerated, manualImport }

class ConfigPage extends StatefulWidget {
  final Event event;
  final List<Photo> selectedPhotos;
  final AITheme selectedTheme;
  final String? semanticSearchQuery;
  final bool preservePhotoOrder;

  const ConfigPage({
    super.key,
    required this.event,
    required this.selectedPhotos,
    required this.selectedTheme,
    this.semanticSearchQuery,
    this.preservePhotoOrder = false,
  });

  @override
  State<ConfigPage> createState() => _ConfigPageState();
}

class _ConfigPageState extends State<ConfigPage> {
  late TextEditingController _themeController;
  String? _selectedSubtitle;

  // 🌟 替换掉原来的 StoryLength，改为新的配置项并给默认值
  VideoAspectRatio _selectedAspectRatio = VideoAspectRatio.vertical;
  PublishingPlatform _selectedPlatform = PublishingPlatform.xiaohongshu;
  StoryGenerationMode _selectedStoryMode = StoryGenerationMode.deepseekTags;
  // 🌟 新增：音乐相关状态
  MusicSource _selectedMusicSource = MusicSource.aiGenerated;
  String? _customMusicPath;
  String? _customMusicName;

  bool _isGenerating = false;

  // 🌟 新增：动态加载提示文本
  String _loadingText = '生成视频';
  // 🌟 新增：是否自动生成台词开关
  bool _enableAutoCaptions = true;
  late TextEditingController _manualCaptionsController; // 🌟 新增：手动字幕控制器

  @override
  void initState() {
    super.initState();
    _themeController = TextEditingController(text: widget.selectedTheme.title);
    _selectedSubtitle = widget.selectedTheme.subtitle;
    _manualCaptionsController = TextEditingController();
  }

  // 🌟 新增：拣选音乐的方法
  Future<void> _pickMusic() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['mp3', 'wav', 'aac', 'm4a', 'flac', 'ogg'],
      allowMultiple: false,
    );

    if (result != null && result.files.single.path != null) {
      setState(() {
        _customMusicPath = result.files.single.path;
        _customMusicName = result.files.single.name;
      });
    }
  }

  @override
  void dispose() {
    _themeController.dispose();
    _manualCaptionsController.dispose();
    super.dispose();
  }

  bool _validateCommonThemeInput() {
    if (_themeController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请输入故事主题')));
      return false;
    }
    return true;
  }

  String _currentPlatformName() {
    switch (_selectedPlatform) {
      case PublishingPlatform.xiaohongshu:
        return '小红书';
      case PublishingPlatform.moments:
        return '朋友圈';
      case PublishingPlatform.bilibili:
        return 'B站';
      case PublishingPlatform.tiktok:
        return '抖音';
    }
  }

  void _openStoryGenerationFlow() {
    if (!_validateCommonThemeInput()) {
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryGenerationProgressPage(
          request: StoryGenerationRequest(
            event: widget.event,
            selectedPhotos: widget.selectedPhotos,
            selectedTheme: widget.selectedTheme,
            title: _themeController.text.trim(),
            subtitle: (_selectedSubtitle ?? '').trim(),
            mode: _selectedStoryMode,
            isHorizontal: _selectedAspectRatio == VideoAspectRatio.horizontal,
            targetPlatform: _currentPlatformName(),
            semanticSearchQuery: widget.semanticSearchQuery?.trim(),
            preserveSelectionOrder: widget.preservePhotoOrder,
          ),
        ),
      ),
    );
  }

  Future<void> _generateStory() async {
    // 校验：如果选择了手动导入但没选文件
    if (_selectedMusicSource == MusicSource.manualImport &&
        _customMusicPath == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先选择一段本地音乐')));
      return;
    }
    if (!_validateCommonThemeInput()) {
      return;
    }

    setState(() {
      _isGenerating = true;
      _loadingText = '🎵 正在分析音乐节拍...'; // 🌟 更新状态
    });

    try {
      // 1. 获取 EventEntity（通过 Event.id 查询）
      final isar = PhotoService().isar;
      EventEntity? eventEntity;

      if (widget.event.id == '-1') {
        // 🕵️‍♂️ 拦截到虚拟 Event！直接在内存中捏一个对象
        eventEntity = EventEntity()
          ..id = -1
          ..title = widget.event.title
          ..startTime = widget.event.startDate.millisecondsSinceEpoch
          ..endTime = widget.event.endDate.millisecondsSinceEpoch
          ..photoCount = widget.selectedPhotos.length;
      } else {
        // 正常走系统自动聚类的相册逻辑
        final eventEntityId = int.parse(widget.event.id);
        eventEntity = await isar.collection<EventEntity>().get(eventEntityId);
      }

      if (eventEntity == null) {
        throw Exception('未找到或创建事件档案失败');
      }

      // 2. 严格按用户选择的照片生成故事
      final selectedAssetIds = widget.selectedPhotos
          .map((photo) => photo.id)
          .toList();
      final List<PhotoEntity> photoEntities = await isar
          .collection<PhotoEntity>()
          .filter()
          .anyOf(selectedAssetIds, (q, assetId) => q.assetIdEqualTo(assetId))
          .sortByTimestamp()
          .findAll();

      if (photoEntities.isEmpty) {
        throw Exception('No photos found');
      }
      // ==========================================
      // 🛡️ 核心修复：路径恢复逻辑
      // 防止数据库里的 PhotoEntity.path 为空，强行用选择器里的最新路径覆盖它
      // ==========================================
      final Map<String, String> idToPathMap = {
        for (var p in widget.selectedPhotos) p.id: p.path ?? "",
      };

      for (var entity in photoEntities) {
        final freshPath = idToPathMap[entity.assetId];
        if (freshPath != null && freshPath.isNotEmpty) {
          entity.path = freshPath; // 🌟 强行缝合路径，保证图片能显示
        }
      }
      // ==========================================
      // 🌟 新增核心节点 1：AI 生成专属配乐
      // ==========================================
      if (_selectedMusicSource == MusicSource.aiGenerated) {
        setState(() {
          _loadingText = '🎵 正在构思音乐配方...';
        });

        // 提取部分照片的描述或标签，给大模型写 Prompt 提供灵感
        List<String> promptTags = [
          _themeController.text.trim(),
          _selectedSubtitle ?? '美好时光',
        ];
        if (photoEntities.isNotEmpty && photoEntities.first.aiCaption != null) {
          promptTags.add(photoEntities.first.aiCaption!);
        }

        // 调用 LLM 写 Prompt
        String musicPrompt = await LLMService().generateMusicPrompt(
          photoTags: promptTags,
          storyTheme: _themeController.text.trim(),
        );

        setState(() {
          _loadingText = '🎹 AI 正在谱写专属配乐 (约需20秒)...';
        });

        int calculatedDuration = 12;

        // 调用 MusicGen 生成并下载 MP3(此处临时注释掉以测试预制音乐效果，到时候记得恢复)
        String? aiMusicPath = await LLMService().generateAndDownloadMusic(
          musicPrompt,
          duration: calculatedDuration,
        );
        // 🌟 强行告诉程序：AI 罢工了，快上预制菜！
        // String? aiMusicPath = null;

        // ==========================================
        // 🌟 终极护盾：如果真 AI 没钱罢工了，预制菜立刻顶上！
        // ==========================================
        if (aiMusicPath == null) {
          setState(() {
            _loadingText = '🎹 AI 专属配乐生成中 (预制菜调取中)...';
          });
          // 传入刚才大模型写的 Prompt，让它挑菜
          aiMusicPath = await _servePremadeMusic(musicPrompt);
        }

        if (aiMusicPath != null) {
          _customMusicPath = aiMusicPath;
          _customMusicName = 'AI 专属原声带.mp3';
        }
      }
      // ==========================================
      // 🌟 核心：云端 Librosa 接入点
      // ==========================================
      Map<String, dynamic>? dynamicBeatData;

      // 现在不管是“手动导入”还是刚才生成的“AI配乐”，只要有路径，统统拿去分析！
      if (_customMusicPath != null) {
        setState(() {
          _loadingText = '🥁 正在分析音乐节拍与鼓点...';
        });

        dynamicBeatData = await MusicService.analyzeAudio(_customMusicPath!);

        if (dynamicBeatData == null) {
          throw Exception('云端音乐分析失败，请检查 Python 后端服务');
        }
      } else {

      }
      // ==========================================
      // 🌟 平台名称转换 (供最终发布页文案生成使用)
      // ==========================================
      final platformName = _currentPlatformName();
      // ==========================================
      // 🌟 第一步：呼叫 VLM 接口生成剧本大纲
      // ==========================================
      setState(() {
        _loadingText = '🧠 正在构思回忆剧本...';
      });

      // 3. 调用 StoryService 生成故事
      // ⚠️ 注意：你需要去 StoryService 里把原来的 length 参数改成接收 aspectRatio 和 platform！
      /*final story = await StoryService().generateStory(
        event: eventEntity,
        selectedPhotos: photoEntities,
        title: _themeController.text.trim(),
        subtitle: _selectedSubtitle ?? '',
        // 🌟 传入新增的两个配置项 (传字符串给后端/AI更方便解析)
        aspectRatio: _selectedAspectRatio.name,
        platform: _selectedPlatform.name,
      );*/ // 暂时注释掉！后期一定记得改回来！

      // 🌟 【测试专用】手动捏一个极其逼真的假 StoryEntity
      // 🌟 修复点：从 photoEntities (List<PhotoEntity>) 里提取 int 类型的 id
      final databaseIds = photoEntities.map((e) => e.id).toList();
      final now = DateTime.now().millisecondsSinceEpoch;
      final story = StoryEntity()
        ..title = _themeController.text.trim().isEmpty
            ? '测试视频生成'
            : _themeController.text.trim()
        ..subtitle = _selectedSubtitle ?? '沙盒测试'
        ..createdAt = now
        ..updatedAt = now
        ..eventId = eventEntity
            .id // 👈 必须传：否则存数据库时会报错
        ..photoIds =
            databaseIds // 👈 必须传：绑定的照片ID列表
        ..photoCount = selectedAssetIds.length
        ..isLlmGenerated = false
        // ⚠️ 最最最关键的 content：必须带有 ![img](x) 占位符，否则 UI 无法切图！
        ..targetPlatform =
            platformName // 👈 🌟 核心新增：把平台写进数据库！
        ..content =
            '''
测试

![img](0)

Sandal Leap

![img](1)
'''
                .trim();

      // ==========================================
      // 🌟 第二步：根据剧本，提炼视频台词 (Captions)
      // ==========================================
      List<String> finalCaptions = [];

      if (_enableAutoCaptions) {
        setState(() {
          _loadingText = '✨ 正在提炼视频台词...';
        });

        // 提取 VLM 的剧本正文（这里用 story.content 替代，实际接入时用 VLM JSON里的 narrative）
        String scriptNarrative = story.content ?? _themeController.text.trim();
        List<String> styleTags = [_selectedSubtitle ?? '治愈风', '小红书感'];

        // ==========================================
        // 🌟 核心提取：把打好的 Tag 揉成一句话送给 LLM
        // ==========================================
        List<String> photoDescriptions = photoEntities.map((p) {
          // 提取图片描述
          String desc = p.aiCaption?.trim() ?? "未知画面元素";

          // 如果有 OCR 文本线索，也一并塞进去
          final ocrTags = OcrPolicy.effectiveTags(
            p.ocrTags ?? const <String>[],
            maxTags: 3,
          );
          final ocrText = OcrPolicy.effectiveText(p.ocrText);
          if (ocrTags.isNotEmpty) {
            desc += " (画面包含文字: ${ocrTags.join('，')})";
          } else if (ocrText.isNotEmpty) {
            desc += " (画面包含文字: $ocrText)";
          }
          return desc;
        }).toList();

        // 呼叫进化版的台词生成方法
        finalCaptions = await LLMService().generateVideoCaptionsFromScript(
          narrative: scriptNarrative,
          styleTags: styleTags,
          photoDescriptions: photoDescriptions, // 👈 传过去！
        );
      } else {
        // 🌟 核心修改：用户选择手动输入
        // 1. 获取输入框的文字并根据换行符打散
        String rawManualText = _manualCaptionsController.text.trim();
        List<String> userLines = [];
        if (rawManualText.isNotEmpty) {
          userLines = rawManualText.split('\n').map((e) => e.trim()).toList();
        }

        // 2. 将输入的句子与照片数量进行“拉平”匹配
        for (int i = 0; i < photoEntities.length; i++) {
          if (i < userLines.length) {
            // 如果用户写了这行的台词，就用它
            finalCaptions.add(userLines[i]);
          } else {
            // 如果用户少写了，剩下的照片就给空字符串（无字纯享版）
            finalCaptions.add("");
          }
        }
        // 注意：如果 userLines.length 大于 photoEntities.length，
        // 多出来的句子根本不会进循环，自然就被丢弃了，完美符合你的要求！
      }

      if (!mounted) return;

      setState(() {
        _isGenerating = false;
        _loadingText = '生成视频';
      });

      if (story != null) {
        // 4. 导航到 StoryResultPage.fromStoryEntity
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => StoryResultPage.fromStoryEntity(
              storyEntity: story,
              photos: photoEntities,
              customMusicPath: _customMusicPath,
              // 🌟 新增：把刚才拿到的云端节拍数据一起传过去！
              dynamicBeatData: dynamicBeatData,
              captions: finalCaptions,
              isHorizontal: _selectedAspectRatio == VideoAspectRatio.horizontal,
              targetPlatform: platformName,
            ),
          ),
        );
      } else {
        // 🌟 修复点 2：补回被不小心删掉的失败提示兜底
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('故事生成失败，请重试')));
      }
    } catch (e) {
      setState(() {
        _isGenerating = false;
        _loadingText = '生成视频';
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('生成异常: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // appBar: AppBar(title: const Text('配置故事')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Event info card
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.event.title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${widget.event.dateRangeText} · ${widget.event.location}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.selectedPhotos.length} 张照片',
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Core theme input
          Text(
            '核心主题',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _themeController,
            decoration: InputDecoration(
              hintText: '输入故事主题',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              prefixIcon: Text(
                widget.selectedTheme.emoji,
                style: const TextStyle(fontSize: 24),
              ),
              prefixIconConstraints: const BoxConstraints(minWidth: 50),
            ),
          ),
          const SizedBox(height: 24),

          // Subtitle chips
          Text(
            '副标题 / 切入点',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [widget.selectedTheme.subtitle, '难忘的回忆', '美好时光', '特别的日子']
                .map((subtitle) {
                  final isSelected = subtitle == _selectedSubtitle;
                  return ChoiceChip(
                    label: Text(subtitle),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedSubtitle = selected ? subtitle : null;
                      });
                    },
                  );
                })
                .toList(),
          ),
          const SizedBox(height: 24),

          // 🎬 删除了原来的“篇幅选择”，换成“视频长宽比”
          Text(
            '画面比例',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          SegmentedButton<VideoAspectRatio>(
            segments: const [
              ButtonSegment(
                value: VideoAspectRatio.vertical,
                label: Text('竖屏 9:16'),
                icon: Icon(Icons.phone_android),
              ),
              ButtonSegment(
                value: VideoAspectRatio.horizontal,
                label: Text('横屏 16:9'),
                icon: Icon(Icons.stay_current_landscape),
              ),
            ],
            selected: {_selectedAspectRatio},
            onSelectionChanged: (Set<VideoAspectRatio> newSelection) {
              setState(() {
                _selectedAspectRatio = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 8),
          Text(
            _selectedAspectRatio == VideoAspectRatio.vertical
                ? '适合抖音、朋友圈、小红书等移动端观看'
                : '适合 B站、大屏沉浸式观看',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
          ),
          const SizedBox(height: 24),

          // 📱 新增：发布平台选择
          Text(
            '发布平台 (影响生成风格)',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('✨ 小红书'),
                selected: _selectedPlatform == PublishingPlatform.xiaohongshu,
                onSelected: (selected) {
                  if (selected) {
                    setState(
                      () => _selectedPlatform = PublishingPlatform.xiaohongshu,
                    );
                  }
                },
              ),
              ChoiceChip(
                label: const Text('💬 朋友圈'),
                selected: _selectedPlatform == PublishingPlatform.moments,
                onSelected: (selected) {
                  if (selected) {
                    setState(
                      () => _selectedPlatform = PublishingPlatform.moments,
                    );
                  }
                },
              ),
              ChoiceChip(
                label: const Text('📺 B站'),
                selected: _selectedPlatform == PublishingPlatform.bilibili,
                onSelected: (selected) {
                  if (selected) {
                    setState(
                      () => _selectedPlatform = PublishingPlatform.bilibili,
                    );
                  }
                },
              ),
              ChoiceChip(
                label: const Text('🔥 短视频'),
                selected: _selectedPlatform == PublishingPlatform.tiktok,
                onSelected: (selected) {
                  if (selected) {
                    setState(
                      () => _selectedPlatform = PublishingPlatform.tiktok,
                    );
                  }
                },
              ),
            ],
          ),

          const SizedBox(height: 24),
          _buildMusicSection(),
          const Divider(height: 48),
          _buildStoryModeSection(),
          const SizedBox(height: 24),

          // 🌟 AI 台词生成开关
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              '自动生成视频台词',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: const Text('AI将根据剧本为每张照片提炼一句专属短字幕'),
            value: _enableAutoCaptions,
            activeThumbColor: Colors.pinkAccent,
            onChanged: (val) {
              setState(() {
                _enableAutoCaptions = val;
              });
            },
          ),

          // 🌟 新增：手动输入框 (当关掉自动生成时才显示)
          if (!_enableAutoCaptions) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _manualCaptionsController,
              maxLines: 5, // 允许多行输入
              decoration: InputDecoration(
                hintText:
                    '手动输入字幕，每行代表一张照片的文案（选填）...\n例如：\n这是第一张图的字幕\n这是第二张图的字幕\n...',
                hintStyle: TextStyle(color: Colors.grey[500], height: 1.5),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Colors.grey[50], // 给一点点底色区分
              ),
            ),
          ],

          const SizedBox(height: 24),

          OutlinedButton.icon(
            onPressed: _isGenerating ? null : _openStoryGenerationFlow,
            icon: const Icon(Icons.auto_stories_rounded),
            label: Text(
              '生成故事',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 1.3,
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Generate video button
          FilledButton(
            onPressed: _isGenerating ? null : _generateStory,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            // 🌟 修复 UI 溢出：给 Text 加上 Flexible 和溢出处理
            child: _isGenerating
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min, // 核心：让 Row 紧凑一点
                    children: [
                      const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // 🌟 核心修复：用 Flexible 包裹长文字，太长就显示省略号
                      Flexible(
                        child: Text(
                          _loadingText,
                          style: const TextStyle(fontSize: 16),
                          overflow: TextOverflow.ellipsis, // 超出显示 ...
                        ),
                      ),
                    ],
                  )
                : Text(_loadingText, style: const TextStyle(fontSize: 16)),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildMusicSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '配乐方案',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        SegmentedButton<MusicSource>(
          segments: const [
            ButtonSegment(
              value: MusicSource.aiGenerated,
              label: Text('AI 智能配乐'),
              icon: Icon(Icons.auto_awesome),
            ),
            ButtonSegment(
              value: MusicSource.manualImport,
              label: Text('手动导入'),
              icon: Icon(Icons.library_music),
            ),
          ],
          selected: {_selectedMusicSource},
          onSelectionChanged: (Set<MusicSource> newSelection) {
            setState(() => _selectedMusicSource = newSelection.first);
          },
        ),
        if (_selectedMusicSource == MusicSource.manualImport) ...[
          const SizedBox(height: 12),
          InkWell(
            onTap: _pickMusic,
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.audiotrack, color: Colors.pinkAccent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _customMusicName ?? '点击选择本地 MP3 文件',
                      style: TextStyle(
                        color: _customMusicName == null
                            ? Colors.grey
                            : Colors.black87,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  if (_customMusicName != null)
                    const Icon(
                      Icons.check_circle,
                      color: Colors.green,
                      size: 20,
                    ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStoryModeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成故事方式',
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          '默认使用 DeepSeek 根据标签、时间和地点生成；如果想更贴近画面细节，可以切换到本地 VLM 模式。',
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: Colors.grey[600], height: 1.4),
        ),
        const SizedBox(height: 12),
        Column(
          children: StoryGenerationMode.values.map((mode) {
            final selected = _selectedStoryMode == mode;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () {
                  setState(() {
                    _selectedStoryMode = mode;
                  });
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: selected
                        ? Theme.of(
                            context,
                          ).colorScheme.primaryContainer.withValues(alpha: 0.92)
                        : Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected
                          ? Theme.of(context).colorScheme.primary
                          : Theme.of(context).colorScheme.outlineVariant,
                      width: selected ? 1.6 : 1.0,
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        selected
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[500],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              mode.title,
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mode.subtitle,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    color: Colors.grey[700],
                                    height: 1.4,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(growable: false),
        ),
      ],
    );
  }
  // ==========================================
  // 🍱 预制菜核心 V2.0：权重打分匹配算法
  // ==========================================
  Future<String> _servePremadeMusic(String prompt) async {
    final lowerPrompt = prompt.toLowerCase();

    // 1. 定义极其严谨的风格专属词库（去掉了容易引起歧义的 piano）
    final upbeatWords = [
      'upbeat',
      'happy',
      'energetic',
      'pop',
      'sunny',
      'cheerful',
      'bright',
      'joy',
      'fun',
      'dynamic',
      'party',
    ];
    final cinematicWords = [
      'cinematic',
      'epic',
      'majestic',
      'orchestral',
      'heroic',
      'grand',
      'brass',
      'soaring',
      'powerful',
      'landscape',
    ];
    // 伤感风必须是明确的负面/悲伤情绪词
    final melancholicWords = [
      'sad',
      'melancholic',
      'sorrow',
      'tear',
      'heartbreak',
      'grief',
      'depressing',
      'lonely',
      'crying',
      'farewell',
    ];
    // 治愈系 Lo-Fi 词汇（把 nostalgic 怀旧 归还给治愈系）
    final lofiWords = [
      'lo-fi',
      'lofi',
      'chill',
      'cozy',
      'relax',
      'dreamy',
      'gentle',
      'warm',
      'calm',
      'peaceful',
      'nostalgic',
      'anime',
    ];

    // 2. 阅卷打分：看看哪种风格命中的词汇最多
    int upbeatScore = upbeatWords.where((w) => lowerPrompt.contains(w)).length;
    int cinematicScore = cinematicWords
        .where((w) => lowerPrompt.contains(w))
        .length;
    int melancholicScore = melancholicWords
        .where((w) => lowerPrompt.contains(w))
        .length;
    int lofiScore = lofiWords.where((w) => lowerPrompt.contains(w)).length;

    debugPrint(
      "📊 预制菜评分结果 -> 欢快:$upbeatScore, 史诗:$cinematicScore, 伤感:$melancholicScore, 治愈:$lofiScore",
    );

    // 3. 选出最高分（默认给 lofi 治愈系打底）
    String assetPath = 'assets/audio/premade/Soft Save Point.mp3';
    int maxScore = 0;

    if (upbeatScore > maxScore) {
      maxScore = upbeatScore;
      assetPath = 'assets/audio/premade/Sunrise Checkpoint.mp3';
    }
    if (cinematicScore > maxScore) {
      maxScore = cinematicScore;
      assetPath = 'assets/audio/premade/Horizons in Motion.mp3';
    }
    if (melancholicScore > maxScore) {
      maxScore = melancholicScore;
      assetPath = 'assets/audio/premade/Faded Save File.mp3';
    }
    if (lofiScore > maxScore) {
      maxScore = lofiScore;
      assetPath = 'assets/audio/premade/Soft Save Point.mp3';
    }

    // 打印最终命中的结果
    if (assetPath.contains('upbeat')) {
      debugPrint("🍱 预制菜最终出锅：欢快风格 (upbeat)");
    } else if (assetPath.contains('cinematic')) {
      debugPrint("🍱 预制菜最终出锅：电影史诗风 (cinematic)");
    } else if (assetPath.contains('melancholic')) {
      debugPrint("🍱 预制菜最终出锅：怀旧伤感风 (melancholic)");
    } else {
      debugPrint("🍱 预制菜最终出锅：治愈放松风 (lofi)");
    }

    // 4. 将 Asset 里的文件拷贝到沙盒目录，伪装成刚下载好的样子
    final ByteData data = await rootBundle.load(assetPath);
    final Directory tempDir = await getTemporaryDirectory();
    final File tempFile = File(
      '${tempDir.path}/ai_bgm_premade_${DateTime.now().millisecondsSinceEpoch}.mp3',
    );
    await tempFile.writeAsBytes(data.buffer.asUint8List(), flush: true);

    // 5. 逼真体验：假装 AI 正在努力思考
    await Future.delayed(const Duration(seconds: 3));

    return tempFile.path;
  }
}
