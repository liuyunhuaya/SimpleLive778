import 'package:dio/dio.dart';
import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';

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

/// 手动粘贴 Cookie 校验结果（含服务端下发的合并后的 Cookie，应优先持久化）
class KuaishouCookieVerifyResult {
  final KuaishouUserInfo info;
  final String effectiveCookie;

  KuaishouCookieVerifyResult({
    required this.info,
    required this.effectiveCookie,
  });
}

/// 快手 Web 端 **Cookie 登录辅助类**。
///
/// 历史背景：早期同时支持二维码扫码登录与 Cookie 登录，类名沿用 [KuaishouQRLogin]。
/// 当前版本已**移除二维码扫码登录流程**（不可靠且需要 APP 配合），仅保留 Cookie 登录方式：
/// 用户在浏览器登录 live.kuaishou.com 后导出 Cookie，粘贴进 APP 完成登录。
///
/// 核心能力（全部为静态方法）：
/// - [normalizeKuaishouCookieHeader]：把浏览器复制的 Cookie 字符串规整为标准头
/// - [mergeSetCookieIntoHeader]：把响应的 Set-Cookie 合并进现有 Cookie 头
/// - [verifyByCookiesFull]：调用 `live_api/baseuser/userLogin` + `userinfo` 双接口完整校验，
///   返回 [KuaishouCookieVerifyResult]（含服务端最新 Cookie，应持久化）
/// - [verifyByCookies]：仅取用户信息，常用于启动时恢复登录态
class KuaishouQRLogin {
  /// live_api 接口必须的 sid 字段（保持兼容引用）
  static const String kSid = "kuaishou.live.web";

  /// 登录链路统一使用桌面端 Chrome UA，避免被识别为 APP 端导致接口差异
  static const String kUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  /// 接口 JSON 里 result 可能为 int / String / double，统一判定 1 为成功
  static bool _ksApiOk(dynamic result) =>
      result == 1 || result == "1" || result == 1.0;

  /// live.kuaishou.com baseuser 接口与浏览器一致：POST + JSON
  static Map<String, dynamic> _liveBaseuserHeaders(String cookie) {
    return {
      "User-Agent": kUserAgent,
      "Accept": "application/json, text/plain, */*",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      "Origin": "https://live.kuaishou.com",
      "Referer": "https://live.kuaishou.com/",
      if (cookie.isNotEmpty) "Cookie": cookie,
    };
  }

  /// POST `/live_api/baseuser/userinfo`，body 为 `{}`（与 DevTools 抓包一致）
  static Future<Response> _postBaseuserUserinfo(
    Dio dio,
    String cookie,
  ) {
    return dio.post(
      "https://live.kuaishou.com/live_api/baseuser/userinfo",
      data: const <String, dynamic>{},
      options: Options(
        headers: {
          ..._liveBaseuserHeaders(cookie),
          "Content-Type": "application/json",
        },
        responseType: ResponseType.json,
        validateStatus: (_) => true,
      ),
    );
  }

  /// 规范化浏览器/application 面板导出的 Cookie 字符串。
  /// - 去掉 `Cookie:` 前缀与换行
  /// - 同一 key 出现多次时保留最后一次（与 Chrome 合并行为一致，修复重复 did/userId）
  /// - 不含 `kpn` 时补 `GAME_ZONE`（与登录回调一致）
  static String normalizeKuaishouCookieHeader(String raw) {
    var s = raw.trim();
    if (s.toLowerCase().startsWith("cookie:")) {
      s = s.substring(7).trim();
    }
    s = s.replaceAll(RegExp(r"[\r\n]+"), " ");
    final pairs = <String, String>{};
    for (final segment in s.split(";")) {
      final p = segment.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf("=");
      if (eq <= 0) continue;
      final key = p.substring(0, eq).trim();
      var val = p.substring(eq + 1).trim();
      if (key.isEmpty) continue;
      if ((val.startsWith('"') && val.endsWith('"')) ||
          (val.startsWith("'") && val.endsWith("'"))) {
        val = val.substring(1, val.length - 1);
      }
      pairs[key] = val;
    }
    pairs.putIfAbsent("kpn", () => "GAME_ZONE");
    return pairs.entries.map((e) => "${e.key}=${e.value}").join("; ");
  }

  static Map<String, String> _cookieHeaderToMap(String cookie) {
    final pairs = <String, String>{};
    for (final segment in cookie.split(";")) {
      final p = segment.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf("=");
      if (eq <= 0) continue;
      final key = p.substring(0, eq).trim();
      final val = p.substring(eq + 1).trim();
      if (key.isNotEmpty) pairs[key] = val;
    }
    return pairs;
  }

