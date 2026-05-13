import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:simple_live_core/src/common/core_log.dart';
import 'package:simple_live_core/src/common/http_client.dart';
import 'package:simple_live_core/src/danmaku/kuaishou_danmaku.dart';
import 'package:simple_live_core/src/interface/live_danmaku.dart';
import 'package:simple_live_core/src/interface/live_site.dart';
import 'package:simple_live_core/src/model/live_anchor_item.dart';
import 'package:simple_live_core/src/model/live_category.dart';
import 'package:simple_live_core/src/model/live_category_result.dart';
import 'package:simple_live_core/src/model/live_message.dart';
import 'package:simple_live_core/src/model/live_play_quality.dart';
import 'package:simple_live_core/src/model/live_play_url.dart';
import 'package:simple_live_core/src/model/live_rank_item.dart';
import 'package:simple_live_core/src/model/live_room_detail.dart';
import 'package:simple_live_core/src/model/live_room_item.dart';
import 'package:simple_live_core/src/model/live_search_result.dart';

/// 快手直播站点实现。
///
/// 关键说明：
/// 1. 房间ID约定：使用主播 eid（即 https://live.kuaishou.com/u/{eid} 中的 eid）。
/// 2. 推荐 / 分类：调用快手网页端 live_api 接口（home/list、gameboard/list、category/data）。
/// 3. 直播间详情：解析 H5 页面 `__INITIAL_STATE__` 获取房间数据。
/// 4. 弹幕使用占位实现（详见 KuaishouDanmaku），不解析 protobuf 协议。
class KuaishouSite implements LiveSite {
  @override
  String id = "kuaishou";

  @override
  String name = "快手直播";

  static const String kDesktopUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36";

  static const String kDefaultUserAgent = kDesktopUserAgent;

  /// 进入站点首次抓到的 cookie，用于后续接口请求
  String _cachedCookie = "";
  DateTime _cookieExpire = DateTime.fromMillisecondsSinceEpoch(0);

  /// 用户登录后的 cookie（passToken / kuaishou.live.web_st / userId 等），
  /// 会与匹配的顶部匿名 cookie 一起发送，用于需要登录态的接口（如搜索、高画质资源）。
  String userCookie = "";

  Map<String, String> get headers {
    final merged = _mergeCookieStrings(_cachedCookie, userCookie);
    return {
      "User-Agent": kDesktopUserAgent,
      "Referer": "https://live.kuaishou.com/",
      "Accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      if (merged.isNotEmpty) "Cookie": merged,
    };
  }

  /// 把两段 Cookie 字符串按 key 去重合并；
  /// 后者（userCookie）相同 key 覆盖前者（_cachedCookie），
  /// 避免登录态 did/userId 被匿名 cookie 顶掉，造成 SSR 数据被当作未登录返回。
  static String _mergeCookieStrings(String a, String b) {
    final pairs = <String, String>{};
    void parse(String s) {
      for (final seg in s.split(";")) {
        final p = seg.trim();
        if (p.isEmpty) continue;
        final eq = p.indexOf("=");
        if (eq <= 0) continue;
        pairs[p.substring(0, eq).trim()] = p.substring(eq + 1).trim();
      }
    }

    parse(a);
    parse(b);
    return pairs.entries.map((e) => "${e.key}=${e.value}").join("; ");
  }

  /// 拉取首页 cookie（live.kuaishou.com 首次访问会下发 did/clientid 等鉴权cookie）
  Future<void> _ensureCookie({bool force = false}) async {
    if (!force &&
        _cachedCookie.isNotEmpty &&
        _cookieExpire.isAfter(DateTime.now())) {
      return;
    }
    try {
      final resp = await HttpClient.instance.dio.get(
        "https://live.kuaishou.com/",
        options: Options(
          headers: {
            "User-Agent": kDesktopUserAgent,
            "Accept":
                "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3",
          },
          followRedirects: true,
          validateStatus: (_) => true,
          responseType: ResponseType.plain,
        ),
      );
      final raw = resp.headers.map['set-cookie'];
      if (raw != null && raw.isNotEmpty) {
        final pairs = <String>[];
        for (final c in raw) {
          final p = c.split(";").first.trim();
          if (p.isNotEmpty) pairs.add(p);
        }
        if (pairs.isNotEmpty) {
          _cachedCookie = pairs.join("; ");
          _cookieExpire = DateTime.now().add(const Duration(minutes: 30));
        }
      }
    } catch (e) {
      CoreLog.error(e);
    }
  }

  /// 是否为图片URL（快手部分接口返回的 poster 缺扩展名）
  bool _isImage(String url) {
    if (url.isEmpty) return false;
    final ext = url.split("?").first.split(".").last.toLowerCase();
    const imageExts = [
      "jpg",
      "jpeg",
      "png",
      "webp",
      "bmp",
      "gif",
      "svg",
      "jfif",
      "avif"
    ];
    return imageExts.contains(ext);
  }

  String _wrapPoster(dynamic raw) {
    final s = raw?.toString() ?? "";
    if (s.isEmpty) return "";
    if (s.startsWith("http")) {
      return _isImage(s) ? s : "$s.jpg";
    }
    return s;
  }

  @override
  LiveDanmaku getDanmaku() => KuaishouDanmaku();

