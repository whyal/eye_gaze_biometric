import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
    
    let eyeTrackingManager = EyeTrackingManager()

    override func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {

        // 1️⃣ Register Flutter plugins first
        GeneratedPluginRegistrant.register(with: self)

        // 2️⃣ Get Flutter root controller
        guard let controller = window?.rootViewController as? FlutterViewController else {
            fatalError("rootViewController is not FlutterViewController")
        }

        // 3️⃣ Set up MethodChannel
        let channel = FlutterMethodChannel(
            name: "eye_tracking",
            binaryMessenger: controller.binaryMessenger
        )

        // 4️⃣ Attach channel to EyeTrackingManager
        eyeTrackingManager.attachChannel(channel)

        // 5️⃣ Handle Flutter method calls
        channel.setMethodCallHandler { call, result in
            switch call.method {
            case "start":
                self.eyeTrackingManager.start()
                result(nil)
            case "stop":
                self.eyeTrackingManager.stop()
                result(nil)
            default:
                result(FlutterMethodNotImplemented)
            }
        }

        return super.application(application, didFinishLaunchingWithOptions: launchOptions)
    }
}
