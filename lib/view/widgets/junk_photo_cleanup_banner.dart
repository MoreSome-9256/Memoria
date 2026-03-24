import 'package:flutter/material.dart';

import '../../service/junk_photo_filter_service.dart';

class JunkPhotoCleanupBanner extends StatelessWidget {
  const JunkPhotoCleanupBanner({
    super.key,
    required this.report,
    required this.onReview,
    required this.onDismiss,
  });

  final JunkPhotoCleanupReport report;
  final VoidCallback onReview;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final summaries = report.orderedReasonSummaries.take(4).toList(growable: false);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cleaning_services_outlined,
                size: 18,
                color: Colors.orange,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '已筛出 ${report.totalCount} 张低价值照片',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '系统已挑出这些低质量图片，你可以选择是否从本地数据库中删除对应记录。不会删除系统相册原图。',
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          if (summaries.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: summaries
                  .map(
                    (summary) => Chip(
                      label: Text(summary),
                      visualDensity: VisualDensity.compact,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              FilledButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('查看并处理'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: onDismiss,
                child: const Text('忽略'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