  @override
  Future<List<LiveCategory>> getCategores() async {
    // 快手网页端按 type 划分一级分类
    final categories = <LiveCategory>[
      LiveCategory(id: "1", name: "热门", children: []),
      LiveCategory(id: "2", name: "网游", children: []),
      LiveCategory(id: "3", name: "单机", children: []),
      LiveCategory(id: "4", name: "手游", children: []),
      LiveCategory(id: "5", name: "棋牌", children: []),
      LiveCategory(id: "6", name: "娱乐", children: []),
      LiveCategory(id: "7", name: "综合", children: []),
      LiveCategory(id: "8", name: "文化", children: []),
    ];
    await _ensureCookie();
    for (final cat in categories) {
      try {
        final subs = await _fetchSubCategores(cat, page: 1, size: 30);
        cat.children.addAll(subs);
      } catch (e) {
        CoreLog.error(e);
      }
    }
    return categories;
  }

  Future<List<LiveSubCategory>> _fetchSubCategores(
    LiveCategory parent, {
    int page = 1,
    int size = 30,
  }) async {
    final result = await HttpClient.instance.getJson(
      "https://live.kuaishou.com/live_api/category/data",
      queryParameters: {
        "type": parent.id,
        "page": page,
        "size": size,
      },
      header: headers,
    );
    final data = (result is Map) ? result["data"] : null;
    final raw = (data is Map) ? data["list"] : null;
    final list = (raw is List) ? raw : const [];
    final subs = <LiveSubCategory>[];
    for (final item in list) {
      if (item is! Map) continue;
      subs.add(LiveSubCategory(
        id: item["id"]?.toString() ?? "",
        name: item["name"]?.toString() ?? "",
        parentId: parent.id,
        pic: _wrapPoster(item["poster"]),
      ));
    }
    return subs;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    try {
      await _ensureCookie();
      // gameId 长度 < 7 时为游戏分类，否则为兴趣分类（接口不同）
      final api = (category.id.length < 7)
          ? "https://live.kuaishou.com/live_api/gameboard/list"
          : "https://live.kuaishou.com/live_api/non-gameboard/list";
      final result = await HttpClient.instance.getJson(
        api,
        queryParameters: {
          "filterType": 0,
          "pageSize": 20,
          "gameId": category.id,
          "page": page,
        },
        header: headers,
      );
      final data = (result is Map) ? result["data"] : null;
      final raw = (data is Map) ? data["list"] : null;
      final list = (raw is List) ? raw : const [];
      final items = <LiveRoomItem>[];
      for (final item in list) {
        if (item is! Map) continue;
        final author = (item["author"] as Map?) ?? const {};
        items.add(LiveRoomItem(
          roomId: author["id"]?.toString() ?? "",
          title: item["caption"]?.toString() ?? "",
          cover: _wrapPoster(item["poster"]),
          userName: author["name"]?.toString() ?? "",
          online: int.tryParse(item["watchingCount"]?.toString() ?? "0") ?? 0,
        ));
      }
      final hasMore = list.length >= 20;
      return LiveCategoryResult(hasMore: hasMore, items: items);
    } catch (e) {
      CoreLog.error(e);
      return LiveCategoryResult(hasMore: false, items: []);
    }
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    if (page > 1) {
      // 快手 home/list 接口不支持翻页
      return LiveCategoryResult(hasMore: false, items: []);
    }
    try {
      await _ensureCookie();
      final result = await HttpClient.instance.getJson(
        "https://live.kuaishou.com/live_api/home/list",
        queryParameters: {},
        header: headers,
      );
      final data = (result is Map) ? result["data"] : null;
      final raw = (data is Map) ? data["list"] : null;
      final list = (raw is List) ? raw : const [];
      final items = <LiveRoomItem>[];
      for (final group in list) {
        if (group is! Map) continue;
        final games = group["gameLiveInfo"];
        if (games is! List) continue;
        for (final game in games) {
          if (game is! Map) continue;
          final liveInfo = game["liveInfo"];
          if (liveInfo is! List) continue;
          for (final live in liveInfo) {
            if (live is! Map) continue;
            final author = (live["author"] as Map?) ?? const {};
            final gameInfo = (live["gameInfo"] as Map?) ?? const {};
            final desc = author["description"]?.toString().replaceAll(
                    "\n", " ") ??
                "";
            items.add(LiveRoomItem(
              roomId: author["id"]?.toString() ?? "",
              title: desc.isNotEmpty ? desc : (author["name"]?.toString() ?? ""),
              cover: _wrapPoster(gameInfo["poster"]),
              userName: author["name"]?.toString() ?? "",
              online:
                  int.tryParse(live["watchingCount"]?.toString() ?? "0") ?? 0,
            ));
          }
        }
      }
      return LiveCategoryResult(hasMore: false, items: items);
    } catch (e) {
      CoreLog.error(e);
      return LiveCategoryResult(hasMore: false, items: []);
    }
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    Map? state;
    Map firstNode = const {};
    // _fetchRoomState 内部已经做了"完整 cookie → 匿名 cookie → cdn 备用接口"3 策略尝试，
    // 这里只做"反爬错误页/空 SSR"识别后的整体重试，最多 2 轮。
    for (int attempt = 0; attempt < 2; attempt++) {
      await _ensureCookie(force: attempt > 0);
      state = await _fetchRoomState(roomId);
      if (state == null) {
        if (attempt == 1) {
          throw Exception("快手直播间数据解析失败，请稍后重试");
        }
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      firstNode = _resolvePlayListFirst(state);
      // 检测 errorType.type==22（典型反爬错误页），刷新 cookie 整体重试
      final err = firstNode["errorType"];
      final errType = (err is Map) ? err["type"] : null;
      if (errType == 22 || errType == "22") {
        if (attempt < 1) {
          await Future.delayed(const Duration(milliseconds: 500));
          continue;
        }
      }
      // SSR 中拿到了 playList 节点，但 liveStream 为空且 author 也为空，
      // 多半是被反爬投放了"空 SSR"。整体刷新 cookie 再试一次。
      final ls = firstNode["liveStream"] ?? firstNode["livestream"];
      final au = firstNode["author"] ?? firstNode["principal"];
      final emptySsr = (ls is! Map || ls.isEmpty) && (au is! Map || au.isEmpty);
      if (emptySsr && attempt < 1) {
        await Future.delayed(const Duration(milliseconds: 500));
        continue;
      }
      break;
    }
    final url = "https://live.kuaishou.com/u/$roomId";

    final liveStream =
        (firstNode["liveStream"] ?? firstNode["livestream"] ?? const {}) as Map;
    Map author =
        (firstNode["author"] ?? firstNode["principal"] ?? const {}) as Map;
    final gameInfo = (firstNode["gameInfo"] ?? const {}) as Map;
    final config = (firstNode["config"] ?? const {}) as Map;

    // 开播判定：尽量宽松，覆盖快手 SSR 不同版本的字段
    bool isLive = firstNode["isLiving"] == true ||
        firstNode["living"] == true ||
        liveStream["isLive"] == true ||
        liveStream["living"] == true ||
        liveStream["status"]?.toString() == "1" ||
        liveStream["status"]?.toString() == "2" ||
        liveStream["status"]?.toString().toUpperCase() == "LIVING" ||
        config["living"] == true ||
        config["status"]?.toString() == "1" ||
        (liveStream["id"]?.toString() ?? "").isNotEmpty ||
        (config["liveStreamId"]?.toString() ?? "").isNotEmpty ||
        (liveStream["playUrls"] is List &&
            (liveStream["playUrls"] as List).isNotEmpty) ||
        (liveStream["playUrls"] is Map &&
            (liveStream["playUrls"] as Map).isNotEmpty) ||
        (config["multiResolutionPlayUrls"] is List &&
            (config["multiResolutionPlayUrls"] as List).isNotEmpty) ||
        (liveStream["multiResolutionPlayUrls"] is List &&
            (liveStream["multiResolutionPlayUrls"] as List).isNotEmpty);

    // 兜底：仅当 SSR 完全没拿到开播信号时，用 search/author 反查确认在播 +
    // 补全主播 UI 信息（id / name / avatar / description）。
    // 注意：playUrls 仍来自 SSR；本兜底只用于消除"明明在播却显示未开播"的体验回退。
    if (!isLive) {
      final apiAuthor = await _verifyLivingBySearch(roomId);
      if (apiAuthor != null) {
        isLive = true;
        final filled = <String, dynamic>{...author};
        void fillIfEmpty(String key, dynamic value) {
          if (value == null) return;
          final str = value.toString();
          if (str.isEmpty) return;
          final existing = filled[key]?.toString() ?? "";
          if (existing.isEmpty) filled[key] = value;
        }

        fillIfEmpty("id", apiAuthor["id"]);
        fillIfEmpty("name", apiAuthor["name"]);
        fillIfEmpty("avatar", apiAuthor["avatar"]);
        fillIfEmpty("description", apiAuthor["description"]);
        fillIfEmpty("originUserId", apiAuthor["originUserId"]);
        author = filled;
        firstNode = {
          ...firstNode,
          "isLiving": true,
          "author": filled,
        };
      }
    }

    // 合并 liveStream + config 为 data，保证清晰度提取能访问 multiResolutionPlayUrls
    // 注意：config.watchingCount 才是页面 top-count 实时在线观众数，
    // liveStream.watchingCount 通常不存在，gameInfo.watchingCount 是游戏品类总人数（不适用）。
    // 因此 config 中的 watchingCount / multiResolutionPlayUrls 允许覆盖 liveStream。
    const kConfigPreferredKeys = {"watchingCount", "multiResolutionPlayUrls"};
    final mergedData = <String, dynamic>{};
    liveStream.forEach((k, v) {
      mergedData[k.toString()] = v;
    });
    config.forEach((k, v) {
      final key = k.toString();
      if (kConfigPreferredKeys.contains(key) || !mergedData.containsKey(key)) {
        mergedData[key] = v;
      }
    });

    final userAvatar = (author["avatar"] ?? author["headUrl"] ?? "").toString();
    final userName = (author["name"] ?? author["nickname"] ?? "").toString();
    final descRaw = author["description"]?.toString() ?? "";
    final desc = descRaw.replaceAll("\n", " ");
    final title = (liveStream["caption"] ??
            liveStream["title"] ??
            config["caption"] ??
            (desc.isNotEmpty ? desc : userName))
        .toString();
    final cover = _wrapPoster(liveStream["poster"] ??
        liveStream["coverUrl"] ??
        config["rtCoverUrl"] ??
        config["coverUrl"]);
    // 观众数优先级：config.watchingCount（真实房间人数）> liveStream.watchingCount
    //             > liveStream.audienceCount > 在 playList[0] 子树中递归搜索
    //             > gameInfo.watchingCount（兜底，实为游戏品类总人数）
    int online = int.tryParse(config["watchingCount"]?.toString() ??
            liveStream["watchingCount"]?.toString() ??
            liveStream["displayWatchingCount"]?.toString() ??
            liveStream["audienceCount"]?.toString() ??
            "0") ??
        0;
    if (online == 0) {
      online = _scanRoomWatchingCount(firstNode);
    }
    if (online == 0) {
      online =
          int.tryParse(gameInfo["watchingCount"]?.toString() ?? "0") ?? 0;
    }

    String? showTime;
    final startTime = liveStream["startTime"] ??
        liveStream["createTime"] ??
        liveStream["startPlayTime"];
    if (startTime != null) {
      var ts = int.tryParse(startTime.toString()) ?? 0;
      if (ts > 0) {
        if (ts > 1000000000000) ts = ts ~/ 1000;
        showTime = ts.toString();
      }
    }

    return LiveRoomDetail(
      cover: cover,
      online: online,
      roomId: roomId,
      title: title,
      userName: userName,
      userAvatar: userAvatar,
      introduction: desc.isNotEmpty ? desc : title,
      notice: "",
      status: isLive,
      data: mergedData,
      danmakuData: KuaishouDanmakuArgs(
        liveStreamId: liveStream["id"]?.toString() ?? "",
        principalId: author["id"]?.toString() ?? roomId,
        caption: userName,
      ),
      url: url,
      showTime: showTime,
    );
  }

  /// 获取直播间所有可用清晰度（按"等级 → 码率"降序排序，列表[0] 即为**最高清晰度**）。
  ///
  /// 解析顺序（任一命中即用，避免重复计入）：
  /// 1. `multiResolutionPlayUrls`：同清晰度多 CDN URL（最完整、最权威）
  /// 2. `playUrls.{h264|h265|hevc}.adaptationSet.representation`：分编码清晰度组
  /// 3. `playUrls`（List 形式）：扫平后的 URL 列表（旧版 SSR）
  /// 4. `lebPlayUrls` / `webRTCPlayUrls` / `lhlsPlayUrls`：边缘 / 低延迟流（兜底）
  /// 5. `hlsPlayUrl`：单条 HLS 流（最弱兜底）
  ///
  /// 调用方 [LiveRoomController.getPlayQualites] 会按用户设置的画质等级（最高/中/最低）
  /// 选择 currentQuality 索引，最高时取 0（即本方法返回列表的首个元素），
  /// 因此**返回列表必须保证首项是清晰度最高、码率最高、CDN 最优**的那一组。
  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    final qualityMap = <String, _KuaishouQuality>{};
    try {
      final dataRaw = detail.data;
      if (dataRaw is! Map) return [];
      final data = Map<String, dynamic>.from(
          dataRaw.map((k, v) => MapEntry(k.toString(), v)));

      // ===== 策略 1：multiResolutionPlayUrls（最完整，覆盖原画/蓝光/超清/高清/流畅） =====
      _extractMultiResolutionPlayUrls(data["multiResolutionPlayUrls"], qualityMap);

      // ===== 策略 2：playUrls.{h264|h265|hevc}.adaptationSet.representation =====
      if (qualityMap.isEmpty) {
        final adapts = <Map>[];
        void addList(dynamic raw) {
          if (raw is! List) return;
          for (final v in raw) {
            if (v is Map) adapts.add(v);
          }
        }

        // playUrls 可能是 Map（新版 SSR）或 List（旧版 SSR）
        final pu = data["playUrls"];
        if (pu is Map) {
          if (pu["h264"] is Map) adapts.add(pu["h264"] as Map);
          if (pu["hevc"] is Map) adapts.add(pu["hevc"] as Map);
          if (pu["h265"] is Map) adapts.add(pu["h265"] as Map);
        } else if (pu is List) {
          addList(pu);
        }
        if (data["h264"] is Map) adapts.add(data["h264"] as Map);
        if (data["h265"] is Map) adapts.add(data["h265"] as Map);
        addList(data["adaptiveManifest"]);

        for (final adapt in adapts) {
          final adaptSet = adapt["adaptationSet"];
          List? reps;
          if (adaptSet is Map && adaptSet["representation"] is List) {
            reps = adaptSet["representation"] as List;
          } else if (adapt["representation"] is List) {
            reps = adapt["representation"] as List;
          }
          if (reps == null) continue;
          for (final rep in reps) {
            if (rep is! Map) continue;
            final name = (rep["name"] ??
                    rep["qualityType"] ??
                    rep["qualityLabel"] ??
                    "默认")
                .toString()
                .trim();
            final url = rep["url"]?.toString() ?? "";
            if (url.isEmpty) continue;
            // 优先取 maxBitrate，没有再退回 bitrate
            final bitrate = int.tryParse(rep["maxBitrate"]?.toString() ??
                    rep["bitrate"]?.toString() ??
                    "0") ??
                0;
            final level = int.tryParse(rep["level"]?.toString() ?? "0") ?? 0;
            final key = _normalizeQualityName(name);
            final exist = qualityMap[key];
            if (exist == null) {
              qualityMap[key] = _KuaishouQuality(
                name: key,
                bitrate: bitrate,
                level: level,
                urls: [url],
              );
            } else if (!exist.urls.contains(url)) {
              exist.urls.add(url);
            }
          }
        }
      }

      // ===== 策略 3：扫平的 playUrls（旧版 SSR） =====
      if (qualityMap.isEmpty) {
        final flat = data["playUrls"];
        if (flat is List) {
          final urls = <String>[];
          for (final u in flat) {
            if (u is Map) {
              final ux = u["url"]?.toString() ?? "";
              if (ux.isNotEmpty) urls.add(ux);
            } else if (u is String && u.isNotEmpty) {
              urls.add(u);
            }
          }
          if (urls.isNotEmpty) {
            qualityMap["默认"] = _KuaishouQuality(
              name: "默认",
              bitrate: 0,
              level: 0,
              urls: urls,
            );
          }
        }
      }

      // ===== 策略 4：lebPlayUrls / webRTCPlayUrls / lhlsPlayUrls 等边缘流兜底 =====
      if (qualityMap.isEmpty) {
        for (final key in const [
          "lebPlayUrls",
          "webRTCPlayUrls",
          "lhlsPlayUrls",
        ]) {
          _extractMultiResolutionPlayUrls(data[key], qualityMap);
          if (qualityMap.isNotEmpty) break;
        }
      }

      // ===== 策略 5：hlsPlayUrl（单条 HLS 流，最后兜底） =====
      if (qualityMap.isEmpty) {
        for (final key in const [
          "hlsPlayUrl",
          "playUrl",
          "playUrlH265",
        ]) {
          final s = data[key]?.toString() ?? "";
          if (s.isNotEmpty) {
            qualityMap["默认"] = _KuaishouQuality(
              name: "默认",
              bitrate: 0,
              level: 0,
              urls: [s],
            );
            break;
          }
        }
      }

      // 按"等级 → 码率"降序排序，list[0] 即为最高清晰度
      final list = qualityMap.values.toList()
        ..sort((a, b) {
          final c = b.level.compareTo(a.level);
          if (c != 0) return c;
          return b.bitrate.compareTo(a.bitrate);
        });
      return list
          .map((q) => LivePlayQuality(
                quality: q.name,
                data: q.urls,
              ))
          .toList();
    } catch (e) {
      CoreLog.error(e);
    }
    return [];
  }

