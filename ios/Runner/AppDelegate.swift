import Flutter
import UIKit
import BackgroundTasks

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(
                forTaskWithIdentifier: "com.example.photo_album.background_analysis",
                using: nil
            ) { task in
                BackgroundAnalysisManager.shared.handleBackgroundTask(
                    task as! BGProcessingTask
                )
            }
        }

        let controller = window?.rootViewController as! FlutterViewController
        BackgroundAnalysisManager.shared.register(with: controller.binaryMessenger)

        if #available(iOS 13.0, *) {
            let (taskId, status) = BackgroundAnalysisManager.shared.recoverFromCheckpoint()
            if let taskId = taskId, let status = status {
                let data: [String: Any] = [
                    "taskId": taskId,
                    "status": status,
                    "recovered": true,
                ]
                let channel = FlutterMethodChannel(
                    name: "memoria/analysis",
                    binaryMessenger: controller.binaryMessenger
                )
                channel.invokeMethod("onRecoveredTask", arguments: data)
            }
        }

        GeneratedPluginRegistrant.register(with: self)

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
