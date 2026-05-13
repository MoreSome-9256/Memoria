/// 垃圾照片清理提示横幅，用于引导用户处理低价值照片。

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
    final summaries = report.orderedReasonSummaries.take(4).toList(
      growable: false,
    );

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
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
                  '已筛出 ${report.totalCount} 张低价值候选照片',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '这些照片只会从 Memoria 本地数据库中移除，不会删除系统相册原图。',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: Colors.grey[700], fontSize: 12),
          ),
          if (summaries.isNotEmpty) ...[
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: summaries
                    .map(
                      (summary) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Chip(
                          label: Text(summary),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onReview,
                icon: const Icon(Icons.visibility_outlined),
                label: const Text('查看并处理'),
              ),
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