  /// 解析快手 multiResolutionPlayUrls / lebPlayUrls / webRTCPlayUrls 等"同清晰度多 CDN"结构。
  /// 这些字段统一是 `[{name, level, urls: [{url, bitrate}, ...]}, ...]`。
  void _extractMultiResolutionPlayUrls(
      dynamic multi, Map<String, _KuaishouQuality> qualityMap) {
    if (multi is! List) return;
    for (final group in multi) {
      if (group is! Map) continue;
      final name =
          (group["name"] ?? group["shortName"] ?? group["qualityType"] ?? "默认")
              .toString()
              .trim();
      final level = int.tryParse(group["level"]?.toString() ?? "0") ?? 0;
      final urlsRaw = group["urls"];
      if (urlsRaw is! List) continue;
      int bitrate = 0;
      final urlList = <String>[];
      for (final u in urlsRaw) {
        if (u is Map) {
          final ux = u["url"]?.toString() ?? "";
          if (ux.isNotEmpty) urlList.add(ux);
          // 优先 maxBitrate，没有再回退 bitrate
          final br = int.tryParse(u["maxBitrate"]?.toString() ??
                  u["bitrate"]?.toString() ??
                  "0") ??
              0;
          if (br > bitrate) bitrate = br;
        } else if (u is String && u.isNotEmpty) {
          urlList.add(u);
        }
      }
      if (urlList.isEmpty) continue;
      final key = _normalizeQualityName(name);
      final exist = qualityMap[key];
      if (exist == null) {
        qualityMap[key] = _KuaishouQuality(
          name: key,
          bitrate: bitrate,
          level: level,
          urls: urlList,
        );
      } else {
        for (final u in urlList) {
          if (!exist.urls.contains(u)) exist.urls.add(u);
        }
      }
    }
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    final raw = quality.data;
    final urls = <String>[];
    if (raw is List) {
      for (var u in raw) {
        final s = u?.toString() ?? "";
        if (s.isNotEmpty) urls.add(s);
      }
    } else if (raw is String && raw.isNotEmpty) {
      urls.add(raw);
    }
    return LivePlayUrl(urls: urls);
  }

