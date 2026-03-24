import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../models/entity/photo_entity.dart';
import '../../models/vo/semantic_search_models.dart';
import '../../service/semantic_photo_search_service.dart';
import '../../utils/tag_sanitizer.dart';
import '../widgets/fullscreen_photo_viewer.dart';
import '../widgets/path_image.dart';

class AlbumSearchPage extends StatefulWidget {
  const AlbumSearchPage({super.key, required this.initialQuery});

  final String initialQuery;

  @override
  State<AlbumSearchPage> createState() => _AlbumSearchPageState();
}

class _AlbumSearchPageState extends State<AlbumSearchPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _isSearching = false;
  String? _errorMessage;
  SemanticSearchResult? _result;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.initialQuery;
    if (widget.initialQuery.trim().isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _performSearch();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _performSearch() async {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _result = null;
        _errorMessage = null;
      });
      return;
    }

    setState(() {
      _isSearching = true;
      _errorMessage = null;
    });

    try {
      final result = await SemanticPhotoSearchService().search(query);
      if (!mounted) {
        return;
      }
      setState(() {
        _result = result;
        _isSearching = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _isSearching = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(title: const Text('语义搜索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _performSearch(),
              decoration: InputDecoration(
                hintText: '输入时间、地点、人物、场景或排除条件',
                suffixIcon: IconButton(
                  onPressed: _performSearch,
                  icon: const Icon(Icons.search),
                ),
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(18),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (result != null) _buildSummaryCard(result),
          Expanded(
            child: _isSearching
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                ? _buildErrorState()
                : result == null
                ? _buildIdleState()
                : result.photos.isEmpty
                ? _buildEmptyState(result)
                : _buildGrid(result),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(SemanticSearchResult result) {
    final query = result.query;
    final chips = <Widget>[
      _SummaryChip(
        label: query.usedLlm ? 'DeepSeek 已解析' : '本地解析',
        icon: query.usedLlm ? Icons.auto_awesome : Icons.memory_outlined,
      ),
      if (query.includeLocations.isNotEmpty)
        ...query.includeLocations.map(
          (item) => _SummaryChip(label: item, icon: Icons.place_outlined),
        ),
      if (query.includeTags.isNotEmpty)
        ...query.includeTags.map(
          (item) => _SummaryChip(label: item, icon: Icons.sell_outlined),
        ),
      if (query.excludeTags.isNotEmpty)
        ...query.excludeTags.map(
          (item) => _SummaryChip(label: '排除 $item', icon: Icons.block_outlined),
        ),
      if (query.includeOcrTerms.isNotEmpty)
        ...query.includeOcrTerms.map(
          (item) => _SummaryChip(label: '文字:$item', icon: Icons.text_fields),
        ),
      if (query.startTimeMs != null || query.endTimeMs != null)
        _SummaryChip(
          label: _formatDateRange(query),
          icon: Icons.schedule_outlined,
        ),
      if (!query.allowScreenshots)
        const _SummaryChip(
          label: '已排除截图/文档',
          icon: Icons.hide_source_outlined,
        ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '命中 ${result.photos.length} 张，候选 ${result.filteredCandidateCount} / 已分析 ${result.totalAnalyzedPhotos} 张。',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (query.semanticQuery.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '语义意图：${query.semanticQuery}',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
            if (query.negativeSemanticQuery.trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                '负向约束：${query.negativeSemanticQuery}',
                style: TextStyle(color: Colors.grey[700]),
              ),
            ],
            const SizedBox(height: 8),
            Text(
              query.llmConfigured
                  ? (query.usedLlm ? '当前已接入 DeepSeek 解析。' : 'DeepSeek 已配置，但本次回退到了本地解析。')
                  : '当前未检测到 DeepSeek API 配置，正在使用本地解析。',
              style: TextStyle(
                color: query.usedLlm ? Colors.teal[700] : Colors.orange[800],
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            if (chips.isNotEmpty) ...[
              Wrap(spacing: 8, runSpacing: 8, children: chips),
            ],
            const SizedBox(height: 8),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              childrenPadding: EdgeInsets.zero,
              title: const Text(
                '查看 DeepSeek 解析 JSON',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              children: [
                const SizedBox(height: 4),
                SelectableText(
                  query.debugJson,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[800],
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid(SemanticSearchResult result) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.82,
      ),
      itemCount: result.photos.length,
      itemBuilder: (context, index) {
        final photo = result.photos[index];
        final hit = result.hits[photo.id];
        return _SearchPhotoTile(photo: photo, hit: hit);
      },
    );
  }

  Widget _buildIdleState() {
    return const Center(
      child: Text('输入自然语言后开始搜索'),
    );
  }

  Widget _buildEmptyState(SemanticSearchResult result) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          result.usedFallback
              ? '没有找到高置信语义结果，也没有匹配到标签回退结果。'
              : '没有找到符合条件的图片，试试放宽地点、时间或排除条件。',
          textAlign: TextAlign.center,
          style: TextStyle(color: Colors.grey[600], height: 1.5),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 44),
            const SizedBox(height: 12),
            Text(_errorMessage ?? '搜索失败'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: _performSearch,
              child: const Text('重试'),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateRange(SemanticSearchQuery query) {
    final formatter = DateFormat('yyyy.MM.dd');
    final start = query.startTimeMs == null
        ? null
        : formatter.format(
            DateTime.fromMillisecondsSinceEpoch(query.startTimeMs!),
          );
    final end = query.endTimeMs == null
        ? null
        : formatter.format(
            DateTime.fromMillisecondsSinceEpoch(query.endTimeMs!),
          );
    if (start != null && end != null) {
      return '$start - $end';
    }
    return start ?? end ?? '时间不限';
  }
}

class _SearchPhotoTile extends StatelessWidget {
  const _SearchPhotoTile({
    required this.photo,
    required this.hit,
  });

  final PhotoEntity photo;
  final SemanticSearchHit? hit;

  @override
  Widget build(BuildContext context) {
    final tags = TagSanitizer.sanitizeVisualTags(
      photo.aiTags ?? const <String>[],
      maxTags: 2,
    ).join(' · ');
    final reason = [
      ...?hit?.matchedTags,
      ...?hit?.matchedOcrTerms,
    ].take(2).join(' · ');

    final heroTag = 'search-photo-${photo.id}';
    return GestureDetector(
      onTap: () => showFullscreenPhotoViewer(
        context,
        path: photo.path,
        heroTag: heroTag,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              child: PathImage(path: photo.path, fit: BoxFit.cover),
            ),
            if (reason.isNotEmpty || tags.isNotEmpty)
              Positioned(
                left: 6,
                right: 6,
                bottom: 6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    reason.isNotEmpty ? reason : tags,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({
    required this.label,
    required this.icon,
  });

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
