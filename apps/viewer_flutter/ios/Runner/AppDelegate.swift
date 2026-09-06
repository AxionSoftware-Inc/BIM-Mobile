import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var appStorageChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    RenderScenePlaceholderFactory.register(with: engineBridge.pluginRegistry)

    let channel = FlutterMethodChannel(
      name: "tbe/app_storage",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      guard call.method == "getProjectDirectory" else {
        result(FlutterMethodNotImplemented)
        return
      }

      do {
        let support = try FileManager.default.url(
          for: .applicationSupportDirectory,
          in: .userDomainMask,
          appropriateFor: nil,
          create: true
        )
        let directory = support.appendingPathComponent("TabletBIM", isDirectory: true)
        try FileManager.default.createDirectory(
          at: directory,
          withIntermediateDirectories: true,
          attributes: nil
        )
        result(directory.path)
      } catch {
        result(
          FlutterError(
            code: "app_storage_unavailable",
            message: "Unable to create TabletBIM application support directory.",
            details: error.localizedDescription
          )
        )
      }
    }
    appStorageChannel = channel
  }
}