  /// 规范化快手清晰度名称
  String _normalizeQualityName(String raw) {
    final lower = raw.toLowerCase();
    // 快手“蓝光 4M / 蓝光 质臻”该区分，保留原名以免同名合并
    if (raw.contains("原画") || lower.contains("origin")) return "原画";
    if (raw.contains("质臻")) return "蓝光质臻";
    if (raw.contains("蓝光")) return raw.trim();
    if (raw.contains("超清") || lower.contains("super")) return "超清";
    if (raw.contains("高清") || lower.contains("high")) return "高清";
    if (raw.contains("流畅") ||
        lower.contains("standard") ||
        lower.contains("low")) {
      return "流畅";
    }
    return raw.isEmpty ? "默认" : raw;
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    try {
      var detail = await getRoomDetail(roomId: roomId);
      return detail.status;
    } catch (e) {
      CoreLog.error(e);
      return false;
    }
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) {
    return Future.value([]);
  }

  /// 房间搜索：调用主播搜索接口，把所有主播作为"房间"返回
  ///
  /// 设计变更（2026.05）：
  /// - 原实现只保留 living=true 的主播，搜"边路之怪"只返回 tingan666 一条
  ///   （唯一在播的，名字不绝对匹配），用户体验差。
  /// - 现在返回所有匹配主播：living=true 排前面 + keyword 精确匹配优先排序，
  ///   未开播的主播保留在结果中但 title 加 [未开播] 前缀提示，让用户能直接选择。
  /// - 进入未开播主播详情时，KuaishouSite.getRoomDetail 会显示"未开播"状态。
  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    final anchorResult = await searchAnchors(keyword, page: page);
    final items = anchorResult.items
        .map((e) => LiveRoomItem(
              roomId: e.roomId,
              title: e.liveStatus ? e.userName : "[未开播] ${e.userName}",
              cover: e.avatar,
              userName: e.userName,
              online: 0,
            ))
        .toList();
    return LiveSearchRoomResult(hasMore: anchorResult.hasMore, items: items);
  }

  /// 主播搜索：调用 live_api/search/author 接口
  ///
  /// 关键参数说明（与浏览器抓包一致）：
  /// - caver=2：协议版本号，缺失会被服务端识别为过期客户端并返回少量结果
  /// - count=15：单页条数（与浏览器默认一致）
  /// - key/keyword：搜索关键字（两者必须一致）
  /// - lssid/ussid：上次会话 id / 用户会话 id；首页可留空，分页时需带上一次响应中的 ussid
  ///
  /// 排序优先级：
  /// 1. living=true 优先于 living=false
  /// 2. 名称完全匹配优先于部分匹配
  /// 3. 名称包含 keyword 优先于不包含
  /// 4. 其余保持服务端返回顺序
  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    final trimmed = keyword.trim();
    if (trimmed.isEmpty) {
      return LiveSearchAnchorResult(hasMore: false, items: <LiveAnchorItem>[]);
    }
    try {
      await _ensureCookie();
      final ussid = _lastSearchUssid;
      final result = await HttpClient.instance.getJson(
        "https://live.kuaishou.com/live_api/search/author",
        queryParameters: {
          "caver": 2,
          "count": 15,
          "key": trimmed,
          "keyword": trimmed,
          "lssid": "",
          "page": page,
          "ussid": ussid,
        },
        header: headers,
      );
      final data = (result is Map) ? result["data"] : null;
      // 服务端在下一次请求时需要带上本次响应里的 ussid，保证分页连续。
      if (data is Map) {
        final newUssid = data["ussid"]?.toString() ?? "";
        if (newUssid.isNotEmpty) {
          _lastSearchUssid = newUssid;
        }
      }
      final raw = (data is Map) ? data["list"] : null;
      final list = (raw is List) ? raw : const [];
      final items = <LiveAnchorItem>[];
      for (final item in list) {
        if (item is! Map) continue;
        // id 字段是字符串型主播 eid（如 tingan666），是 https://live.kuaishou.com/u/{id} 的 id
        var id = item["id"]?.toString() ?? "";
        if (id.isEmpty) {
          // 兜底：服务端偶尔会丢 id 字段，退而用 originUserId（纯数字 ID）
          id = item["originUserId"]?.toString() ?? "";
        }
        if (id.isEmpty) continue;
        items.add(LiveAnchorItem(
          roomId: id,
          avatar: item["avatar"]?.toString() ?? "",
          userName: item["name"]?.toString() ?? "",
          liveStatus: item["living"] == true,
        ));
      }

      // 按"在播优先 + keyword 精确匹配优先"重新排序，
      // 解决用户痛点：搜"边路之怪"原本只能看到 tingan666，
      // 现在能完整看到所有同名主播并优先看到在播的。
      final lowerKw = trimmed.toLowerCase();
      int rank(LiveAnchorItem a) {
        final lowerName = a.userName.toLowerCase().trim();
        final exact = lowerName == lowerKw;
        final startsWith = lowerName.startsWith(lowerKw);
        final contains = lowerName.contains(lowerKw);
        // 4-bit 分数：bit3=living, bit2=exact, bit1=startsWith, bit0=contains
        int score = 0;
        if (a.liveStatus) score |= 1 << 3;
        if (exact) score |= 1 << 2;
        if (startsWith) score |= 1 << 1;
        if (contains) score |= 1 << 0;
        return score;
      }

      items.sort((a, b) => rank(b).compareTo(rank(a)));

      // 快手 search/author 单页固定 15 条，少于 15 视为最后一页
      final hasMore = list.length >= 15;
      return LiveSearchAnchorResult(hasMore: hasMore, items: items);
    } catch (e) {
      CoreLog.error(e);
      return LiveSearchAnchorResult(hasMore: false, items: <LiveAnchorItem>[]);
    }
  }

  /// 主播搜索接口的上一次会话 id，用于分页连续性。
  /// 不同 keyword 之间共享并无副作用，服务端只用它做去重 / 排序参考。
  String _lastSearchUssid = "";

  @override
  bool get supportLiveRank => false;

  @override
  Future<LiveRankResult> getLiveRanks({required LiveRoomDetail detail}) {
    return Future.value(LiveRankResult(title: "榜单", items: []));
  }

  // ===== 内部工具方法 =====

  /// 从 HTML 中提取 `window.__APOLLO_STATE__` / `window.__INITIAL_STATE__` JSON。
  /// 快手SSR下发的 INIT_STATE 对象不能用贪婪或懒匹配的正则提取（嵌套过深），
  /// 这里采用“指定错误位置后括号平衡”的方式，遇到字符串、转义符也能正确跳过。
  Map? _extractInitialState(String html) {
    const markers = [
      "window.__APOLLO_STATE__",
      "window.__INITIAL_STATE__",
      "window.INIT_STATE",
      "__APOLLO_STATE__",
      "__INITIAL_STATE__",
    ];
    for (final marker in markers) {
      final idx = html.indexOf(marker);
      if (idx < 0) continue;
      // 定位 "=" 之后的首个 '{'
      final eqIdx = html.indexOf('=', idx + marker.length);
      if (eqIdx < 0) continue;
      final braceStart = html.indexOf('{', eqIdx);
      if (braceStart < 0) continue;
      final end = _findMatchingBrace(html, braceStart);
      if (end < 0) continue;
      var raw = html.substring(braceStart, end + 1);
      // 替换 JS 中的 undefined 为 null，否则 jsonDecode 会报错
      raw = raw.replaceAll(RegExp(r":\s*undefined\b"), ": null");
      try {
        final obj = jsonDecode(raw);
        if (obj is Map) return obj;
      } catch (e) {
        CoreLog.error(e);
      }
    }
    return null;
  }

  /// 从指定位置的 '{' 开始，查找其对应的 '}'。考虑字符串、转义、注释跳过。
  int _findMatchingBrace(String s, int start) {
    int depth = 0;
    bool inString = false;
    String? quote;
    bool escape = false;
    for (int i = start; i < s.length; i++) {
      final c = s[i];
      if (escape) {
        escape = false;
        continue;
      }
      if (c == '\\') {
        escape = true;
        continue;
      }
      if (inString) {
        if (c == quote) {
          inString = false;
          quote = null;
        }
        continue;
      }
      if (c == '"' || c == "'" || c == '`') {
        inString = true;
        quote = c;
        continue;
      }
      if (c == '{') {
        depth++;
      } else if (c == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  /// 拉取直播间 HTML 并提取 __INITIAL_STATE__；
  ///
  /// **登录后的健壮性策略**（核心修复）：
  /// 经测试发现登录态 cookie 会让 SSR 偶发性返回精简数据（liveStream 缺 playUrls，
  /// 导致清晰度列表为空，无法播放）。因此本方法按"完整 cookie → 匿名 cookie → cdn 备用接口"
  /// 顺序尝试，每个 SSR 都会用 [_isStateUseful] 校验是否包含 playUrls，
  /// 不完整就继续向下兜底。直到任一策略拿到含 playUrls 的 SSR 为止。
  ///
  /// 这是"未登录可看 / 登录后看不了"问题的关键修复点。
  Future<Map?> _fetchRoomState(String roomId) async {
    // 策略 1：完整 cookies（匿名 + 登录），相当于浏览器登录状态
    final s1 = await _tryFetchRoomState(roomId, withUserCookie: true);
    if (_isStateUseful(s1)) return s1;

    // 策略 2：仅匿名 cookies（去掉 userCookie），登录态干扰下 SSR 反而不下发 playUrls
    // 时，回到匿名状态通常能拿到完整数据
    if (userCookie.isNotEmpty) {
      final s2 = await _tryFetchRoomState(roomId, withUserCookie: false);
      if (_isStateUseful(s2)) return s2;
      // 若匿名也不可用，但比策略 1 多了一些字段（如开播信号），优先返回它
      if (s2 != null && s1 == null) return s2;
    }

    // 策略 3：cdn/live/byUser 备用接口（HTML 路径不同，SSR 数据结构一致）
    final s3 = await _tryFetchRoomStateFromCdn(roomId);
    if (_isStateUseful(s3)) return s3;

    // 兜底：返回任一非空的 state，让上层能继续走兜底逻辑（如反查搜索接口）
    return s1 ?? s3;
  }

  /// 校验 SSR 数据是否"可用于播放"——核心标识：能在 playList 第一项里找到 playUrls 或 liveStream.id
  bool _isStateUseful(Map? state) {
    if (state == null) return false;
    try {
      final first = _resolvePlayListFirst(state);
      if (first.isEmpty) return false;
      final liveStream =
          (first["liveStream"] ?? first["livestream"] ?? const {}) as Map;
      final config = (first["config"] ?? const {}) as Map;
      // 1. 有 multiResolutionPlayUrls → 完整可播
      final mp1 = liveStream["multiResolutionPlayUrls"];
      final mp2 = config["multiResolutionPlayUrls"];
      if (mp1 is List && mp1.isNotEmpty) return true;
      if (mp2 is List && mp2.isNotEmpty) return true;
      // 2. 有 playUrls.h264/h265 结构 → 完整可播
      final pu = liveStream["playUrls"];
      if (pu is Map &&
          (pu["h264"] is Map ||
              pu["h265"] is Map ||
              pu["hevc"] is Map)) {
        return true;
      }
      if (pu is List && pu.isNotEmpty) return true;
      return false;
    } catch (e) {
      CoreLog.error(e);
      return false;
    }
  }

  /// 单次尝试抓取主页 SSR（按 [withUserCookie] 决定是否带登录 cookie）
  Future<Map?> _tryFetchRoomState(
    String roomId, {
    required bool withUserCookie,
  }) async {
    try {
      final reqHeaders = withUserCookie ? headers : _anonymousHeaders();
      final html = await HttpClient.instance.getText(
        "https://live.kuaishou.com/u/$roomId",
        queryParameters: {},
        header: reqHeaders,
      );
      return _extractInitialState(html);
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 从备用 cdn 路径抓取 SSR
  Future<Map?> _tryFetchRoomStateFromCdn(String roomId) async {
    try {
      final mHtml = await HttpClient.instance.getText(
        "https://live.kuaishou.com/cdn/live/byUser/$roomId",
        queryParameters: {},
        header: headers,
      );
      return _extractInitialState(mHtml);
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 仅带匿名 cookie 的 headers（去除 userCookie，避免登录态干扰 SSR 下发）
  Map<String, String> _anonymousHeaders() {
    return {
      "User-Agent": kDesktopUserAgent,
      "Referer": "https://live.kuaishou.com/",
      "Accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      if (_cachedCookie.isNotEmpty) "Cookie": _cachedCookie,
    };
  }

  /// 兜底反查·通过 `live_api/search/author` 接口确认 [roomId] 是否正在开播。
  ///
  /// 这条路径**不返回 playUrls**，只用于：
  /// - 在 SSR + 拉流接口都失败时，确认主播确实在播（避免误判为未开播）
  /// - 顺便补全 author 信息（id / name / avatar / description / originUserId）
  ///
  /// 返回 null 表示主播未开播 / 搜索失败；否则返回搜索条目 Map。
  Future<Map<String, dynamic>?> _verifyLivingBySearch(String roomId) async {
    if (roomId.isEmpty) return null;
    try {
      // 与主搜索方法保持一致：必须带 caver=2，否则服务端返回的列表会被截断
      final result = await HttpClient.instance.getJson(
        "https://live.kuaishou.com/live_api/search/author",
        queryParameters: {
          "caver": 2,
          "count": 15,
          "key": roomId,
          "keyword": roomId,
          "lssid": "",
          "page": 1,
          "ussid": "",
        },
        header: headers,
      );
      final data = (result is Map) ? result["data"] : null;
      final list = (data is Map) ? data["list"] : null;
      if (list is! List || list.isEmpty) return null;
      Map? matched;
      for (final item in list) {
        if (item is! Map) continue;
        if ((item["id"]?.toString() ?? "") == roomId) {
          matched = item;
          break;
        }
      }
      if (matched == null) return null;
      if (matched["living"] != true) return null;
      return matched.map((k, v) => MapEntry(k.toString(), v));
    } catch (e) {
      CoreLog.error(e);
      return null;
    }
  }

  /// 从 INIT_STATE 中提取 `liveroom.playList[0]`。
  ///
  /// 快手 SSR 中当前主播一定排在 playList[0]；之前曾尝试用 roomId 匹配，
  /// 但 `author.id` 多为数字 originUserId，与 URL 路径里的字符串 eid 不等，
  /// 反而落到 fallback 分支选错节点，因此直接取首项是最稳的选择。
  Map _resolvePlayListFirst(Map state) {
    final liveroom = (_findKey(state, "liveroom") ?? state) as Map? ?? const {};
    final playListRaw = liveroom["playList"] ?? _findKey(liveroom, "playList");
    if (playListRaw is List && playListRaw.isNotEmpty) {
      final first = playListRaw.first;
      if (first is Map) return first;
    } else if (playListRaw is Map) {
      return playListRaw;
    }
    return const {};
  }

  /// 在 playList[0] 子树中递归搜索 watchingCount / displayWatchingCount /
  /// audienceCount 等字段，返回找到的最大正整数（避免 SSR 中字段路径不固定时取不到值）。
  /// 限制深度并跳过 gameInfo（其 watchingCount 是品类总人数）。
  int _scanRoomWatchingCount(dynamic node, {int depth = 0, bool inGameInfo = false}) {
    if (depth > 6 || node == null) return 0;
    const candidateKeys = [
      "watchingCount",
      "displayWatchingCount",
      "audienceCount",
      "watcherCount",
      "onlineCount",
      "realWatchingCount",
    ];
    int best = 0;
    if (node is Map) {
      // gameInfo 子树明确跳过 watchingCount（是品类总人数）
      if (!inGameInfo) {
        for (final k in candidateKeys) {
          if (!node.containsKey(k)) continue;
          final v = int.tryParse(node[k]?.toString() ?? "0") ?? 0;
          if (v > best) best = v;
        }
      }
      for (final entry in node.entries) {
        final key = entry.key.toString();
        final next = inGameInfo || key == "gameInfo";
        final r = _scanRoomWatchingCount(entry.value,
            depth: depth + 1, inGameInfo: next);
        if (r > best) best = r;
      }
    } else if (node is List) {
      for (final v in node) {
        final r = _scanRoomWatchingCount(v,
            depth: depth + 1, inGameInfo: inGameInfo);
        if (r > best) best = r;
      }
    }
    return best;
  }

  /// 在状态树中递归查找指定 key
  dynamic _findKey(dynamic node, String key) {
    if (node is Map) {
      if (node.containsKey(key)) return node[key];
      for (var v in node.values) {
        var r = _findKey(v, key);
        if (r != null) return r;
      }
    } else if (node is List) {
      for (var v in node) {
        var r = _findKey(v, key);
        if (r != null) return r;
      }
    }
    return null;
  }

}

/// 快手清晰度内部聚合类
class _KuaishouQuality {
  final String name;
  final int bitrate;
  final int level;
  final List<String> urls;
  _KuaishouQuality({
    required this.name,
    required this.bitrate,
    required this.urls,
    this.level = 0,
  });
}
