import 'dart:async';
import 'dart:convert';

import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/model/live_message.dart';

/// 快手直播弹幕参数
class KuaishouDanmakuArgs {
  /// 房间号 / 直播间 liveStreamId
  final String liveStreamId;

  /// 主播 eid（principalId）
  final String principalId;

  /// 主播 caption（用户名）
  final String caption;

  /// websocket token，从 startPlay 接口获取
  final String token;

  /// websocket 服务器地址列表
  final List<String> webSocketUrls;

  KuaishouDanmakuArgs({
    required this.liveStreamId,
    required this.principalId,
    this.caption = "",
    this.token = "",
    this.webSocketUrls = const [],
  });

  @override
  String toString() {
    return jsonEncode({
      "liveStreamId": liveStreamId,
      "principalId": principalId,
      "caption": caption,
      "token": token,
      "webSocketUrls": webSocketUrls,
    });
  }
}

/// 快手直播弹幕
///
/// 注：快手弹幕协议为 protobuf 二进制流（CSWebFeedPushMessage），
/// 签名机制（Last_RTT、AppVersion、AccessToken）变化频繁，且服务端有强校验。
/// 完整协议实现可参考：
///   - https://github.com/OrdinaryRoad-Project/ordinaryroad-barrage-fly
///   - https://github.com/wushuaihua520/BarrageGrab
///
/// 当前为占位实现：连接成功即提示用户，不解析弹幕。
/// 这样用户进入快手直播间不会因弹幕初始化失败崩溃，后续完善 protobuf 解码即可启用。
class KuaishouDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 20 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  WebScoketUtils? webScoketUtils;
  Timer? _hintTimer;

  @override
  Future start(dynamic args) async {
    if (args is! KuaishouDanmakuArgs) {
      onClose?.call("快手弹幕参数无效");
      return;
    }
    // 立即标记为就绪，避免上层一直等待
    onReady?.call();

    // 延迟一点再发出提示，让控件先渲染完成，提示不阻塞 UI
    _hintTimer?.cancel();
    _hintTimer = Timer(const Duration(milliseconds: 800), () {
      try {
        onMessage?.call(LiveMessage(
          type: LiveMessageType.chat,
          userName: "系统提示",
          message: "快手弹幕暂未支持解析，画面与音频正常播放",
          color: LiveMessageColor.white,
        ));
      } catch (e) {
        CoreLog.error(e);
      }
    });
  }

  @override
  void heartbeat() {
    // 占位实现无需心跳
  }

  @override
  Future stop() async {
    _hintTimer?.cancel();
    _hintTimer = null;
    onMessage = null;
    onClose = null;
    try {
      webScoketUtils?.close();
    } catch (e) {
      CoreLog.error(e);
    }
  }
}
