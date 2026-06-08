import 'package:flutter/material.dart';
import 'dart:ui';

import '../../models/chat_message.dart';
import '../../service/chat_service.dart';
import '../../service/photo_service.dart';
import '../../service/semantic_photo_search_service.dart';
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
  final SemanticPhotoSearchService _semanticSearchService =
      SemanticPhotoSearchService();
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
    final query = chatBox.query().order(ChatMessage_.timestampMs).build();
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
      final result = await _semanticSearchService.search(userText);
      final merged = <PhotoEntity>[];
      final seen = <int>{};
      for (final photo in [...result.exactPhotos, ...result.relatedPhotos]) {
        if (seen.add(photo.id)) {
          merged.add(photo);
        }
        if (merged.length >= 15) {
          break;
        }
      }
      return await PhotoService().reconcileAccessiblePhotos(merged);
    } catch (e) {
      debugPrint("语义照片搜索失败: $e");
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
  void _navigateToCreateAndGenerate(
    List<String> photoPaths,
    String topic,
  ) async {
    // 根据路径反向查出实体（因为传给下一页需要实体）
    if (photoPaths.isEmpty) return;
    final store = ObjectBoxService().store;
    final photoBox = store.box<PhotoEntity>();
    final query = photoBox.query(PhotoEntity_.path.oneOf(photoPaths)).build();
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
        title: const Text(
          '记忆助理',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
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
                  itemBuilder: (context, index) =>
                      _buildMessageBubble(_messages[index]),
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
              top: -100,
              left: -50,
              child: Container(
                width: 300,
                height: 300,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x88FFB6C1),
                ),
              ),
            ),
            Positioned(
              top: -20,
              right: -80,
              child: Container(
                width: 250,
                height: 250,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0x77E0B0FF),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    bool isUser = message.sender == MessageSender.user;
    bool hasPhotos =
        message.relatedPhotoPaths != null &&
        message.relatedPhotoPaths!.isNotEmpty;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 8),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.85,
            ),
            decoration: BoxDecoration(
              color: isUser
                  ? const Color.fromARGB(255, 255, 64, 129)
                  : Colors.white.withOpacity(0.9),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(20),
                topRight: const Radius.circular(20),
                bottomLeft: Radius.circular(isUser ? 20 : 0),
                bottomRight: Radius.circular(isUser ? 0 : 20),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (message.text.isNotEmpty)
                  Text(
                    message.text,
                    style: TextStyle(
                      color: isUser ? Colors.white : Colors.black87,
                      fontSize: 15,
                      height: 1.4,
                    ),
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
                label: const Text(
                  "以此回忆生成视频",
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: TextButton.styleFrom(
                  foregroundColor: const Color.fromARGB(255, 255, 64, 129),
                  backgroundColor: Colors.white.withOpacity(0.6),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                ),
              ),
            ),

          if (message.relatedPhotoPaths != null &&
              message.relatedPhotoPaths!.isEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                "（在本地记忆库中没有找到匹配的画面）",
                style: TextStyle(color: Colors.grey, fontSize: 12),
              ),
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
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).padding.bottom + 12,
      ),
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
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100]?.withOpacity(0.7),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 10,
                ),
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
                color: _isLoading
                    ? Colors.grey
                    : const Color.fromARGB(255, 255, 64, 129),
                shape: BoxShape.circle,
              ),
              child: _isLoading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Icon(
                      Icons.send_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
