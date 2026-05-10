import UIKit
import Flutter
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 配置音频会话：使用 playback 类型并允许与其他音频混音 / 降低本应用音量
    // 这样切到微信拍照、来电等场景时本应用可继续在后台播放，不会被强制中断
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.mixWithOthers, .duckOthers]
      )
      try session.setActive(true)
    } catch {
      NSLog("AVAudioSession 设置失败: \(error)")
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
