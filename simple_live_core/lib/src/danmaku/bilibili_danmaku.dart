import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:brotli/brotli.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/convert_helper.dart';
import 'package:simple_live_core/src/common/web_socket_util.dart';

import '../common/binary_writer.dart';

class BiliBiliDanmakuArgs {
  final int roomId;
  final String token;
  final String buvid;
  final String serverHost;
  final int uid;
  final String cookie;
  BiliBiliDanmakuArgs({
    required this.roomId,
    required this.token,
    required this.serverHost,
    required this.buvid,
    required this.uid,
    required this.cookie,
  });
  @override
  String toString() {
    return json.encode({
      "roomId": roomId,
      "token": token,
      "serverHost": serverHost,
      "buvid": buvid,
      "uid": uid,
      "cookie": cookie,
    });
  }
}

class BiliBiliDanmaku implements LiveDanmaku {
  @override
  int heartbeatTime = 60 * 1000;

  @override
  Function(LiveMessage msg)? onMessage;
  @override
  Function(String msg)? onClose;
  @override
  Function()? onReady;

  //String serverUrl = "wss://broadcastlv.chat.bilibili.com/sub";

  WebScoketUtils? webScoketUtils;
  late BiliBiliDanmakuArgs danmakuArgs;
  @override
  Future start(dynamic args) async {
    danmakuArgs = args as BiliBiliDanmakuArgs;

    // ===== B 站弹幕 WS 连接策略（参考 blivedm 实现）=====
    //
    // 关键点（之前 iOS 版踩坑总结）：
    // 1. 端口必须用 443，**不要**用 2243 这类非标端口。
    //    iOS App Transport Security + 系统 TLS 校验对非标端口的 SNI/证书更严格，
    //    `xxx-comet.chat.bilibili.com:2243` 在 iOS 上几乎必握手失败。
    // 2. 优先用官方主域 `broadcastlv.chat.bilibili.com`，它持有 bilibili 主通配证书；
    //    `host_list` 接口返回的 CDN host 部分证书 SNI 在 iOS 上偶发不匹配。
    //    （host_list 仍作为备选，由 args.serverHost 传入第一个）
    // 3. WS 握手**不要**带 Cookie / Origin / User-Agent 等 header。
    //    blivedm 验证：B 站弹幕认证完全靠 joinRoom 数据包里的 `key` (token) 字段。
    //    带 Cookie 反而会让 iOS 端把 WS 升级请求当成"带 credentials"的请求，
    //    触发更严的证书与 ATS 校验，导致 HandshakeException。
    // 4. **不要**因 cookie 缺失就在 iOS 端直接 return。
    //    B 站弹幕游客模式 (uid=0) 同样可用，旧代码在 iOS 端强制要求 SESSDATA
    //    实际上把已登录用户也拦在了 TLS 握手之前的判断里——这是误判。

    final officialHost = "broadcastlv.chat.bilibili.com";
    final argsHost = args.serverHost.isNotEmpty
        ? args.serverHost.split(':').first
        : officialHost;

    String buildUrl(String host) => "wss://$host:443/sub";

    // 主连接优先官方主域，备用走 host_list 返回的服务器
    final wsUrl = buildUrl(officialHost);
    final backupUrl = argsHost == officialHost ? buildUrl(argsHost) : buildUrl(argsHost);

    // iOS 端兜底：对 bilibili 系域名放行 badCertificate（仅限 bilibili，
    // 不影响其他域名安全性）。Windows / Android 默认不需要 customClient。
    HttpClient? customClient;
    if (Platform.isIOS) {
      customClient = HttpClient()
        ..badCertificateCallback = (cert, host, port) {
          return host.endsWith(".bilibili.com") ||
              host.endsWith(".bilivideo.com") ||
              host.endsWith(".bilivideo.cn") ||
              host.endsWith(".biliapi.net") ||
              host.endsWith(".biliapi.com");
        };
    }

    webScoketUtils = WebScoketUtils(
      url: wsUrl,
      backupUrl: backupUrl,
      heartBeatTime: heartbeatTime,
      // headers 留空：B 站弹幕 WS 握手不需要 Cookie/UA/Origin
      customClient: customClient,
      onMessage: (e) {
        decodeMessage(e);
      },
      onReady: () {
        onReady?.call();
        joinRoom(danmakuArgs);
      },
      onHeartBeat: () {
        heartbeat();
      },
      onReconnect: () {
        onClose?.call("与服务器断开连接，正在尝试重连");
      },
      onClose: (e) {
        var errorMsg = e.toString();
        if (errorMsg.contains("HandshakeException")) {
          onClose?.call("弹幕连接失败：TLS/SSL 握手失败。\n请检查网络连接或系统时间是否正确。");
        } else if (errorMsg.contains("Connection refused")) {
          onClose?.call("弹幕连接失败：服务器连接被拒绝。\n请检查网络连接。");
        } else if (errorMsg.contains("SocketException") ||
            errorMsg.contains("Connection closed")) {
          onClose?.call("弹幕连接失败：网络连接中断。\n请检查网络连接。");
        } else if (errorMsg.contains("401") || errorMsg.contains("403")) {
          onClose?.call("弹幕连接失败：身份验证失败。\nCookie 可能已过期，请重新登录B站账号。");
        } else if (errorMsg.contains("WebSocketException")) {
          onClose?.call("弹幕连接失败：WebSocket 连接异常。\n请检查网络连接。");
        } else if (errorMsg.contains("FormatException")) {
          onClose?.call("弹幕连接失败：数据格式异常。\n请检查网络连接。");
        } else {
          onClose?.call("弹幕服务器连接失败：$errorMsg");
        }
      },
    );
    webScoketUtils?.connect();
  }

