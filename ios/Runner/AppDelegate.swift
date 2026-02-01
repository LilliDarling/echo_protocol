import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private var protectionView: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(
      name: "com.echo.protocol/screenshot",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { [weak self] (call, result) in
      switch call.method {
      case "enableProtection":
        self?.enableScreenshotProtection()
        result(nil)
      case "disableProtection":
        self?.disableScreenshotProtection()
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    NotificationCenter.default.addObserver(
      self,
      selector: #selector(userDidTakeScreenshot),
      name: UIApplication.userDidTakeScreenshotNotification,
      object: nil
    )

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  @objc func userDidTakeScreenshot() {
    if protectionView != nil {
      let alert = UIAlertController(
        title: "Security Warning",
        message: "Screenshots of sensitive information are not recommended for security reasons.",
        preferredStyle: .alert
      )
      alert.addAction(UIAlertAction(title: "OK", style: .default))
      window?.rootViewController?.present(alert, animated: true)
    }
  }

  private func enableScreenshotProtection() {
    let blurEffect = UIBlurEffect(style: .light)
    let blurView = UIVisualEffectView(effect: blurEffect)
    blurView.frame = UIScreen.main.bounds
    blurView.alpha = 0
    window?.addSubview(blurView)
    protectionView = blurView

    NotificationCenter.default.addObserver(
      forName: UIApplication.willResignActiveNotification,
      object: nil,
      queue: .main
    ) { [weak blurView] _ in
      blurView?.alpha = 1
    }

    NotificationCenter.default.addObserver(
      forName: UIApplication.didBecomeActiveNotification,
      object: nil,
      queue: .main
    ) { [weak blurView] _ in
      blurView?.alpha = 0
    }
  }

  private func disableScreenshotProtection() {
    protectionView?.removeFromSuperview()
    protectionView = nil
  }
}
