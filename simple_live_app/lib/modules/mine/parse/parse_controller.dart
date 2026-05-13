import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/routes/app_navigation.dart';

// 快手分享相关 UA：iPhone（更容易触发 302 跳到 live.kuaishou.com / chenzhongtech）
const String _kKuaishouMobileUA =
    "Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1";
const String _kKuaishouDesktopUA =
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

class ParseController extends GetxController {
  final TextEditingController roomJumpToController = TextEditingController();
  final TextEditingController getUrlController = TextEditingController();

  /// 标记本次解析过程中是否已显示过精确的错误反馈，避免外层再叠加一个泛化 toast
  bool _toastedInParse = false;

  void _toastInParse(String msg) {
    _toastedInParse = true;
    SmartDialog.showToast(msg);
  }

  /// 从输入文本中提取第一个可识别的链接（去除中文/空格等噪声）
  String _extractFirstUrl(String text) {
    final reg = RegExp(r"https?://[^\s\u4e00-\u9fa5\(\)\[\]\{\}'\""!，。、；：？！]+",
        caseSensitive: false);
    final m = reg.firstMatch(text);
    if (m == null) return "";
    var url = m.group(0) ?? "";
    // 修剪结尾常见噪声字符
    while (url.isNotEmpty &&
        ('.,;)]}>'.contains(url[url.length - 1]))) {
      url = url.substring(0, url.length - 1);
    }
    return url;
  }

  void jumpToRoom(String e) async {
    if (e.trim().isEmpty) {
      SmartDialog.showToast("链接不能为空");
      return;
    }
    // 隐藏键盘
    FocusManager.instance.primaryFocus?.unfocus();
    _toastedInParse = false;
    try {
      SmartDialog.showLoading(msg: "正在解析链接...");
      var parseResult = await parse(e);
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (parseResult.isEmpty ||
          (parseResult.first is String && (parseResult.first as String).isEmpty)) {
        if (!_toastedInParse) {
          SmartDialog.showToast("无法解析此链接，请确认链接是否正确");
        }
        return;
      }
      // 延迟200ms跳转，等待键盘隐藏
      Future.delayed(const Duration(milliseconds: 200), () {
        Site site = parseResult[1];
        AppNavigator.toLiveRoomDetail(site: site, roomId: parseResult.first);
      });
    } catch (e) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      Log.logPrint(e);
      SmartDialog.showToast("链接解析失败：$e");
    }
  }

  void getPlayUrl(String e) async {
    if (e.trim().isEmpty) {
      SmartDialog.showToast("链接不能为空");
      return;
    }
    _toastedInParse = false;
    List parseResult;
    try {
      SmartDialog.showLoading(msg: "正在解析链接...");
      parseResult = await parse(e);
    } catch (err) {
      SmartDialog.dismiss(status: SmartStatus.loading);
      Log.logPrint(err);
      SmartDialog.showToast("链接解析失败：$err");
      return;
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
    if (parseResult.isEmpty ||
        (parseResult.first is String && (parseResult.first as String).isEmpty)) {
      if (!_toastedInParse) {
        SmartDialog.showToast("无法解析此链接，请确认链接是否正确");
      }
      return;
    }
    Site site = parseResult[1];
    try {
      SmartDialog.showLoading(msg: "");
      var detail = await site.liveSite.getRoomDetail(roomId: parseResult.first);
      var qualites = await site.liveSite.getPlayQualites(detail: detail);
      SmartDialog.dismiss(status: SmartStatus.loading);
      if (qualites.isEmpty) {
        SmartDialog.showToast("读取直链失败,无法读取清晰度");

        return;
      }
      var result = await Get.dialog(SimpleDialog(
        title: const Text("选择清晰度"),
        children: qualites
            .map(
              (e) => ListTile(
                title: Text(
                  e.quality,
                  textAlign: TextAlign.center,
                ),
                onTap: () {
                  Get.back(result: e);
                },
              ),
            )
            .toList(),
      ));
      if (result == null) {
        return;
      }
      SmartDialog.showLoading(msg: "");
      var playUrl =
          await site.liveSite.getPlayUrls(detail: detail, quality: result);
      SmartDialog.dismiss(status: SmartStatus.loading);
      await Get.dialog(SimpleDialog(
        title: const Text("选择线路"),
        children: playUrl.urls
            .map(
              (e) => ListTile(
                title: Text(
                  "线路${playUrl.urls.indexOf(e) + 1}",
                ),
                subtitle: Text(
                  e,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: e));
                  Get.back();
                  SmartDialog.showToast("已复制直链");
                },
              ),
            )
            .toList(),
      ));
    } catch (e) {
      SmartDialog.showToast("读取直链失败");
    } finally {
      SmartDialog.dismiss(status: SmartStatus.loading);
    }
  }

  Future<List> parse(String rawInput, {int depth = 0}) async {
    // 防止重定向死循环
    if (depth > 5) return [];

    // 先把粘贴文本里的中文/前后噪声去掉，仅保留首个 URL
    var url = rawInput;
    if (!url.startsWith("http")) {
      final extracted = _extractFirstUrl(rawInput);
      if (extracted.isNotEmpty) {
        url = extracted;
      }
    } else {
      // 如果是以 http 开头但被中文/空格污染，也要清洗一遍
      final extracted = _extractFirstUrl(rawInput);
      if (extracted.isNotEmpty) {
        url = extracted;
      }
    }
    Log.d("解析链接: $url");
    var id = "";
    if (url.contains("bilibili.com")) {
      var regExp = RegExp(r"bilibili\.com/([\d|\w]+)");
      id = regExp.firstMatch(url)?.group(1) ?? "";
      return [id, Sites.allSites[Constant.kBiliBili]!];
    }

    if (url.contains("b23.tv")) {
      var btvReg = RegExp(r"https?:\/\/b23.tv\/[0-9a-z-A-Z]+");
      var u = btvReg.firstMatch(url)?.group(0) ?? "";
      var location = await getLocation(u);
      if (location.isEmpty) return [];
      return await parse(location, depth: depth + 1);
    }

    if (url.contains("douyu.com")) {
      var regExp = RegExp(r"douyu\.com/([\d|\w]+)");
      if (url.contains("topic")) {
        regExp = RegExp(r"[?&]rid=([\d]+)");
      }
      id = regExp.firstMatch(url)?.group(1) ?? "";

      return [id, Sites.allSites[Constant.kDouyu]!];
    }
    if (url.contains("huya.com")) {
      var regExp = RegExp(r"huya\.com/([\d|\w]+)");
      id = regExp.firstMatch(url)?.group(1) ?? "";

      return [id, Sites.allSites[Constant.kHuya]!];
    }
    if (url.contains("live.douyin.com")) {
      var regExp = RegExp(r"live\.douyin\.com/([\d|\w]+)");
      id = regExp.firstMatch(url)?.group(1) ?? "";

      return [id, Sites.allSites[Constant.kDouyin]!];
    }
    if (url.contains("webcast.amemv.com")) {
      var regExp = RegExp(r"reflow/(\d+)");
      id = regExp.firstMatch(url)?.group(1) ?? "";
      return [id, Sites.allSites[Constant.kDouyin]!];
    }
    if (url.contains("v.douyin.com")) {
      var regExp = RegExp(r"http.?://v.douyin.com/[\d\w]+/?");
      var u = regExp.firstMatch(url)?.group(0) ?? "";
      var location = await getLocation(u);
      if (location.isEmpty) return [];
      return await parse(location, depth: depth + 1);
    }
    // 快手直播跨平台链接：https://live.kuaishou.com/u/{eid}
    if (url.contains("live.kuaishou.com/u/")) {
      var regExp = RegExp(r"live\.kuaishou\.com/u/([\d\w\-_]+)");
      id = regExp.firstMatch(url)?.group(1) ?? "";
      if (id.isEmpty) {
        _toastInParse("快手直播间链接缺少主播 ID");
        return [];
      }
      return [id, Sites.allSites[Constant.kKuaishou]!];
    }
    // 快手主播主页：https://www.kuaishou.com/profile/{eid}
    if (url.contains("kuaishou.com/profile/")) {
      var regExp = RegExp(r"kuaishou\.com/profile/([\d\w\-_]+)");
      id = regExp.firstMatch(url)?.group(1) ?? "";
      if (id.isEmpty) {
        _toastInParse("快手主页链接缺少主播 ID");
        return [];
      }
      return [id, Sites.allSites[Constant.kKuaishou]!];
    }
    // 快手APP分享短链：https://v.kuaishou.com/xxxx
    if (url.contains("v.kuaishou.com")) {
      var regExp = RegExp(r"http.?://v\.kuaishou\.com/[\d\w]+");
      var u = regExp.firstMatch(url)?.group(0) ?? "";
      if (u.isEmpty) {
        _toastInParse("快手短链格式异常");
        return [];
      }
      // 1) 用手机 UA 跟随多层 302 重定向，拿到完整链路
      var chain = await _followAllRedirects(u, mobileUA: true);
      // 2) 链路里优先匹配直播间格式（live.kuaishou.com/u/、profile/、chenzhongtech）
      var hit = _pickKuaishouRoomUrl(chain);
      // 3) 如果手机 UA 没拿到可识别 URL，再尝试一次 PC UA
      if (hit == null) {
        final pcChain = await _followAllRedirects(u, mobileUA: false);
        chain = [...chain, ...pcChain];
        hit = _pickKuaishouRoomUrl(chain);
      }
      Log.d("[Parse] kuaishou chain = $chain, hit=$hit");
      if (hit != null && hit != u && !hit.contains("v.kuaishou.com")) {
        return await parse(hit, depth: depth + 1);
      }
      // 4) 兜底：抓最后一个 URL 的 HTML，从中找主播 eid
      final lastUrl = chain.isNotEmpty ? chain.last : u;
      final eid = await _extractKuaishouIdFromHtml(lastUrl);
      if (eid.isNotEmpty) {
        return [eid, Sites.allSites[Constant.kKuaishou]!];
      }
      _toastInParse("无法识别此快手链接，可能不是直播间分享");
      return [];
    }
    // 快手 App 分享后的中转域名：https://v.m.chenzhongtech.com/fw/live/{username}?...&efid={photoId}
    //
    // 实测链路（curl 验证）：
    //   https://v.kuaishou.com/K5Do1RsP
    //   → 302 https://v.m.chenzhongtech.com/fw/live/tianci666?efid=3xsdnab6r256z8g&userId=125393142&...
    //
    // 关键事实（之前的代码理解错了）：
    //   - URL **path** 段 `/fw/live/tianci666` 中的 tianci666 才是**主播 username/eid**，
    //     可直接用于 `https://live.kuaishou.com/u/tianci666`
    //   - URL **query** 参数 `efid=3xsdnab6r256z8g` 是 photoId / 直播流 ID，**不是主播 eid**，
    //     用它去访问 `live.kuaishou.com/u/{efid}` 会拿到主播信息但 SSR 中 playUrls 为空架子
    //     `{h264:{}, hevc:{}}`，进入直播间就会报"无法读取播放清晰度"
    //   - userId 是主播 originUserId（数字），shareEid 才是分享者 eid（不是主播）
    //
    // 因此修复后的优先级：path > 抓 HTML > query 兜底，并彻底移除 efid 作为主播 ID 的提取。
    if (url.contains("chenzhongtech.com") || url.contains("kwai.com")) {
      // 优先级 1：URL 路径中的主播段（live / user / profile / u）
      const pathPatterns = [
        // /fw/live/{username} & /fw/user/{eid} → 主播标识
        r"/fw/(?:live|user)/([\d\w\-_]+)",
        // /profile/{eid} & /u/{eid} → 主播标识
        r"/(?:profile|u)/([\d\w\-_]+)",
      ];
      for (final p in pathPatterns) {
        final m = RegExp(p).firstMatch(url)?.group(1) ?? "";
        if (m.isNotEmpty && m.length >= 5) {
          Log.d("[Parse] kuaishou chenzhongtech 命中路径 $m");
          return [m, Sites.allSites[Constant.kKuaishou]!];
        }
      }
      // 优先级 2：抓 HTML 兜底找主播 eid（og:url / principalId / authorId / live.kuaishou.com/u/）
      final eid = await _extractKuaishouIdFromHtml(url);
      if (eid.isNotEmpty) {
        return [eid, Sites.allSites[Constant.kKuaishou]!];
      }
      // 优先级 3：query 参数兜底（注意：efid 是 photoId 已剔除；userId 是 originUserId 部分场景能用）
      const candidateQueryKeys = [
        "principalId",
        "authorId",
        "eid",
        "shareEid",
        "userId", // 主播 originUserId（部分场景 live.kuaishou.com/u/{originUserId} 也能命中）
      ];
      for (final key in candidateQueryKeys) {
        final reg = RegExp("[?&]$key=([\\d\\w\\-_]+)");
        final m = reg.firstMatch(url)?.group(1) ?? "";
        if (m.isNotEmpty && m.length >= 5) {
          Log.d("[Parse] kuaishou chenzhongtech 命中参数 $key=$m");
          return [m, Sites.allSites[Constant.kKuaishou]!];
        }
      }
      _toastInParse("无法从快手中转链接识别直播间 ID");
      return [];
    }

    return [];
  }

  /// 创建带合理超时配置的 Dio 实例（避免短链请求长时间挂起）。
  Dio _buildDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      sendTimeout: const Duration(seconds: 8),
    ));
  }

  /// 跟随多层 302/301 重定向，返回完整重定向链路（包含原 URL 与所有跳转后的 URL）。
  /// 部分快手短链需要跳 3 ~ 5 跳才能到 live.kuaishou.com 或 chenzhongtech.com。
  ///
  /// **关键实现细节**：
  /// `validateStatus` 必须设为 `< 300`，让 3xx 响应抛 DioException 进入 catch，
  /// 这样我们才能拿到 Location header。如果设为 `< 400`（旧版 bug），3xx 会被
  /// 视为正常响应返回 → 循环直接 break，**整个重定向链路丢失**，导致快手
  /// 短链 `v.kuaishou.com/xxx` 永远拿不到跳转后的 `chenzhongtech.com/fw/live/{username}`。
  Future<List<String>> _followAllRedirects(
    String url, {
    int maxRedirects = 8,
    bool mobileUA = true,
  }) async {
    final List<String> chain = [url];
    String current = url;
    final dio = _buildDio();
    for (int i = 0; i < maxRedirects; i++) {
      try {
        final resp = await dio.get(
          current,
          options: Options(
            followRedirects: false,
            // 只把 2xx 视为成功；3xx 让其抛 DioException 走 catch，便于读 Location
            validateStatus: (status) => status != null && status < 300,
            responseType: ResponseType.plain,
            headers: {
              "User-Agent": mobileUA ? _kKuaishouMobileUA : _kKuaishouDesktopUA,
              "Accept":
                  "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
              "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
            },
          ),
        );
        Log.d("[Parse] 重定向终点 $current status=${resp.statusCode}");
        break;
      } on DioException catch (e) {
        final statusCode = e.response?.statusCode ?? 0;
        if (statusCode >= 300 && statusCode < 400) {
          final redirectUrl = e.response?.headers.value("location") ??
              e.response?.headers.value("Location");
          if (redirectUrl == null || redirectUrl.isEmpty) break;
          String next;
          try {
            if (redirectUrl.startsWith("//")) {
              final scheme = Uri.parse(current).scheme;
              next = "$scheme:$redirectUrl";
            } else if (redirectUrl.startsWith("/")) {
              final uri = Uri.parse(current);
              next = "${uri.scheme}://${uri.host}$redirectUrl";
            } else if (!redirectUrl.startsWith("http")) {
              next = Uri.parse(current).resolve(redirectUrl).toString();
            } else {
              next = redirectUrl;
            }
          } catch (_) {
            next = redirectUrl;
          }
          if (next == current) break;
          chain.add(next);
          Log.d("[Parse] redirect $i: $current -> $next");
          current = next;
          continue;
        }
        Log.logPrint(e);
        break;
      } catch (e) {
        Log.logPrint(e);
        break;
      }
    }
    return chain;
  }

  /// 从重定向链路中按优先级挑选第一个可识别为快手直播间的 URL。
  /// 优先级：live.kuaishou.com/u/ > kuaishou.com/profile/ > chenzhongtech/kwai
  String? _pickKuaishouRoomUrl(List<String> chain) {
    for (final u in chain) {
      if (u.contains("live.kuaishou.com/u/")) return u;
    }
    for (final u in chain) {
      if (u.contains("kuaishou.com/profile/")) return u;
    }
    for (final u in chain) {
      if (u.contains("chenzhongtech.com") || u.contains("kwai.com")) return u;
    }
    return null;
  }

  /// 抓取最终页面 HTML，从中提取快手主播 eid（兜底）。
  /// 解析顺序：og:url > __APOLLO_STATE__/__INITIAL_STATE__ JSON > 页面中的 live.kuaishou.com/u/xxx 链接
  Future<String> _extractKuaishouIdFromHtml(String url) async {
    if (url.isEmpty) return "";
    try {
      final dio = _buildDio();
      final resp = await dio.get(
        url,
        options: Options(
          responseType: ResponseType.plain,
          followRedirects: true,
          maxRedirects: 5,
          validateStatus: (s) => s != null && s < 500,
          headers: const {
            "User-Agent": _kKuaishouMobileUA,
            "Accept":
                "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
          },
        ),
      );
      final raw = resp.data;
      final html = raw is String ? raw : raw.toString();
      if (html.isEmpty) return "";

      // ① 优先从 og:url meta 标签中拿到完整 URL
      final ogUrlReg = RegExp(
        r'''<meta\s+(?:property|name)\s*=\s*["']og:url["']\s+content\s*=\s*["']([^"']+)["']''',
        caseSensitive: false,
      );
      final ogMatch = ogUrlReg.firstMatch(html);
      if (ogMatch != null) {
        final ogUrl = ogMatch.group(1) ?? "";
        final fromOg = _extractIdFromUrlString(ogUrl);
        if (fromOg.isNotEmpty) {
          Log.d("[Parse] kuaishou og:url 命中 -> $fromOg");
          return fromOg;
        }
      }

      // ② HTML 文本中直接搜索 live.kuaishou.com/u/xxx（最权威，直接是主播页 URL）
      final liveReg = RegExp(r'live\.kuaishou\.com/u/([\d\w\-_]+)');
      final liveMatch = liveReg.firstMatch(html);
      if (liveMatch != null) {
        final eid = liveMatch.group(1) ?? "";
        if (eid.isNotEmpty) {
          Log.d("[Parse] kuaishou html live/u/ -> $eid");
          return eid;
        }
      }

      // ③ HTML 文本中搜索 kuaishou.com/profile/xxx（次权威）
      final profReg = RegExp(r'kuaishou\.com/profile/([\d\w\-_]+)');
      final profMatch = profReg.firstMatch(html);
      if (profMatch != null) {
        final eid = profMatch.group(1) ?? "";
        if (eid.isNotEmpty) {
          Log.d("[Parse] kuaishou html profile -> $eid");
          return eid;
        }
      }

      // ④ HTML 文本中搜索 v.m.chenzhongtech.com/fw/(live|user)/xxx 中的 path 段
      // path 段是主播 username/eid（如 tianci666），可直接用作 live.kuaishou.com/u/{x}
      final fwReg = RegExp(r'(?:chenzhongtech|kwai)\.com/fw/(?:live|user)/([\d\w\-_]+)');
      final fwMatch = fwReg.firstMatch(html);
      if (fwMatch != null) {
        final eid = fwMatch.group(1) ?? "";
        if (eid.isNotEmpty) {
          Log.d("[Parse] kuaishou html fw/live -> $eid");
          return eid;
        }
      }

      // ⑤ 从内嵌 JSON 中找 principalId / authorId / eid（兜底）
      // 注意：效验 efid 故意排除——它是 photoId 不是主播 eid，会导致进入直播间
      // 时 SSR 拿不到 playUrls，报"无法读取播放清晰度"
      const idJsonKeys = [
        "principalId",
        "authorId",
        "eid",
      ];
      for (final k in idJsonKeys) {
        final reg = RegExp('"$k"\\s*:\\s*"([\\d\\w\\-_]+)"');
        final m = reg.firstMatch(html)?.group(1) ?? "";
        if (m.isNotEmpty && m.length >= 6) {
          Log.d("[Parse] kuaishou json key=$k -> $m");
          return m;
        }
      }

      return "";
    } catch (e) {
      Log.logPrint(e);
      return "";
    }
  }

  /// 从给定 URL 中尝试按已知模式提取主播 eid。
  ///
  /// **优先级（按 URL 中已知主播标识的可靠程度排序）**：
  /// 1. `live.kuaishou.com/u/{x}` → 主播页 path
  /// 2. `kuaishou.com/profile/{x}` → 主播 profile 页
  /// 3. `(chenzhongtech|kwai).com/fw/(live|user)/{x}` → 分享中转页 path（如 tianci666）
  /// 4. query `principalId` / `authorId` → 兜底
  ///
  /// **注意**：故意不再提取 `efid` query 参数。它是 photoId / 直播流 ID，
  /// 不是主播 eid，用它去 `live.kuaishou.com/u/{efid}` 会拿到主播信息但 SSR 中 playUrls
  /// 为空架子 `{h264:{}, hevc:{}}`，进入直播间会报"无法读取播放清晰度"。
  String _extractIdFromUrlString(String url) {
    if (url.isEmpty) return "";
    final patterns = <RegExp>[
      RegExp(r"live\.kuaishou\.com/u/([\d\w\-_]+)"),
      RegExp(r"kuaishou\.com/profile/([\d\w\-_]+)"),
      RegExp(r"(?:chenzhongtech|kwai)\.com/fw/(?:live|user)/([\d\w\-_]+)"),
      RegExp(r"[?&]principalId=([\d\w\-_]+)"),
      RegExp(r"[?&]authorId=([\d\w\-_]+)"),
    ];
    for (final reg in patterns) {
      final m = reg.firstMatch(url)?.group(1) ?? "";
      if (m.isNotEmpty && m.length >= 5) return m;
    }
    return "";
  }

  Future<String> getLocation(String url) async {
    try {
      if (url.isEmpty) return "";
      final resp = await Dio().get(
        url,
        options: Options(
          followRedirects: false,
          // 只把 2xx 视为成功；3xx 让其抛 DioException 走 catch 读 Location
          validateStatus: (status) => status != null && status < 300,
          headers: const {
            "User-Agent":
                "Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36",
          },
        ),
      );
      // 部分平台直接 200 返回 HTML，没有 302。这里也作为兜底，返回原 url。
      Log.d("getLocation status=${resp.statusCode}");
      return "";
    } on DioException catch (e) {
      // 301/302/303/307/308 都视为重定向
      final statusCode = e.response?.statusCode ?? 0;
      if (statusCode >= 300 && statusCode < 400) {
        final redirectUrl = e.response?.headers.value("location") ??
            e.response?.headers.value("Location");
        if (redirectUrl != null && redirectUrl.isNotEmpty) {
          return redirectUrl;
        }
      }
      Log.logPrint(e);
    } catch (e) {
      Log.logPrint(e);
    }
    return "";
  }
}
