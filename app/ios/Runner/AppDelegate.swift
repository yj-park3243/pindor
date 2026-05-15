import UIKit
import Flutter
import FirebaseCore
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate {
    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        FirebaseApp.configure()
        GeneratedPluginRegistrant.register(with: self)

        // Flutter ↔ Native bridge: 앱 아이콘 배지/전달된 알림 초기화
        let controller = window?.rootViewController as? FlutterViewController
        if let controller = controller {
            let channel = FlutterMethodChannel(
                name: "kr.pins/badge",
                binaryMessenger: controller.binaryMessenger
            )
            channel.setMethodCallHandler { (call, result) in
                if call.method == "clearBadge" {
                    if #available(iOS 16.0, *) {
                        UNUserNotificationCenter.current().setBadgeCount(0) { _ in }
                    } else {
                        DispatchQueue.main.async {
                            UIApplication.shared.applicationIconBadgeNumber = 0
                        }
                    }
                    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
                    result(nil)
                } else {
                    result(FlutterMethodNotImplemented)
                }
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
