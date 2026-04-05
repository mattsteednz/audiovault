import Flutter
import UIKit
import GoogleCast

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Initialise Google Cast with the Default Media Receiver.
    let discoveryCriteria = GCKDiscoveryCriteria(applicationID: "CC1AD845")
    let castOptions = GCKCastOptions(discoveryCriteria: discoveryCriteria)
    castOptions.physicalVolumeButtonsWillControlDeviceVolume = true
    GCKCastContext.setSharedInstanceWith(castOptions)
    GCKCastContext.sharedInstance().useDefaultExpandedMediaControls = true

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