  void joinRoom(BiliBiliDanmakuArgs args) {
    // 不输出控制台日志
    
    var joinData = encodeData(
      json.encode({
        "uid": args.uid,
        "roomid": args.roomId,
        "protover": 3,
        "buvid": args.buvid,
        "platform": "web",
        "type": 2,
        "key": args.token,
      }),
      7,
    );
    webScoketUtils?.sendMessage(joinData);
  }

  @override
  void heartbeat() {
    // 不输出控制台日志
    webScoketUtils?.sendMessage(encodeData(
      "",
      2,
    ));
  }

  @override
  Future stop() async {
    onMessage = null;
    onClose = null;
    webScoketUtils?.close();
  }

  List<int> encodeData(String msg, int action) {
    var data = utf8.encode(msg);
    //头部长度固定16
    var length = data.length + 16;
    var buffer = Uint8List(length);

    var writer = BinaryWriter([]);

    //数据包长度
    writer.writeInt(buffer.length, 4);
    //数据包头部长度,固定16
    writer.writeInt(16, 2);

    //协议版本，0=JSON,1=Int32,2=Buffer
    writer.writeInt(0, 2);

    //操作类型
    writer.writeInt(action, 4);

    //数据包头部长度,固定1

    writer.writeInt(1, 4);

    writer.writeBytes(data);

    return writer.buffer;
  }

  void decodeMessage(List<int> data) {
    try {
      var message = Uint8List.fromList(data);
      //协议版本。0为JSON，可以直接解析；1为房间人气值,Body为4位Int32；2为压缩过Buffer，需要解压再处理
      int protocolVersion = readInt(message, 6, 2);
      //操作类型。3=心跳回应，内容为房间人气值；5=通知，弹幕、广播等全部信息；8=进房回应，空
      int operation = readInt(message, 8, 4);
      //内容
      var body = Uint8List.fromList(data.skip(16).toList());
      if (operation == 3) {
        var online = readInt(body, 0, 4);

        onMessage?.call(
          LiveMessage(
            type: LiveMessageType.online,
            data: online,
            color: LiveMessageColor.white,
            message: "",
            userName: "",
          ),
        );
      } else if (operation == 5) {
        var text = "";
        if (protocolVersion == 2) {
          body = Uint8List.fromList(zlib.decode(body));
        } else if (protocolVersion == 3) {
          // protover 3使用brotli压缩
          try {
            body = Uint8List.fromList(brotli.decode(body));
          } catch (e) {
            // Brotli解码失败，不输出日志
            return;
          }
        }
        
        text = utf8.decode(body, allowMalformed: true);
        var group =
            text.split(RegExp(r"[\x00-\x1f]+", unicode: true, multiLine: true));
        for (var item
            in group.where((x) => x.length > 2 && x.startsWith('{'))) {
          parseMessage(item);
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  void parseMessage(String jsonMessage) {
    try {
      var obj = json.decode(jsonMessage);
      var cmd = obj["cmd"].toString();
      if (cmd.contains("DANMU_MSG")) {
        if (obj["info"] != null && obj["info"].length != 0) {
          var message = obj["info"][1].toString();
          var color = asT<int?>(obj["info"][0][3]) ?? 0;
          if (obj["info"][2] != null && obj["info"][2].length != 0) {
            var username = obj["info"][2][1].toString();
            var liveMsg = LiveMessage(
              type: LiveMessageType.chat,
              userName: username,
              message: message,
              color: color == 0
                  ? LiveMessageColor.white
                  : LiveMessageColor.numberToColor(color),
            );
            onMessage?.call(liveMsg);
          }
        }
      } else if (cmd == "SUPER_CHAT_MESSAGE") {
        if (obj["data"] == null) {
          return;
        }
        LiveSuperChatMessage sc = LiveSuperChatMessage(
          backgroundBottomColor:
              obj["data"]["background_bottom_color"].toString(),
          backgroundColor: obj["data"]["background_color"].toString(),
          endTime: DateTime.fromMillisecondsSinceEpoch(
            obj["data"]["end_time"] * 1000,
          ),
          face: "${obj["data"]["user_info"]["face"]}@200w.jpg",
          message: obj["data"]["message"].toString(),
          price: obj["data"]["price"],
          startTime: DateTime.fromMillisecondsSinceEpoch(
            obj["data"]["start_time"] * 1000,
          ),
          userName: obj["data"]["user_info"]["uname"].toString(),
        );
        var liveMsg = LiveMessage(
          type: LiveMessageType.superChat,
          userName: "SUPER_CHAT_MESSAGE",
          message: "SUPER_CHAT_MESSAGE",
          color: LiveMessageColor.white,
          data: sc,
        );
        onMessage?.call(liveMsg);
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  int readInt(Uint8List buffer, int start, int len) {
    int result = 0;
    // 大端模式读取整数
    for (int i = 0; i < len; i++) {
      result = result * 256 + buffer[start + i];
    }
    return result;
  }
}
