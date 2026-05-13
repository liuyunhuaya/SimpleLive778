import UIKit
import Flutter
import AVFoundation

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // 配置音频会话：使用 playback + mixWithOthers，允许与其他音频混音播放。
    // 这样切到微信拍照、微信语音、来电等场景时本应用不会被强制暂停，
    // 而是由 Dart 侧 audio_session 中断事件回调主动降低本应用音量。
    do {
      let session = AVAudioSession.sharedInstance()
      try session.setCategory(
        .playback,
        mode: .moviePlayback,
        options: [.mixWithOthers]
      )
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      NSLog("AVAudioSession 设置失败: \(error)")
    }
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
