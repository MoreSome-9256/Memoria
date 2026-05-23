import Foundation
import Flutter
import UIKit
import BackgroundTasks

@objc class BackgroundAnalysisManager: NSObject {
    static let shared = BackgroundAnalysisManager()

    private let methodChannelName = "memoria/analysis"
    private let eventChannelName = "memoria/analysis_progress"
    private let taskIdentifier = "com.example.photo_album.background_analysis"

    private var eventSink: FlutterEventSink?
    private var activeTaskId: String?
    private var isRunning = false
    private var shouldCancel = false
    private var shouldPause = false

    private var pendingImages: [[String: String?]] = []
    private var completedCount = 0
    private var failedCount = 0
    private var totalCount = 0

    private struct TaskCheckpoint: Codable {
        let taskId: String
        let completedCount: Int
        let failedCount: Int
        let totalCount: Int
        let imageIds: [String]
        let status: String
        let updatedAt: TimeInterval
    }

    private var checkpointURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent("analysis_checkpoint.json")
    }

    func register(with messenger: FlutterBinaryMessenger) {
        let methodChannel = FlutterMethodChannel(name: methodChannelName, binaryMessenger: messenger)
        let eventChannel = FlutterEventChannel(name: eventChannelName, binaryMessenger: messenger)

        methodChannel.setMethodCallHandler { [weak self] call, result in
            self?.handleMethodCall(call, result: result)
        }

        eventChannel.setStreamHandler { [weak self] _ -> FlutterEventSink? in
            return { event in self?.eventSink = event as? FlutterEventSink }
        }
    }

    private func handleMethodCall(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "enqueueImages":
            let args = call.arguments as? [String: Any]
            let taskId = args?["taskId"] as? String ?? ""
            let images = args?["images"] as? [[String: String?]] ?? []
            enqueueImages(taskId: taskId, images: images)
            result(true)

        case "startAnalysis":
            let taskId = call.arguments as? [String: Any]??
            startAnalysis(taskId: taskId ?? "")
            result(true)

        case "pauseAnalysis":
            shouldPause = true
            result(true)

        case "resumeAnalysis":
            shouldPause = false
            result(true)

        case "cancelAnalysis":
            shouldCancel = true
            shouldPause = false
            result(true)

        case "getState":
            result(getState())

        case "getUnfinishedTasks":
            result(getUnfinishedTasks())

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    func registerBackgroundTask() {
        BGTaskScheduler.shared.register(forTaskWithIdentifier: taskIdentifier, using: nil) { [weak self] task in
            self?.handleBackgroundTask(task as! BGProcessingTask)
        }
    }

    func scheduleBackgroundTask() {
        let request = BGProcessingTaskRequest(identifier: taskIdentifier)
        request.requiresNetworkConnectivity = false
        request.requiresExternalPower = false
        request.earliestBeginDate = Date(timeIntervalSinceNow: 1)

        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            print("Failed to schedule background task: \(error)")
        }
    }

    private func enqueueImages(taskId: String, images: [[String: String?]]) {
        activeTaskId = taskId
        pendingImages = images
        totalCount = images.count
        completedCount = 0
        failedCount = 0
        shouldCancel = false
        shouldPause = false
        saveCheckpoint(status: "pending")
    }

    private func startAnalysis(taskId: String) {
        guard let _ = activeTaskId, !isRunning else { return }
        isRunning = true
        saveCheckpoint(status: "running")
        scheduleBackgroundTask()
        sendProgress(status: "running")
        processNextImage()
    }

    private func processNextImage() {
        guard isRunning, !shouldCancel else {
            finishAnalysis()
            return
        }

        if shouldPause {
            saveCheckpoint(status: "paused")
            sendProgress(status: "paused")
            return
        }

        guard !pendingImages.isEmpty else {
            finishAnalysis()
            return
        }

        let image = pendingImages.removeFirst()
        let imageId = image["imageId"] ?? ""
        let assetId = image["assetId"]

        sendProgress(status: "running", currentItemId: imageId)

        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }

            let result = self.processImage(imageId: imageId, assetId: assetId)
            DispatchQueue.main.async {
                if result {
                    self.completedCount += 1
                } else {
                    self.failedCount += 1
                }
                self.saveCheckpoint(status: "running")
                self.sendImageResult(imageId: imageId, success: result)
                self.processNextImage()
            }
        }
    }

    private func processImage(imageId: String, assetId: String?) -> Bool {
        guard let assetId = assetId else { return false }

        let fetchResult = PHAsset.fetchAssets(withLocalIdentifiers: [assetId], options: nil)
        guard let asset = fetchResult.firstObject else { return false }

        let options = PHImageRequestOptions()
        options.isSynchronous = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast

        var imageData: Data?
        PHImageManager.default().requestImageDataAndOrientation(
            for: asset,
            options: options
        ) { data, _, _, _ in
            imageData = data
        }

        return imageData != nil
    }

    private func finishAnalysis() {
        isRunning = false
        let status = shouldCancel ? "cancelled" : (failedCount > 0 ? "completed_with_errors" : "completed")
        saveCheckpoint(status: status)
        sendProgress(status: status)
    }

    private func sendProgress(status: String, currentItemId: String? = nil) {
        let data: [String: Any] = [
            "taskId": activeTaskId ?? "",
            "totalCount": totalCount,
            "completedCount": completedCount,
            "failedCount": failedCount,
            "currentItemId": currentItemId ?? "",
            "percent": totalCount > 0 ? Double(completedCount + failedCount) / Double(totalCount) : 0,
            "status": status,
        ]
        eventSink?(data)
        NotificationCenter.default.post(name: .analysisProgressUpdated, object: data)
    }

    private func sendImageResult(imageId: String, success: Bool) {
        let data: [String: Any] = [
            "imageId": imageId,
            "status": success ? "completed" : "failed",
            "taskId": activeTaskId ?? "",
        ]
        eventSink?(data)
    }

    private func saveCheckpoint(status: String) {
        guard let taskId = activeTaskId else { return }
        let checkpoint = TaskCheckpoint(
            taskId: taskId,
            completedCount: completedCount,
            failedCount: failedCount,
            totalCount: totalCount,
            imageIds: pendingImages.compactMap { $0["imageId"] },
            status: status,
            updatedAt: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(checkpoint) {
            try? data.write(to: checkpointURL)
        }
    }

    private func getState() -> [String: Any]? {
        guard let data = try? Data(contentsOf: checkpointURL),
              let checkpoint = try? JSONDecoder().decode(TaskCheckpoint.self, from: data) else {
            return nil
        }
        return [
            "taskId": checkpoint.taskId,
            "totalCount": checkpoint.totalCount,
            "completedCount": checkpoint.completedCount,
            "failedCount": checkpoint.failedCount,
            "percent": checkpoint.totalCount > 0
                ? Double(checkpoint.completedCount + checkpoint.failedCount) / Double(checkpoint.totalCount)
                : 0,
            "status": checkpoint.status,
        ]
    }

    private func getUnfinishedTasks() -> [[String: Any]] {
        guard let data = try? Data(contentsOf: checkpointURL),
              let checkpoint = try? JSONDecoder().decode(TaskCheckpoint.self, from: data) else {
            return []
        }
        let unfinished = ["pending", "running", "paused"]
        guard unfinished.contains(checkpoint.status) else { return [] }
        return [[
            "taskId": checkpoint.taskId,
            "status": checkpoint.status,
            "totalCount": checkpoint.totalCount,
            "completedCount": checkpoint.completedCount,
            "failedCount": checkpoint.failedCount,
        ]]
    }

    func handleBackgroundTask(_ task: BGProcessingTask) {
        guard let taskId = activeTaskId, isRunning else {
            task.setTaskCompleted(success: false)
            return
        }

        scheduleBackgroundTask()

        task.expirationHandler = { [weak self] in
            self?.saveCheckpoint(status: "paused")
            self?.isRunning = false
        }

        processNextImage()
        task.setTaskCompleted(success: true)
    }

    func recoverFromCheckpoint() -> (taskId: String?, status: String?) {
        guard let data = try? Data(contentsOf: checkpointURL),
              let checkpoint = try? JSONDecoder().decode(TaskCheckpoint.self, from: data) else {
            return (nil, nil)
        }
        activeTaskId = checkpoint.taskId
        totalCount = checkpoint.totalCount
        completedCount = checkpoint.completedCount
        failedCount = checkpoint.failedCount
        return (checkpoint.taskId, checkpoint.status)
    }
}

extension Notification.Name {
    static let analysisProgressUpdated = Notification.Name("analysisProgressUpdated")
}
