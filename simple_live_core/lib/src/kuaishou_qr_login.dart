import 'package:dio/dio.dart';
import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';

/// 快手扫码登录状态
enum KuaishouQRScanState {
  /// 未扫描
  unscanned,

  /// 已扫描，未确认
  scanned,

  /// 已确认（acceptResult 拿到 qrToken）
  accepted,

  /// 二维码已过期
  expired,

  /// 失败
  failed,
}

/// 快手扫码登录·获取二维码结果
class KuaishouQRStartResult {
  final String qrLoginToken;
  final String qrLoginSignature;
  final String qrUrl;

  /// base64 PNG 二维码图（不带 data:image/png;base64, 前缀）
  final String imageData;
  final int expireTime;

  KuaishouQRStartResult({
    required this.qrLoginToken,
    required this.qrLoginSignature,
    required this.qrUrl,
    required this.imageData,
    required this.expireTime,
  });
}

/// 扫码状态轮询返回
class KuaishouQRScanResult {
  final KuaishouQRScanState state;

  /// 已扫描时的用户基本信息（昵称、头像）
  final Map<String, dynamic>? user;

  /// 已确认时返回的 qrToken
  final String? qrToken;

  KuaishouQRScanResult._(this.state, {this.user, this.qrToken});

  factory KuaishouQRScanResult.unscanned() =>
      KuaishouQRScanResult._(KuaishouQRScanState.unscanned);
  factory KuaishouQRScanResult.scanned(Map user) => KuaishouQRScanResult._(
      KuaishouQRScanState.scanned,
      user: user.map((k, v) => MapEntry(k.toString(), v)));
  factory KuaishouQRScanResult.accepted(String qrToken,
          {Map<String, dynamic>? user}) =>
      KuaishouQRScanResult._(KuaishouQRScanState.accepted,
          qrToken: qrToken, user: user);
  factory KuaishouQRScanResult.expired() =>
      KuaishouQRScanResult._(KuaishouQRScanState.expired);
  factory KuaishouQRScanResult.failed() =>
      KuaishouQRScanResult._(KuaishouQRScanState.failed);
}

/// 登录后用户信息
class KuaishouUserInfo {
  final String userId;
  final String eid;
  final String name;
  final String avatar;

  KuaishouUserInfo({
    required this.userId,
    required this.eid,
    required this.name,
    required this.avatar,
  });
}

/// 快手扫码登录核心流程封装。
///
/// 流程（来自抓包）：
/// 1. POST /rest/c/infra/ks/qr/start → 取 qrLoginToken / qrLoginSignature / imageData
/// 2. 轮询 POST /rest/c/infra/ks/qr/scanResult → 用户用 APP 扫描后返回 result=1 + user
/// 3. 轮询 POST /rest/c/infra/ks/qr/acceptResult → 用户在 APP 上确认后返回 result=1 + qrToken
/// 4. POST /pass/kuaishou/login/qr/callback → 用 qrToken 换 passToken / kuaishou.live.web_st / userId
/// 5. GET  /live_api/baseuser/userLogin → 完成 web 端登录态
/// 6. GET  /live_api/baseuser/userinfo → 拉取登录后用户信息
class KuaishouQRLogin {
  static const String kSid = "kuaishou.live.web";
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  /// 在整个登录链路中累积维护的 cookies
  String _cookies = "";

  String _qrLoginToken = "";
  String _qrLoginSignature = "";
  int _expireTime = 0;

  String get cookies => _cookies;
  String get qrLoginToken => _qrLoginToken;

  /// 快手后端给出的二维码绝对过期时间（毫秒时间戳）
  int get expireTime => _expireTime;

  Map<String, String> _headers({String? referer, String? origin}) {
    return {
      "User-Agent": kUserAgent,
      "Accept": "application/json, text/plain, */*",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      "Origin": origin ?? "https://live.kuaishou.com",
      "Referer": referer ?? "https://live.kuaishou.com/",
      if (_cookies.isNotEmpty) "Cookie": _cookies,
    };
  }

