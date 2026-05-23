import '../../objectbox.g.dart';
import '../../storage/objectbox/objectbox_service.dart';
import 'analysis_task_entity.dart';
import 'analysis_image_entity.dart';
import 'analysis_types.dart';

class AnalysisRepository {
  final ObjectBoxService _objectBox;

  AnalysisRepository({ObjectBoxService? objectBoxService})
    : _objectBox = objectBoxService ?? ObjectBoxService();

  Box<AnalysisTaskEntity> get _taskBox => _objectBox.store.box<AnalysisTaskEntity>();
  Box<AnalysisImageEntity> get _imageBox => _objectBox.store.box<AnalysisImageEntity>();

  AnalysisTaskEntity createTask(String taskId, List<String> itemIds) {
    final task = AnalysisTaskEntity(
      taskId: taskId,
      status: AnalysisTaskStatus.pending.index,
      totalCount: itemIds.length,
    );
    _taskBox.put(task);

    final images = <AnalysisImageEntity>[
      for (var i = 0; i < itemIds.length; i++)
        AnalysisImageEntity(
          taskId: taskId,
          imageId: itemIds[i],
          sortOrder: i,
        ),
    ];
    if (images.isNotEmpty) {
      _imageBox.putMany(images);
    }
    return task;
  }

  AnalysisTaskEntity? getTask(String taskId) {
    final q = _taskBox.query(AnalysisTaskEntity_.taskId.equals(taskId)).build();
    try {
      return q.findFirst();
    } finally {
      q.close();
    }
  }

  List<AnalysisTaskEntity> getUnfinishedTasks() {
    final q = _taskBox
        .query(
          AnalysisTaskEntity_.status
              .equals(AnalysisTaskStatus.pending.index)
              .or(AnalysisTaskEntity_.status.equals(AnalysisTaskStatus.running.index))
              .or(AnalysisTaskEntity_.status.equals(AnalysisTaskStatus.paused.index)),
        )
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  void updateTaskStatus(String taskId, AnalysisTaskStatus newStatus, {String? error}) {
    final task = getTask(taskId);
    if (task == null) return;
    task.taskStatus = newStatus;
    task.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    if (error != null) task.errorMessage = error;
    _taskBox.put(task);
  }

  void updateTaskProgress(String taskId, {int? completed, int? failed, String? currentItem}) {
    final task = getTask(taskId);
    if (task == null) return;
    if (completed != null) task.completedCount = completed;
    if (failed != null) task.failedCount = failed;
    if (currentItem != null) task.currentItemId = currentItem;
    task.percent = task.totalCount > 0
        ? (task.completedCount + task.failedCount) / task.totalCount
        : 0;
    task.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    _taskBox.put(task);
  }

  void updateImageStatus(String imageId, ImageJobStatus status, {String? resultJson, String? resultPath, String? error}) {
    final q = _imageBox.query(AnalysisImageEntity_.imageId.equals(imageId)).build();
    try {
      final img = q.findFirst();
      if (img == null) return;
      img.jobStatus = status;
      img.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
      if (resultJson != null) img.resultJson = resultJson;
      if (resultPath != null) img.resultPath = resultPath;
      if (error != null) img.errorMessage = error;
      _imageBox.put(img);
    } finally {
      q.close();
    }
  }

  List<AnalysisImageEntity> getTaskImages(String taskId) {
    final q = _imageBox
        .query(AnalysisImageEntity_.taskId.equals(taskId))
        .order(AnalysisImageEntity_.sortOrder)
        .build();
    try {
      return q.find();
    } finally {
      q.close();
    }
  }

  List<AnalysisImageEntity> getPendingImages(String taskId, {int limit = 5}) {
    final q = _imageBox
        .query(
          AnalysisImageEntity_.taskId
              .equals(taskId)
              .and(AnalysisImageEntity_.status.equals(ImageJobStatus.pending.index)),
        )
        .order(AnalysisImageEntity_.sortOrder)
        .build();
    try {
      final all = q.find();
      if (all.length <= limit) return all;
      return all.sublist(0, limit);
    } finally {
      q.close();
    }
  }

  void markTaskResult(String taskId, String resultJson) {
    final task = getTask(taskId);
    if (task == null) return;
    task.resultJson = resultJson;
    task.updatedAtMs = DateTime.now().millisecondsSinceEpoch;
    _taskBox.put(task);
  }

  void deleteTask(String taskId) {
    final task = getTask(taskId);
    if (task != null) _taskBox.remove(task.id);
    final q = _imageBox.query(AnalysisImageEntity_.taskId.equals(taskId)).build();
    try {
      final ids = q.findIds();
      if (ids.isNotEmpty) _imageBox.removeMany(ids);
    } finally {
      q.close();
    }
  }
}
