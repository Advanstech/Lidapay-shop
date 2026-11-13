import Flutter
import GoogleMaps
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Restricted Google Maps key for the courier driver pin. Set
    // GOOGLE_MAPS_API_KEY in ios/Flutter/Local.xcconfig (gitignored) or as an
    // Xcode build setting; empty means the tracking card shows coordinates
    // only. Restrict the key in Google Cloud Console before release.
    if let mapsKey = Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String,
       !mapsKey.isEmpty, !mapsKey.contains("$(") {
      GMSServices.provideAPIKey(mapsKey)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
