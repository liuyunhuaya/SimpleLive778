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
    
    // 构建调试信息
    var debugInfo = StringBuffer();
    debugInfo.writeln("=== B站弹幕连接信息 ===");
    debugInfo.writeln("平台: ${Platform.operatingSystem}");
    debugInfo.writeln("房间ID: ${args.roomId}");
    debugInfo.writeln("服务器: ${args.serverHost}");
    debugInfo.writeln("UID: ${args.uid}");
    debugInfo.writeln("Buvid: ${args.buvid.isNotEmpty ? '已设置' : '未设置'}");
    debugInfo.writeln("Token: ${args.token.isNotEmpty ? '已获取' : '未获取'}");
    debugInfo.writeln("Cookie: ${args.cookie.isNotEmpty ? '已设置' : '未设置'}");
    debugInfo.writeln("SESSDATA: ${args.cookie.contains('SESSDATA') ? '存在' : '不存在'}");
    
    // iOS特殊处理
    if (Platform.isIOS) {
      debugInfo.writeln("iOS平台特殊说明:");
      if (args.cookie.isEmpty || !args.cookie.contains('SESSDATA')) {
        debugInfo.writeln("❌ 未登录B站账号，iOS需要登录才能查看弹幕");
        onClose?.call("iOS平台需要登录B站账号才能查看弹幕\n请在「我的-账号管理」中登录");
        return;
      }
      debugInfo.writeln("✓ 已登录B站账号");
    }
    
    // Windows可以游客模式，但iOS不行
    if (Platform.isWindows && (args.cookie.isEmpty || !args.cookie.contains('SESSDATA'))) {
      debugInfo.writeln("Windows游客模式（功能受限）");
    }
    
    // 不输出控制台日志
    
    // 根据blivedm最新代码构建WebSocket URL
    String wsUrl;
    List<String> backupUrls;
    
    // iOS平台使用特殊端口2243
    if (Platform.isIOS) {
      // iOS优先使用的服务器列表
      var iosPreferredHosts = [
        "zj-cn-live-comet.chat.bilibili.com",
        "broadcastlv.chat.bilibili.com",
        "bd-gz-live-comet-07.chat.bilibili.com"
      ];
      
      // 从args.serverHost中提取主机名
      String hostName = args.serverHost.split(':')[0];
      
      // 如果是iOS优选服务器，使用该服务器
      if (iosPreferredHosts.contains(hostName)) {
        wsUrl = "wss://$hostName:2243/sub";
      } else if (args.serverHost.isNotEmpty) {
        // 使用提供的服务器，但使用iOS端口
        wsUrl = "wss://$hostName:2243/sub";
      } else {
        // 默认使用第一个iOS服务器
        wsUrl = "wss://zj-cn-live-comet.chat.bilibili.com:2243/sub";
      }
      
      // iOS备用服务器，端口2243
      backupUrls = [
        "wss://broadcastlv.chat.bilibili.com:2243/sub",
        "wss://zj-cn-live-comet.chat.bilibili.com:2243/sub",
        "wss://bd-gz-live-comet-07.chat.bilibili.com:2243/sub",
      ];
    } else {
      // 其他平台使用端口443
      if (args.serverHost.contains(':')) {
        // 如果serverHost已经包含端口，直接使用
        wsUrl = "wss://${args.serverHost}/sub";
      } else {
        // 否则添加默认端口443
        wsUrl = "wss://${args.serverHost}:443/sub";
      }
      
      // 其他平台备用服务器，端口443
      backupUrls = [
        "wss://broadcastlv.chat.bilibili.com:443/sub",
        "wss://tx-sh-live-comet-08.chat.bilibili.com:443/sub",
        "wss://tx-bj-live-comet-08.chat.bilibili.com:443/sub",
      ];
    }
    
    // iOS平台使用特定的User-Agent和Headers
    Map<String, dynamic> headers = {
      "Origin": "https://live.bilibili.com",
    };
    
    if (Platform.isIOS) {
      // 使用最新的iOS 17.5.1 User-Agent
      headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148";
    } else {
      // 使用最新的Edge 142 User-Agent
      headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36 Edg/142.0.0.0";
    }
    
    if (args.cookie.isNotEmpty) {
      headers["Cookie"] = args.cookie;
    }
    
    webScoketUtils = WebScoketUtils(
      url: wsUrl,
      backupUrl: backupUrls.first,
      heartBeatTime: heartbeatTime,
      headers: headers,
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
        // 不输出控制台日志
        
        // 只在真正未登录时提示游客模式
        if (args.cookie.isEmpty || !args.cookie.contains("SESSDATA")) {
          onClose?.call("弹幕连接失败：当前为游客模式，无法查看弹幕。\n请在「我的-账号管理」中登录B站账号。");
        } else if (errorMsg.contains("HandshakeException")) {
          onClose?.call("弹幕连接失败：TLS/SSL 握手失败。\n请检查网络连接或系统时间是否正确。");
        } else if (errorMsg.contains("Connection refused")) {
          onClose?.call("弹幕连接失败：服务器连接被拒绝。\n请检查网络连接。");
        } else if (errorMsg.contains("SocketException") || errorMsg.contains("Connection closed")) {
          onClose?.call("弹幕连接失败：网络连接中断。\n请检查网络连接。");
        } else if (errorMsg.contains("401") || errorMsg.contains("403")) {
          onClose?.call("弹幕连接失败：身份验证失败。\nCookie 可能已过期，请重新登录B站账号。");
        } else if (errorMsg.contains("WebSocketException")) {
          onClose?.call("弹幕连接失败：WebSocket 连接异常。\n请检查网络连接。");
        } else if (errorMsg.contains("FormatException")) {
          onClose?.call("弹幕连接失败：数据格式异常。\n请检查网络连接。");
        } else {
          // 其他错误，显示详细信息
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