  static String _mapToCookieHeader(Map<String, String> pairs) =>
      pairs.entries.map((e) => "${e.key}=${e.value}").join("; ");

  /// 把响应 Set-Cookie 合并进现有 Cookie 头
  static String mergeSetCookieIntoHeader(String cookieHeader, Response resp) {
    final pairs = _cookieHeaderToMap(cookieHeader);
    final raw = resp.headers.map["set-cookie"];
    if (raw == null || raw.isEmpty) {
      return _mapToCookieHeader(pairs);
    }
    for (final c in raw) {
      final first = c.split(";").first.trim();
      if (first.isEmpty) continue;
      final eq = first.indexOf("=");
      if (eq > 0) {
        pairs[first.substring(0, eq).trim()] =
            first.substring(eq + 1).trim();
      }
    }
    return _mapToCookieHeader(pairs);
  }

  static KuaishouUserInfo? _parseUserinfoResponse(
    dynamic data, {
    String? cookieUserIdFallback,
  }) {
    if (data is! Map) return null;
    final wrap = data["data"];
    if (wrap is! Map) return null;
    Map? info = wrap["ownerInfo"] as Map?;
    info ??= wrap["userInfo"] as Map?;
    if (info == null) return null;

    var userId = "${info["originUserId"] ?? ""}".trim();
    if (userId.isEmpty) {
      userId = "${info["userId"] ?? ""}".trim();
    }
    var eid = "${info["id"] ?? info["eid"] ?? ""}".trim();
    final name = info["name"]?.toString() ?? "";
    final avatar = (info["avatar"] ?? info["headUrl"] ?? "").toString();

    if (userId.isEmpty && eid.isNotEmpty) {
      userId = eid;
    }
    if (userId.isEmpty &&
        cookieUserIdFallback != null &&
        cookieUserIdFallback.isNotEmpty) {
      userId = cookieUserIdFallback;
    }
    if (eid.isEmpty && userId.isNotEmpty) {
      eid = userId;
    }
    if (userId.isEmpty && name.isEmpty && avatar.isEmpty) {
      return null;
    }
    return KuaishouUserInfo(
      userId: userId,
      eid: eid,
      name: name,
      avatar: avatar,
    );
  }

  /// 完整 Cookie 校验：先 `userLogin` 再 `userinfo`，并合并服务端 Set-Cookie。
  ///
  /// 入参 [rawCookies] 接受用户从浏览器复制的任意格式（含 `Cookie:` 前缀、换行、重复 key 都可），
  /// 返回 [KuaishouCookieVerifyResult]（包含合并后的 effectiveCookie，应替换持久化）。
  /// 校验失败 / 用户未登录返回 null。
  static Future<KuaishouCookieVerifyResult?> verifyByCookiesFull(
      String rawCookies) async {
    try {
      final normalized = normalizeKuaishouCookieHeader(rawCookies);
      if (normalized.isEmpty) return null;

      final cookieMap = _cookieHeaderToMap(normalized);
      final cookieUserIdFallback = cookieMap["userId"];

      var merged = normalized;

      final loginResp = await HttpClient.instance.dio.get(
        "https://live.kuaishou.com/live_api/baseuser/userLogin",
        options: Options(
          headers: {
            "User-Agent": kUserAgent,
            "Origin": "https://live.kuaishou.com",
            "Referer": "https://live.kuaishou.com/",
            "Accept": "application/json, text/plain, */*",
            "Cookie": merged,
          },
          responseType: ResponseType.json,
          validateStatus: (_) => true,
        ),
      );
      merged = mergeSetCookieIntoHeader(merged, loginResp);

      final resp =
          await _postBaseuserUserinfo(HttpClient.instance.dio, merged);
      merged = mergeSetCookieIntoHeader(merged, resp);

      final info = _parseUserinfoResponse(
        resp.data,
        cookieUserIdFallback: cookieUserIdFallback,
      );
      if (info == null) return null;
      if (info.userId.isEmpty) return null;

      // 静默调用 _ksApiOk 让其不被 unused 提示（保留以便将来需要从 result 字段判定时复用）
      _ksApiOk(loginResp.data is Map ? loginResp.data["result"] : null);

      return KuaishouCookieVerifyResult(
        info: info,
        effectiveCookie: merged,
      );
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 用已有 cookies 直接验证用户信息（用于持久化恢复登录态）
  static Future<KuaishouUserInfo?> verifyByCookies(String cookies) async {
    final r = await verifyByCookiesFull(cookies);
    return r?.info;
  }
}
