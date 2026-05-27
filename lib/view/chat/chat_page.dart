import 'package:flutter/material.dart';
import 'dart:ui';
import 'dart:convert';
import 'package:objectbox/objectbox.dart';

import '../../models/chat_message.dart';
import '../../service/chat_service.dart';
import '../../service/photo_service.dart';
import '../../models/entity/photo_entity.dart';
import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';
import '../widgets/path_image.dart';
import 'select_photos_page.dart'; // 我们马上要建的选图页面

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  List<ChatMessage> _messages = [];
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ChatService _chatService = ChatService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  // 🌟 1. 从数据库读取历史记录
  Future<void> _loadHistory() async {
    final store = ObjectBoxService().store;
    final chatBox = store.box<ChatMessage>();
    final query = chatBox.query()
        .order(ChatMessage_.timestampMs)
        .build();
    query.limit = 200;
    final history = query.find();
    query.close();

    if (history.isEmpty) {
      await _addAndSaveMessage(
        ChatMessage.create(
          text: "你好！我是 Memoria 助手。我可以帮你找照片，或者聊聊你的美好回忆。你想看哪方面的瞬间？",
          sender: MessageSender.ai,
          timestamp: DateTime.now(),
        ),
      );
      return;
    }

    setState(() {
      _messages = history;
    });
    _scrollToBottom();
  }

  // 🌟 统一保存消息的方法（带防崩溃护盾）
  Future<void> _addAndSaveMessage(ChatMessage message) async {
    setState(() {
      _messages.add(message);
    });

    try {
      final store = ObjectBoxService().store;
      final chatBox = store.box<ChatMessage>();
      store.runInTransaction(TxMode.write, () {
        chatBox.put(message);
      });
    } catch (e) {
      debugPrint('❌ 聊天记录保存到数据库失败: $e');
      // 就算数据库坏了，至少别让界面卡死，让用户能继续聊天
    }

    _scrollToBottom();
  }

  Future<List<PhotoEntity>?> _executeLocalSearch(
    String responseText,
    String userText,
  ) async {
    final RegExp searchExp = RegExp(r'<SEARCH>(.*?)</SEARCH>', dotAll: true);
    final match = searchExp.firstMatch(responseText);

    if (match == null) return null;

    try {
      final jsonStr = match.group(1)!.trim();
      final queryParams = jsonDecode(jsonStr);

      final List<dynamic> rawTags = queryParams['tags'] ?? [];

      List<String> tags = rawTags
          .map((t) => t.toString().toLowerCase().trim())
          .map((t) => t.replaceAll(RegExp(r'的照片|照片|图片'), '')) // 清理废话
          .where((t) => t.isNotEmpty)
          .toList();

      final ut = userText.toLowerCase();

      // ==========================================
      // 🌟 1. 年份提取
      // ==========================================
      int? targetYear;
      final now = DateTime.now();

      if (ut.contains('今年'))
        targetYear = now.year;
      else if (ut.contains('去年'))
        targetYear = now.year - 1;
      else if (ut.contains('前年'))
        targetYear = now.year - 2;
      else {
        final yearMatch = RegExp(r'(20\d{2})年').firstMatch(ut);
        if (yearMatch != null) {
          targetYear = int.tryParse(yearMatch.group(1)!);
        }
      }

      // ==========================================
      // 🌟 2. 季节与月份提取
      // ==========================================
      List<int>? targetMonths;

      final springKeys = ['春天', '春日', '春季', '春', 'spring'];
      final summerKeys = ['夏天', '夏日', '夏季', '夏', 'summer'];
      final autumnKeys = ['秋天', '秋日', '秋季', '秋', 'autumn', 'fall'];
      final winterKeys = ['冬天', '冬日', '冬季', '冬', 'winter'];

      final monthRegExp = RegExp(
        r'(1[0-2]|[1-9])月份?|(一|二|三|四|五|六|七|八|九|十|十一|十二)月份?',
      );
      final monthMatch = monthRegExp.firstMatch(ut);

      if (monthMatch != null) {
        String mStr = monthMatch.group(1) ?? monthMatch.group(2) ?? '';
        int? m = int.tryParse(mStr);
        if (m == null) {
          const zhMonths = {
            '一': 1,
            '二': 2,
            '三': 3,
            '四': 4,
            '五': 5,
            '六': 6,
            '七': 7,
            '八': 8,
            '九': 9,
            '十': 10,
            '十一': 11,
            '十二': 12,
          };
          m = zhMonths[mStr];
        }
        if (m != null) targetMonths = [m];
      } else {
        if (springKeys.any(ut.contains)) {
          targetMonths = [3, 4, 5];
        } else if (summerKeys.any(ut.contains)) {
          targetMonths = [6, 7, 8];
        } else if (autumnKeys.any(ut.contains)) {
          targetMonths = [9, 10, 11];
        } else if (winterKeys.any(ut.contains)) {
          targetMonths = [12, 1, 2];
        }
      }

      // ==========================================
      // 🌟 3. 意图纯净度检测（专门猎杀 AI 幻觉）
      // ==========================================
      // 抠掉所有的功能词、时间词
      String pureIntent = ut
          .replaceAll(RegExp(r'帮我|查找|找找|看看|推荐|一下|的|照片|图片|回忆'), '')
          .replaceAll(monthRegExp, '');
      for (var key in [
        ...springKeys,
        ...summerKeys,
        ...autumnKeys,
        ...winterKeys,
      ]) {
        pureIntent = pureIntent.replaceAll(key, '');
      }
      pureIntent = pureIntent.replaceAll(RegExp(r'今年|去年|前年|20\d{2}年'), '');

      // 如果用户仅仅说了时间（比如"冬天的照片"、"一月份照片"），直接清空 AI 瞎编的视觉 tags！
      if (pureIntent.trim().isEmpty) {
        tags.clear();
      } else {
        // 如果用户不仅说了时间，还说了景物（如"冬天海边"），正常清洗时间词，保留视觉词
        for (int i = 0; i < tags.length; i++) {
          for (var key in [
            ...springKeys,
            ...summerKeys,
            ...autumnKeys,
            ...winterKeys,
          ]) {
            tags[i] = tags[i].replaceAll(key, '');
          }
          tags[i] = tags[i].replaceAll(monthRegExp, '');
          tags[i] = tags[i].replaceAll('的', '').trim();
        }
        tags.removeWhere((t) => t.isEmpty);
      }

      // ==========================================
      // 4. ObjectBox 查询（🌟 完美兼容 10 位和 13 位时间戳）
      // ==========================================
      final store = ObjectBoxService().store;
      final photoBox = store.box<PhotoEntity>();

      QueryBuilder<PhotoEntity> queryBuilder;
      if (targetYear != null) {
        final startMillis = DateTime(targetYear, 1, 1).millisecondsSinceEpoch;
        final endMillis = DateTime(
          targetYear,
          12,
          31,
          23,
          59,
          59,
          999,
        ).millisecondsSinceEpoch;

        queryBuilder = photoBox.query(
          PhotoEntity_.timestamp
              .between(startMillis, endMillis)
              .or(
                PhotoEntity_.timestamp.between(
                  startMillis ~/ 1000,
                  endMillis ~/ 1000,
                ),
              ),
        );
      } else {
        queryBuilder = photoBox.query();
      }

      queryBuilder.order(PhotoEntity_.timestamp, flags: Order.descending);
      final query = queryBuilder.build();
      query.limit = 500;
      final candidates = query.find();
      query.close();

      // ==========================================
      // 5. 内存精细过滤
      // ==========================================
      final filtered = candidates.where((p) {
        // 🌟 时空修复：把 10 位秒级时间戳强行放大回毫秒级
        int ts = p.timestamp;
        if (ts < 10000000000) ts *= 1000;
        final photoMonth = DateTime.fromMillisecondsSinceEpoch(ts).month;

        if (targetMonths != null) {
          if (!targetMonths!.contains(photoMonth)) return false;
        }

        if (tags.isNotEmpty) {
          if (p.aiTags == null || p.aiTags!.isEmpty) return false;
          final pTagsLower = p.aiTags!.map((t) => t.toLowerCase()).toList();

          final tagMatched = tags.any((searchTag) {
            return pTagsLower.any((photoTag) {
              if (photoTag.contains(searchTag)) return true;
              if (photoTag.length >= 2 && searchTag.contains(photoTag))
                return true;
              return false;
            });
          });

          if (!tagMatched) return false;
        }
        return true;
      }).toList();

      final output = filtered.take(15).toList(growable: false);
      return await PhotoService().reconcileAccessiblePhotos(output);
    } catch (e) {
      debugPrint("本地解析或搜索失败: $e");
      return null;
    }
  }

  // 🌟 4. 发送逻辑
  void _handleSend() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _isLoading) return;

    final userMsg = ChatMessage.create(
      text: text,
      sender: MessageSender.user,
      timestamp: DateTime.now(),
    );
    await _addAndSaveMessage(userMsg);

    _controller.clear();
    setState(() => _isLoading = true);

    final rawResponse = await _chatService.sendMessage(text, _messages);
    final foundPhotos = await _executeLocalSearch(rawResponse, text);

    final cleanText = rawResponse
        .replaceAll(RegExp(r'<SEARCH>.*?</SEARCH>', dotAll: true), '')
        .trim();

    if (mounted) {
      final aiMsg = ChatMessage.create(
        text: cleanText,
        sender: MessageSender.ai,
        timestamp: DateTime.now(),
        // 关键修复：统一存路径 String
        relatedPhotoPaths: foundPhotos?.map((p) => p.path).toList(),
        searchTopic: text,
      );

      await _addAndSaveMessage(aiMsg);
      setState(() => _isLoading = false);
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // 🌟 5. 跳转到二次确认页的逻辑
  void _navigateToCreateAndGenerate(List<String> photoPaths, String topic) async {
    // 根据路径反向查出实体（因为传给下一页需要实体）
    if (photoPaths.isEmpty) return;
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final query = photoBox.query(
      PhotoEntity_.path.oneOf(photoPaths),
    ).build();
    final photos = query.find();
    query.close();

    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SelectPhotosPage(
          photos: photos,
          topic: topic.isNotEmpty ? topic : "我的瞬间",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('记忆助理', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white.withOpacity(0.5),
        elevation: 0,
        centerTitle: true,
        flexibleSpace: ClipRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: Colors.transparent),
          ),
        ),
      ),
      body: Stack(
        children: [
          _buildAmbientBackground(),
          Column(
            children: [
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 110, 16, 20),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) => _buildMessageBubble(_messages[index]),
                ),
              ),
              _buildInputArea(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAmbientBackground() {
    return Container(
      color: const Color(0xFFFAFAFA),
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 90, sigmaY: 90),
        child: Stack(
          children: [
            Positioned(
              top: -100, left: -50,
              child: Container(width: 300, height: 300, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x88FFB6C1))),
            ),
            Positioned(
              top: -20, right: -80,
              child: Container(width: 250, height: 250, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x77E0B0FF))),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    bool isUser = message.sender == MessageSender.user;
    bool hasPhotos = message.relatedPhotoPaths != null && message.relatedPhotoPaths!.isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.85),
            decoration: BoxDecoration(
              color: isUser ? const Color.fromARGB(255, 255, 64, 129) : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 0),
                bottomRight: Radius.circular(isUser ? 0 : 20),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.text.isNotEmpty)
                  Text(
                    message.text,
                    style: TextStyle(color: isUser ? Colors.white : Colors.black87, fontSize: 15, height: 1.4),
                  ),
                if (hasPhotos) ...[
                  const SizedBox(height: 12),
                  // 统一传路径去渲染
                  _buildPhotoHorizontalList(message.relatedPhotoPaths!),
                ],
              ],
            ),
          ),

          if (hasPhotos && !isUser)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 8),
              child: TextButton.icon(
                onPressed: () => _navigateToCreateAndGenerate(
                  message.relatedPhotoPaths!,
                  message.searchTopic ?? "我的瞬间",
                ),
                icon: const Icon(Icons.movie_creation_outlined, size: 18),
                label: const Text("以此回忆生成视频", style: TextStyle(fontWeight: FontWeight.bold)),
                style: TextButton.styleFrom(
                  foregroundColor: const Color.fromARGB(255, 255, 64, 129),
                  backgroundColor: Colors.white.withOpacity(0.6),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ),

          if (message.relatedPhotoPaths != null && message.relatedPhotoPaths!.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(8)),
              child: const Text("（在本地记忆库中没有找到匹配的画面）", style: TextStyle(color: Colors.grey, fontSize: 12)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPhotoHorizontalList(List<String> photoPaths) {
    return SizedBox(
      height: 150, // 稍微改低一点横向高度，显得更精致
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: photoPaths.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: 3 / 4,
              child: PathImage(path: photoPaths[index], fit: BoxFit.cover),
            ),
          );
        },
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.9),
        border: Border(top: BorderSide(color: Colors.grey.withOpacity(0.1))),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              decoration: InputDecoration(
                hintText: "描述你想找的回忆...",
                hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(25), borderSide: BorderSide.none),
                filled: true,
                fillColor: Colors.grey[100]?.withOpacity(0.7),
                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              ),
              onSubmitted: (_) => _handleSend(),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: _isLoading ? null : _handleSend,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isLoading ? Colors.grey : const Color.fromARGB(255, 255, 64, 129),
                shape: BoxShape.circle,
              ),
              child: _isLoading 
                ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Icon(Icons.send_rounded, color: Colors.white, size: 22),
            ),
          ),
        ],
      ),
    );
  }
}