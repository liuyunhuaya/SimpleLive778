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
    final cookies = <String>[];
    if (_cachedCookie.isNotEmpty) cookies.add(_cachedCookie);
    if (userCookie.isNotEmpty) cookies.add(userCookie);
    return {
      "User-Agent": kDesktopUserAgent,
      "Referer": "https://live.kuaishou.com/",
      "Accept":
          "text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3",
      "Accept-Language": "zh-CN,zh;q=0.9,en;q=0.8",
      if (cookies.isNotEmpty) "Cookie": cookies.join("; "),
    };
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
    // 最多尝试 2 次：第一次失败/拿到 errorType=22 时强制重置 cookie 重试
    for (int attempt = 0; attempt < 2; attempt++) {
      await _ensureCookie(force: attempt > 0);
      state = await _fetchRoomState(roomId);
      if (state == null) {
        if (attempt == 1) {
          throw Exception("快手直播间数据解析失败，请稍后重试");
        }
        continue;
      }
      firstNode = _resolvePlayListFirst(state);
      // 检测 errorType.type==22（典型反爬错误页），刷新 cookie 重试
      final err = firstNode["errorType"];
      final errType = (err is Map) ? err["type"] : null;
      if (errType == 22 || errType == "22") {
        if (attempt == 0) continue; // 触发重试
      }
      break;
    }
    final url = "https://live.kuaishou.com/u/$roomId";

    final liveStream =
        (firstNode["liveStream"] ?? firstNode["livestream"] ?? const {}) as Map;
    final author =
        (firstNode["author"] ?? firstNode["principal"] ?? const {}) as Map;
    final gameInfo = (firstNode["gameInfo"] ?? const {}) as Map;
    final config = (firstNode["config"] ?? const {}) as Map;
    final isLive = firstNode["isLiving"] == true ||
        liveStream["isLive"] == true ||
        liveStream["status"]?.toString() == "1";

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

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    // 快手直播间清晰度资源有三种可用结构：
    // 1. config.multiResolutionPlayUrls：同一清晰度多 CDN URL（响应2.txt首选）
    // 2. liveStream.playUrls.h264 / h265 下的 adaptationSet.representation
    // 3. config.playUrls：扫平的 url 列表（备选）
    final qualityMap = <String, _KuaishouQuality>{};
    try {
      final data = detail.data as Map?;
      if (data == null) return [];

      // ===== 策略 1：multiResolutionPlayUrls（最完整） =====
      final multi = data["multiResolutionPlayUrls"];
      if (multi is List) {
        for (final group in multi) {
          if (group is! Map) continue;
          final name = (group["name"] ?? group["shortName"] ?? "默认")
              .toString()
              .trim();
          final level =
              int.tryParse(group["level"]?.toString() ?? "0") ?? 0;
          final urlsRaw = group["urls"];
          if (urlsRaw is! List) continue;
          int bitrate = 0;
          final urlList = <String>[];
          for (final u in urlsRaw) {
            if (u is Map) {
              final ux = u["url"]?.toString() ?? "";
              if (ux.isNotEmpty) urlList.add(ux);
              final br = int.tryParse(u["bitrate"]?.toString() ?? "0") ?? 0;
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

      // ===== 策略 2：playUrls.h264 / h265.adaptationSet.representation =====
      if (qualityMap.isEmpty) {
        final adapts = <Map>[];
        void addList(dynamic raw) {
          if (raw is! List) return;
          for (final v in raw) {
            if (v is Map) adapts.add(v);
          }
        }

        // playUrls 可能是 Map（响应2.txt）或 List（旧版）
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
            final name = (rep["name"] ?? rep["qualityType"] ?? "默认")
                .toString()
                .trim();
            final url = rep["url"]?.toString() ?? "";
            if (url.isEmpty) continue;
            final bitrate =
                int.tryParse(rep["bitrate"]?.toString() ?? "0") ?? 0;
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

      // ===== 策略3：扫平的 playUrls（后备，紧迫场景下只有1个默认质） =====
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

      // 后备乔：hlsPlayUrl
      if (qualityMap.isEmpty) {
        final hls = data["hlsPlayUrl"]?.toString() ?? "";
        if (hls.isNotEmpty) {
          qualityMap["默认"] = _KuaishouQuality(
            name: "默认",
            bitrate: 0,
            level: 0,
            urls: [hls],
          );
        }
      }

      // 优先按 level 降序（level 是快手官方清晰度等级），同级再按码率
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

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    // 快手不再有专门的房间搜索，直接走主播搜索后再判断在播状态
    final anchorResult = await searchAnchors(keyword, page: page);
    final items = anchorResult.items
        .where((e) => e.liveStatus)
        .map((e) => LiveRoomItem(
              roomId: e.roomId,
              title: e.userName,
              cover: e.avatar,
              userName: e.userName,
              online: 0,
            ))
        .toList();
    return LiveSearchRoomResult(hasMore: anchorResult.hasMore, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    try {
      await _ensureCookie();
      final result = await HttpClient.instance.getJson(
        "https://live.kuaishou.com/live_api/search/author",
        queryParameters: {
          "count": 15,
          "key": keyword,
          "keyword": keyword,
          "lssid": "",
          "page": page,
          "ussid": "",
        },
        header: headers,
      );
      final data = (result is Map) ? result["data"] : null;
      final raw = (data is Map) ? data["list"] : null;
      final list = (raw is List) ? raw : const [];
      final items = <LiveAnchorItem>[];
      for (final item in list) {
        if (item is! Map) continue;
        final id = item["id"]?.toString() ?? "";
        if (id.isEmpty) continue;
        items.add(LiveAnchorItem(
          roomId: id,
          avatar: item["avatar"]?.toString() ?? "",
          userName: item["name"]?.toString() ?? "",
          liveStatus: item["living"] == true,
        ));
      }
      // 快手 search/author 单页固定 15 条，少于 15 视为最后一页
      final hasMore = list.length >= 15;
      return LiveSearchAnchorResult(hasMore: hasMore, items: items);
    } catch (e) {
      CoreLog.error(e);
      return LiveSearchAnchorResult(hasMore: false, items: <LiveAnchorItem>[]);
    }
  }

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
  /// 主页失败时回退到 cdn 接口。
  Future<Map?> _fetchRoomState(String roomId) async {
    Map? state;
    try {
      final html = await HttpClient.instance.getText(
        "https://live.kuaishou.com/u/$roomId",
        queryParameters: {},
        header: headers,
      );
      state = _extractInitialState(html);
    } catch (e) {
      CoreLog.error(e);
    }
    if (state == null) {
      try {
        final mHtml = await HttpClient.instance.getText(
          "https://live.kuaishou.com/cdn/live/byUser/$roomId",
          queryParameters: {},
          header: headers,
        );
        state = _extractInitialState(mHtml);
      } catch (e) {
        CoreLog.error(e);
      }
    }
    return state;
  }

  /// 从 INIT_STATE 中提取 liveroom.playList[0]
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