  /// 解析并合并 set-cookie
  void _accumulateCookies(Response resp) {
    final raw = resp.headers.map['set-cookie'];
    if (raw == null || raw.isEmpty) return;
    final pairs = <String, String>{};
    // 解析当前 _cookies
    for (final c in _cookies.split(';')) {
      final p = c.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq > 0) {
        pairs[p.substring(0, eq).trim()] = p.substring(eq + 1).trim();
      }
    }
    for (final c in raw) {
      final p = c.split(';').first.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq > 0) {
        pairs[p.substring(0, eq).trim()] = p.substring(eq + 1).trim();
      }
    }
    _cookies = pairs.entries.map((e) => "${e.key}=${e.value}").join("; ");
  }

  /// 1. 启动登录·获取二维码
  Future<KuaishouQRStartResult> start() async {
    // 先访问 live.kuaishou.com 获取基础 cookies（did/clientid 等）
    try {
      final r = await HttpClient.instance.dio.get(
        "https://live.kuaishou.com/",
        options: Options(
          headers: {
            "User-Agent": kUserAgent,
            "Accept":
                "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
          },
          followRedirects: true,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
      );
      _accumulateCookies(r);
    } catch (e) {
      CoreLog.error(e);
    }

    final resp = await HttpClient.instance.dio.post(
      "https://id.kuaishou.com/rest/c/infra/ks/qr/start",
      queryParameters: const {"sid": kSid},
      data: "sid=$kSid",
      options: Options(
        headers: _headers(referer: "https://live.kuaishou.com/"),
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
    _accumulateCookies(resp);
    final data = resp.data;
    if (data is! Map) throw "快手二维码请求失败";
    if (data["result"] != 1) {
      throw (data["error_msg"] ?? "二维码请求失败").toString();
    }
    _qrLoginToken = data["qrLoginToken"]?.toString() ?? "";
    _qrLoginSignature = data["qrLoginSignature"]?.toString() ?? "";
    _expireTime = int.tryParse(data["expireTime"]?.toString() ?? "0") ?? 0;
    return KuaishouQRStartResult(
      qrLoginToken: _qrLoginToken,
      qrLoginSignature: _qrLoginSignature,
      qrUrl: data["qrUrl"]?.toString() ?? "",
      imageData: data["imageData"]?.toString() ?? "",
      expireTime: _expireTime,
    );
  }

  /// 通用·判断接口响应里是否明确意味着二维码过期。
  /// 只通过 error_msg 文本判定（"过期/失效/expire"），不再使用任何硬编码 result 数字，
  /// 避免把"未扫描/中间状态"码误判为过期。客户端额外用 expireTime 做兜底超时。
  bool _isExpired(Map data) {
    final msg = (data["error_msg"] ?? data["errorMsg"] ?? "").toString();
    if (msg.isEmpty) return false;
    final lower = msg.toLowerCase();
    return msg.contains("过期") ||
        msg.contains("失效") ||
        lower.contains("expire") ||
        lower.contains("invalid");
  }

  /// 2. 轮询扫描状态
  Future<KuaishouQRScanResult> pollScanResult() async {
    if (_qrLoginToken.isEmpty) return KuaishouQRScanResult.failed();
    try {
      final resp = await HttpClient.instance.dio.post(
        "https://id.kuaishou.com/rest/c/infra/ks/qr/scanResult",
        queryParameters: {
          "qrLoginToken": _qrLoginToken,
          "qrLoginSignature": _qrLoginSignature,
          "sid": kSid,
        },
        data:
            "qrLoginToken=$_qrLoginToken&qrLoginSignature=$_qrLoginSignature&sid=$kSid",
        options: Options(
          headers: _headers(),
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      _accumulateCookies(resp);
      final data = resp.data;
      if (data is! Map) return KuaishouQRScanResult.unscanned();
      final code = data["result"];
      if (code == 1 && data["user"] is Map) {
        return KuaishouQRScanResult.scanned(data["user"] as Map);
      }
      if (_isExpired(data)) return KuaishouQRScanResult.expired();
      return KuaishouQRScanResult.unscanned();
    } catch (e) {
      CoreLog.error(e);
      return KuaishouQRScanResult.unscanned();
    }
  }

  /// 3. 轮询确认状态
  Future<KuaishouQRScanResult> pollAcceptResult() async {
    if (_qrLoginToken.isEmpty) return KuaishouQRScanResult.failed();
    try {
      final resp = await HttpClient.instance.dio.post(
        "https://id.kuaishou.com/rest/c/infra/ks/qr/acceptResult",
        queryParameters: {
          "qrLoginToken": _qrLoginToken,
          "qrLoginSignature": _qrLoginSignature,
          "sid": kSid,
        },
        data:
            "qrLoginToken=$_qrLoginToken&qrLoginSignature=$_qrLoginSignature&sid=$kSid",
        options: Options(
          headers: _headers(),
          contentType: Headers.formUrlEncodedContentType,
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      _accumulateCookies(resp);
      final data = resp.data;
      if (data is! Map) return KuaishouQRScanResult.scanned(const {});
      final code = data["result"];
      final qrToken = data["qrToken"]?.toString() ?? "";
      if (code == 1 && qrToken.isNotEmpty) {
        return KuaishouQRScanResult.accepted(qrToken);
      }
      // 仅在明确过期信号时才判定为过期，避免手机刚点确认时瞬时错误码造成误判
      if (_isExpired(data)) return KuaishouQRScanResult.expired();
      return KuaishouQRScanResult.scanned(const {});
    } catch (e) {
      CoreLog.error(e);
      return KuaishouQRScanResult.scanned(const {});
    }
  }

  /// 4. 用 qrToken 换 passToken / kuaishou.live.web_st / userId
  Future<bool> callback(String qrToken) async {
    final resp = await HttpClient.instance.dio.post(
      "https://id.kuaishou.com/pass/kuaishou/login/qr/callback",
      queryParameters: {"qrToken": qrToken, "sid": kSid},
      data: "qrToken=$qrToken&sid=$kSid",
      options: Options(
        headers: _headers(),
        contentType: Headers.formUrlEncodedContentType,
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
    _accumulateCookies(resp);
    final data = resp.data;
    if (data is! Map || data["result"] != 1) return false;

    // 把响应里返回的 token 也写入 cookies（部分服务端不通过 set-cookie 下发）
    final pairs = <String, String>{};
    for (final c in _cookies.split(';')) {
      final p = c.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf('=');
      if (eq > 0) {
        pairs[p.substring(0, eq).trim()] = p.substring(eq + 1).trim();
      }
    }
    final passToken = data["passToken"]?.toString() ?? "";
    final webSt = data["kuaishou.live.web_st"]?.toString() ?? "";
    final webAt = data["kuaishou.live.web.at"]?.toString() ?? "";
    final userId = data["userId"]?.toString() ?? "";
    if (passToken.isNotEmpty) pairs["passToken"] = passToken;
    if (webSt.isNotEmpty) pairs["kuaishou.live.web_st"] = webSt;
    if (webAt.isNotEmpty) pairs["kuaishou.live.web.at"] = webAt;
    if (userId.isNotEmpty) pairs["userId"] = userId;
    pairs["kpn"] = "GAME_ZONE";
    _cookies = pairs.entries.map((e) => "${e.key}=${e.value}").join("; ");
    return true;
  }

  /// 5. 完成 web 端登录态
  Future<bool> webLogin() async {
    try {
      final resp = await HttpClient.instance.dio.get(
        "https://live.kuaishou.com/live_api/baseuser/userLogin",
        options: Options(
          headers: _headers(),
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      _accumulateCookies(resp);
      final data = resp.data;
      if (data is Map && data["data"] is Map) {
        return data["data"]["result"] == 1;
      }
      return false;
    } catch (e) {
      CoreLog.error(e);
      return false;
    }
  }

  /// 6. 拉取用户信息
  Future<KuaishouUserInfo?> fetchUserInfo() async {
    try {
      final resp = await HttpClient.instance.dio.get(
        "https://live.kuaishou.com/live_api/baseuser/userinfo",
        options: Options(
          headers: _headers(),
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      _accumulateCookies(resp);
      final data = resp.data;
      if (data is! Map) return null;
      final wrap = data["data"];
      if (wrap is! Map) return null;
      final info = wrap["ownerInfo"];
      if (info is! Map) return null;
      return KuaishouUserInfo(
        userId: info["originUserId"]?.toString() ?? "",
        eid: info["id"]?.toString() ?? "",
        name: info["name"]?.toString() ?? "",
        avatar: info["avatar"]?.toString() ?? "",
      );
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 用已有 cookies 直接验证用户信息（用于持久化恢复登录态）
  static Future<KuaishouUserInfo?> verifyByCookies(String cookies) async {
    try {
      final resp = await HttpClient.instance.dio.get(
        "https://live.kuaishou.com/live_api/baseuser/userinfo",
        options: Options(
          headers: {
            "User-Agent": kUserAgent,
            "Origin": "https://live.kuaishou.com",
            "Referer": "https://live.kuaishou.com/",
            "Accept": "application/json, text/plain, */*",
            if (cookies.isNotEmpty) "Cookie": cookies,
          },
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      final data = resp.data;
      if (data is! Map) return null;
      final wrap = data["data"];
      if (wrap is! Map) return null;
      final info = wrap["ownerInfo"];
      if (info is! Map) return null;
      return KuaishouUserInfo(
        userId: info["originUserId"]?.toString() ?? "",
        eid: info["id"]?.toString() ?? "",
        name: info["name"]?.toString() ?? "",
        avatar: info["avatar"]?.toString() ?? "",
      );
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }
}
