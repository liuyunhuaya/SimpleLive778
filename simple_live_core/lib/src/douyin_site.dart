import 'dart:convert';
import 'dart:math';

import 'package:simple_live_core/simple_live_core.dart';
import 'package:simple_live_core/src/common/convert_helper.dart';
import 'package:simple_live_core/src/common/http_client.dart';

class DouyinSite implements LiveSite {
  @override
  String id = "douyin";

  @override
  String name = "抖音直播";

  @override
  LiveDanmaku getDanmaku() =>
      DouyinDanmaku()..setSignatureFunction(getSignature);

  Future<String> Function(String, String) getAbogusUrl =
      (url, userAgent) async {
    throw Exception(
        "You must call setAbogusUrlFunction to set the function first");
  };

  void setAbogusUrlFunction(Future<String> Function(String, String) func) {
    getAbogusUrl = func;
  }

  Future<String> Function(String, String) getSignature =
      (roomId, uniqueId) async {
    throw Exception(
        "You must call setSignatureFunction to set the function first");
  };

  void setSignatureFunction(Future<String> Function(String, String) func) {
    getSignature = func;
  }

  /// 使用 QQBrowser User-Agent（参考原版 DouyinLiveRecorder）
  static const String kDefaultUserAgent =
      "Mozilla/5.0 (Windows NT 10.0; WOW64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/116.0.5845.97 Safari/537.36 Core/1.116.567.400 QQBrowser/19.7.6764.400";

  static const String kDefaultReferer = "https://live.douyin.com";

  static const String kDefaultAuthority = "live.douyin.com";

  /// 默认 Cookie - 只需要 ttwid 字段即可获取所有画质（包括蓝光）
  static const String kDefaultCookie = "ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511";
  
  /// 抖音重要Cookie字段说明：
  /// 1. ttwid - 设备指纹，有效期最长（几个月），最重要
  /// 2. s_v_web_id - 访客ID，有效期较长（约30天）
  /// 3. passport_csrf_token - CSRF令牌，有效期中等（约7天）
  /// 4. odin_tt - 设备追踪ID，有效期较长（约30天）
  /// 5. sid_guard - 会话保护，有效期中等（约7天）
  /// 6. uid_tt - 用户追踪ID，有效期较长（约30天）
  /// 7. sid_tt - 会话ID，有效期短（约1天）
  /// 8. sessionid - 登录会话，有效期短（约1天）
  /// 9. __ac_nonce - 临时验证，有效期很短（几分钟）
  /// 10. msToken - 微软令牌，有效期中等（约1天）
  
  /// 默认Cookie池（不可修改的原始列表）
  static const List<String> kDefaultCookiePool = [
    "ttwid=1%7CB1qls3GdnZhUov9o2NxOMxxYS2ff6OSvEWbv0ytbES4%7C1680522049%7C280d802d6d478e3e78d0c807f7c487e7ffec0ae4e5fdd6a0fe74c3c6af149511",
    "ttwid=1%7CCQUSKtvKnhhPr2-LZZPi8gotooa5g8mKBS2MTsVWqM0%7C1765287876%7C04a6d728a198c6a0e49695dbc66c8cc96959eff6d5119cf0f5ef2cf33dfe0f6b",
  ];
  
  /// Cookie池 - 可动态修改（由DouyinAccountService同步）
  static List<String> kCookiePool = List.from(kDefaultCookiePool);
  
  /// 当前使用的cookie索引
  static int _currentCookieIndex = 0;
  
  /// 记录每个cookie的最后使用时间和失败次数
  static final Map<String, DateTime> _cookieLastUsed = {};
  static final Map<String, int> _cookieFailCount = {};
  
  /// 获取下一个可用的cookie
  static String getNextCookie() {
    // 找到失败次数最少且超过冷却时间的cookie
    String? bestCookie;
    int minFailCount = 999;
    
    for (int i = 0; i < kCookiePool.length; i++) {
      String cookie = kCookiePool[i];
      int failCount = _cookieFailCount[cookie] ?? 0;
      DateTime? lastUsed = _cookieLastUsed[cookie];
      
      // 如果这个cookie从未使用过，直接使用
      if (lastUsed == null) {
        _currentCookieIndex = i;
        return cookie;
      }
      
      // 检查冷却时间（根据失败次数调整冷却时间）
      int cooldownSeconds = failCount * 30 + 10; // 基础10秒，每次失败增加30秒
      if (DateTime.now().difference(lastUsed).inSeconds > cooldownSeconds) {
        if (failCount < minFailCount) {
          minFailCount = failCount;
          bestCookie = cookie;
          _currentCookieIndex = i;
        }
      }
    }
    
    // 如果找到了合适的cookie，返回它
    if (bestCookie != null) {
      return bestCookie;
    }
    
    // 如果所有cookie都在冷却中，使用失败次数最少的
    _currentCookieIndex = (_currentCookieIndex + 1) % kCookiePool.length;
    return kCookiePool[_currentCookieIndex];
  }
  
  /// 标记当前cookie失败
  static void markCookieAsFailed() {
    String currentCookie = kCookiePool[_currentCookieIndex];
    _cookieFailCount[currentCookie] = (_cookieFailCount[currentCookie] ?? 0) + 1;
    _logDebug("Cookie #${_currentCookieIndex + 1} 失败次数: ${_cookieFailCount[currentCookie]}");
  }
  
  /// 重置cookie失败计数（成功时调用）
  static void resetCookieFailCount() {
    String currentCookie = kCookiePool[_currentCookieIndex];
    _cookieFailCount[currentCookie] = 0;
  }
  
  /// 获取当前cookie索引
  static int getCurrentCookieIndex() {
    return _currentCookieIndex;
  }
  
  /// 获取指定cookie的失败次数
  static int getCookieFailCount(String cookie) {
    return _cookieFailCount[cookie] ?? 0;
  }
  
  /// 用户设置的 cookie
  String cookie = "";
  
  static void _logDebug(String msg) {
    // 只使用 CoreLog，不使用 print  
    CoreLog.d("[Douyin] $msg");
  }

  Map<String, dynamic> headers = {
    "User-Agent": kDefaultUserAgent,
    "Referer": kDefaultReferer,
  };

  Future<Map<String, dynamic>> getRequestHeaders() async {
    try {
      // 如果用户已设置 cookie，直接使用用户的 cookie
      if (cookie.isNotEmpty) {
        headers["cookie"] = cookie;
        return headers;
      }

      // 使用cookie池系统
      String selectedCookie = getNextCookie();
      _cookieLastUsed[selectedCookie] = DateTime.now();
      
      headers["cookie"] = selectedCookie;
      _logDebug("使用Cookie #${_currentCookieIndex + 1}/${kCookiePool.length}");
      
      return headers;
    } catch (e) {
      CoreLog.error(e);
      // 如果出错，使用第一个cookie作为后备
      if (!(headers["cookie"]?.toString().isNotEmpty ?? false)) {
        headers["cookie"] = kCookiePool.first;
      }
      return headers;
    }
  }

  @override
  Future<List<LiveCategory>> getCategores() async {
    List<LiveCategory> categories = [];
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/",
      queryParameters: {},
      header: await getRequestHeaders(),
    );

    var renderData =
        RegExp(r'\{\\"pathname\\":\\"\/\\",\\"categoryData.*?\]\\n')
                .firstMatch(result)
                ?.group(0) ??
            "";
    
    // 检查是否成功获取到数据
    if (renderData.isEmpty) {
      throw Exception("无法获取抖音分类数据，可能是页面结构已变化");
    }
    
    var renderDataStr = renderData
        .trim()
        .replaceAll('\\"', '"')
        .replaceAll(r"\\", r"\")
        .replaceAll(']\\n', "");
    
    Map<String, dynamic> renderDataJson;
    try {
      renderDataJson = json.decode(renderDataStr);
    } catch (e) {
      if (e is FormatException) {
        throw Exception("抖音分类数据解析失败：${e.message}");
      }
      rethrow;
    }

    for (var item in renderDataJson["categoryData"]) {
      List<LiveSubCategory> subs = [];
      var id = '${item["partition"]["id_str"]},${item["partition"]["type"]}';
      for (var subItem in item["sub_partition"]) {
        var subCategory = LiveSubCategory(
          id: '${subItem["partition"]["id_str"]},${subItem["partition"]["type"]}',
          name: asT<String?>(subItem["partition"]["title"]) ?? "",
          parentId: id,
          pic: "",
        );
        subs.add(subCategory);
      }

      var category = LiveCategory(
        children: subs,
        id: id,
        name: asT<String?>(item["partition"]["title"]) ?? "",
      );
      subs.insert(
          0,
          LiveSubCategory(
            id: category.id,
            name: category.name,
            parentId: category.id,
            pic: "",
          ));
      categories.add(category);
    }
    return categories;
  }

  @override
  Future<LiveCategoryResult> getCategoryRooms(LiveSubCategory category,
      {int page = 1}) async {
    var ids = category.id.split(',');
    var partitionId = ids[0];
    var partitionType = ids[1];

    String serverUrl =
        "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
    var uri = Uri.parse(serverUrl)
        .replace(scheme: "https", port: 443, queryParameters: {
      "aid": '6383',
      "app_name": "douyin_web",
      "live_id": '1',
      "device_platform": "web",
      "language": "zh-CN",
      "enter_from": "link_share",
      "cookie_enabled": "true",
      "screen_width": "1980",
      "screen_height": "1080",
      "browser_language": "zh-CN",
      "browser_platform": "Win32",
      "browser_name": "Edge",
      "browser_version": "142.0.0.0",
      "browser_online": "true",
      "count": '15',
      "offset": ((page - 1) * 15).toString(),
      "partition": partitionId,
      "partition_type": partitionType,
      "req_from": '2'
    });
    var requestUrl = await getAbogusUrl(uri.toString(), kDefaultUserAgent);

    var result = await HttpClient.instance.getJson(
      requestUrl,
      header: await getRequestHeaders(),
    );

    var hasMore = (result["data"]["data"] as List).length >= 15;
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["data"]) {
      var roomItem = LiveRoomItem(
        roomId: item["web_rid"],
        title: item["room"]["title"].toString(),
        cover: item["room"]["cover"]["url_list"][0].toString(),
        userName: item["room"]["owner"]["nickname"].toString(),
        online: int.tryParse(
                item["room"]["room_view_stats"]["display_value"].toString()) ??
            0,
      );
      items.add(roomItem);
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveCategoryResult> getRecommendRooms({int page = 1}) async {
    String serverUrl =
        "https://live.douyin.com/webcast/web/partition/detail/room/v2/";
    var uri = Uri.parse(serverUrl)
        .replace(scheme: "https", port: 443, queryParameters: {
      "aid": '6383',
      "app_name": "douyin_web",
      "live_id": '1',
      "device_platform": "web",
      "language": "zh-CN",
      "enter_from": "link_share",
      "cookie_enabled": "true",
      "screen_width": "1980",
      "screen_height": "1080",
      "browser_language": "zh-CN",
      "browser_platform": "Win32",
      "browser_name": "Edge",
      "browser_version": "142.0.0.0",
      "browser_online": "true",
      "count": '15',
      "offset": ((page - 1) * 15).toString(),
      "partition": '720',
      "partition_type": '1',
      "req_from": '2'
    });
    var requestUrl = await getAbogusUrl(uri.toString(), kDefaultUserAgent);

    var result = await HttpClient.instance.getJson(
      requestUrl,
      header: await getRequestHeaders(),
    );

    var hasMore = (result["data"]["data"] as List).length >= 15;
    var items = <LiveRoomItem>[];
    for (var item in result["data"]["data"]) {
      var roomItem = LiveRoomItem(
        roomId: item["web_rid"],
        title: item["room"]["title"].toString(),
        cover: item["room"]["cover"]["url_list"][0].toString(),
        userName: item["room"]["owner"]["nickname"].toString(),
        online: int.tryParse(
                item["room"]["room_view_stats"]["display_value"].toString()) ??
            0,
      );
      items.add(roomItem);
    }
    return LiveCategoryResult(hasMore: hasMore, items: items);
  }

  @override
  Future<LiveRoomDetail> getRoomDetail({required String roomId}) async {
    // 有两种roomId，一种是webRid，一种是roomId
    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // roomId一般长度为19位，例如：7376429659866598196
    // webRid是固定的，用户每次开播都是同一个webRid
    // webRid一般长度为11-12位，例如：416144012050
    // 这里简单进行判断，如果roomId长度小于15，则认为是webRid
    if (roomId.length <= 16) {
      var webRid = roomId;
      return await getRoomDetailByWebRid(webRid);
    }

    return await getRoomDetailByRoomId(roomId);
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  /// - 返回直播间信息
  Future<LiveRoomDetail> getRoomDetailByRoomId(String roomId) async {
    // 读取房间信息
    var roomData = await _getRoomDataByRoomId(roomId);

    // 检查数据有效性
    if (roomData["data"] == null || 
        roomData["data"]["room"] == null) {
      throw Exception("Invalid room data structure from roomId API");
    }

    // 通过房间信息获取WebRid
    var webRid = roomData["data"]["room"]["owner"]["web_rid"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var room = roomData["data"]["room"];
    var owner = room["owner"];

    var status = asT<int?>(room["status"]) ?? 0;

    // roomId是一次性的，用户每次重新开播都会生成一个新的roomId
    // 所以如果roomId对应的直播间状态不是直播中，就通过webRid获取直播间信息
    if (status == 4) {
      var result = await getRoomDetailByWebRid(webRid);
      return result;
    }

    var roomStatus = status == 2;
    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    // 获取在线人数，优先使用 display_value（真实人数，和首页一致）
    int onlineCount = 0;
    if (roomStatus) {
      // 优先从 room_view_stats 获取真实人数（和首页展示一致）
      var roomViewStats = room["room_view_stats"];
      if (roomViewStats != null) {
        onlineCount = asT<int?>(roomViewStats["display_value"]) ?? 0;
      }
      // 如果 display_value 获取不到，才尝试从 stats.total_user 获取
      if (onlineCount == 0 && room["stats"] != null) {
        onlineCount = asT<int?>(room["stats"]["total_user"]) ?? 0;
      }
    }

    return LiveRoomDetail(
      roomId: webRid,
      title: room["title"].toString(),
      cover: roomStatus ? room["cover"]["url_list"][0].toString() : "",
      userName: owner["nickname"].toString(),
      userAvatar: owner["avatar_thumb"]["url_list"][0].toString(),
      online: onlineCount,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner["signature"].toString(),
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
        anchorId: owner?["id_str"]?.toString() ?? owner?["sec_uid"]?.toString() ?? "",
        secAnchorId: owner?["sec_uid"]?.toString() ?? "",
      ),
      data: room["stream_url"],
      showTime: _extractDouyinShowTime(room),
    );
  }

  /// 从抖音 room 对象中提取开播时间戳（秒），找不到时返回 null
  String? _extractDouyinShowTime(Map? room) {
    if (room == null) return null;
    // 尝试常见的开播时间字段
    final candidates = [
      room["create_time"],
      room["live_create_time"],
      room["start_time"],
      room["live_start_time"],
      room["active_time"],
    ];
    for (var v in candidates) {
      if (v == null) continue;
      var ts = int.tryParse(v.toString()) ?? 0;
      if (ts <= 0) continue;
      // 兼容毫秒/微秒时间戳
      if (ts > 1000000000000000) {
        ts = ts ~/ 1000000;
      } else if (ts > 1000000000000) {
        ts = ts ~/ 1000;
      }
      // 合理范围（2010 至 2099），过滤明显异常值
      if (ts > 1262304000 && ts < 4070908800) {
        return ts.toString();
      }
    }
    return null;
  }

  /// 通过WebRid获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> getRoomDetailByWebRid(String webRid) async {
    try {
      var result = await _getRoomDetailByWebRidApi(webRid);
      // 成功时重置失败计数
      resetCookieFailCount();
      return result;
    } catch (e) {
      CoreLog.error(e);
      // 标记当前cookie失败，触发切换
      String errorStr = e.toString();
      if (errorStr.contains("频繁") || errorStr.contains("444") || errorStr.contains("403") || errorStr.contains("格式")) {
        markCookieAsFailed();
      }
    }
    return await _getRoomDetailByWebRidHtml(webRid);
  }

  /// 通过WebRid访问直播间API，从API中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> _getRoomDetailByWebRidApi(String webRid) async {
    // 读取房间信息
    var data = await _getRoomDataByApi(webRid);
    
    // 检查数据有效性
    if (data["data"] == null || data["data"].isEmpty) {
      throw Exception("Invalid room data structure from API");
    }
    
    var roomData = data["data"][0];
    var userData = data["user"];
    var roomId = roomData["id_str"].toString();

    // 读取用户唯一ID，用于弹幕连接
    // 似乎这个参数不是必须的，先随机生成一个
    //var userUniqueId = await _getUserUniqueId(webRid);
    var userUniqueId = generateRandomNumber(12).toString();

    var owner = roomData["owner"];

    var roomStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;

    // 获取在线人数，优先使用 display_value（真实人数，和首页一致）
    int onlineCount = 0;
    if (roomStatus) {
      // 优先从 room_view_stats 获取真实人数（和首页展示一致）
      var roomViewStats = roomData["room_view_stats"];
      if (roomViewStats != null) {
        onlineCount = asT<int?>(roomViewStats["display_value"]) ?? 0;
      }
      // 如果 display_value 获取不到，才尝试从 stats.total_user 获取
      if (onlineCount == 0 && roomData["stats"] != null) {
        onlineCount = asT<int?>(roomData["stats"]["total_user"]) ?? 0;
      }
    }

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();
    return LiveRoomDetail(
      roomId: webRid,
      title: roomData["title"].toString(),
      cover: roomStatus ? roomData["cover"]["url_list"][0].toString() : "",
      userName: roomStatus
          ? owner["nickname"].toString()
          : userData["nickname"].toString(),
      userAvatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : userData["avatar_thumb"]["url_list"][0].toString(),
      online: onlineCount,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner?["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
        anchorId: (owner?["id_str"] ?? userData?["id_str"] ?? "").toString(),
        secAnchorId: (owner?["sec_uid"] ?? userData?["sec_uid"] ?? "").toString(),
      ),
      data: roomStatus ? roomData["stream_url"] : {},
      showTime: _extractDouyinShowTime(roomData),
    );
  }

  /// 通过WebRid访问直播间网页，从网页HTML中获取直播间信息
  /// - [webRid] 直播间RID
  /// - 返回直播间信息
  Future<LiveRoomDetail> _getRoomDetailByWebRidHtml(String webRid) async {
    var roomData = await _getRoomDataByHtml(webRid);
    var roomId = roomData["roomStore"]["roomInfo"]["room"]["id_str"].toString();
    
    // 安全获取user_unique_id，防止空指针
    var userUniqueId = "";
    try {
      if (roomData["userStore"] != null && 
          roomData["userStore"]["odin"] != null &&
          roomData["userStore"]["odin"]["user_unique_id"] != null) {
        userUniqueId = roomData["userStore"]["odin"]["user_unique_id"].toString();
      } else {
        userUniqueId = generateRandomNumber(12).toString();
      }
    } catch (e) {
      userUniqueId = generateRandomNumber(12).toString();
    }

    var room = roomData["roomStore"]["roomInfo"]["room"];
    var owner = room["owner"];
    var anchor = roomData["roomStore"]["roomInfo"]["anchor"];
    var roomStatus = (asT<int?>(room["status"]) ?? 0) == 2;

    // 主要是为了获取cookie,用于弹幕websocket连接
    var headers = await getRequestHeaders();

    return LiveRoomDetail(
      roomId: webRid,
      title: room["title"].toString(),
      cover: roomStatus ? room["cover"]["url_list"][0].toString() : "",
      userName: roomStatus
          ? owner["nickname"].toString()
          : anchor["nickname"].toString(),
      userAvatar: roomStatus
          ? owner["avatar_thumb"]["url_list"][0].toString()
          : anchor["avatar_thumb"]["url_list"][0].toString(),
      online: roomStatus
          ? asT<int?>(room["room_view_stats"]["display_value"]) ?? 0
          : 0,
      status: roomStatus,
      url: "https://live.douyin.com/$webRid",
      introduction: owner?["signature"]?.toString() ?? "",
      notice: "",
      danmakuData: DouyinDanmakuArgs(
        webRid: webRid,
        roomId: roomId,
        userId: userUniqueId,
        cookie: headers["cookie"],
        anchorId: (owner?["id_str"] ?? anchor?["id_str"] ?? "").toString(),
        secAnchorId: (owner?["sec_uid"] ?? anchor?["sec_uid"] ?? "").toString(),
      ),
      data: roomStatus ? room["stream_url"] : {},
      showTime: _extractDouyinShowTime(room),
    );
  }

  /// 读取用户的唯一ID
  /// - [webRid] 直播间RID
  // ignore: unused_element
  Future<String> _getUserUniqueId(String webRid) async {
    try {
      var webInfo = await _getRoomDataByHtml(webRid);
      // 安全检查嵌套对象
      if (webInfo["userStore"] != null && 
          webInfo["userStore"]["odin"] != null &&
          webInfo["userStore"]["odin"]["user_unique_id"] != null) {
        return webInfo["userStore"]["odin"]["user_unique_id"].toString();
      }
      return generateRandomNumber(12).toString();
    } catch (e) {
      return generateRandomNumber(12).toString();
    }
  }

  /// 进入直播间前需要先获取cookie
  /// - [webRid] 直播间RID
  Future<String> _getWebCookie(String webRid) async {
    var headResp = await HttpClient.instance.head(
      "https://live.douyin.com/$webRid",
      header: headers,
    );
    var dyCookie = "";
    headResp.headers["set-cookie"]?.forEach((element) {
      var cookie = element.split(";")[0];
      if (cookie.contains("ttwid")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("__ac_nonce")) {
        dyCookie += "$cookie;";
      }
      if (cookie.contains("msToken")) {
        dyCookie += "$cookie;";
      }
    });
    return dyCookie;
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByHtml(String webRid) async {
    var dyCookie = await _getWebCookie(webRid);
    var result = await HttpClient.instance.getText(
      "https://live.douyin.com/$webRid",
      queryParameters: {},
      header: {
        "User-Agent": kDefaultUserAgent,
        "Referer": "https://live.douyin.com/",
        "Cookie": dyCookie,
      },
    );

    var renderData = RegExp(r'\{\\"state\\":\{\\"appStore.*?\]\\n')
            .firstMatch(result)
            ?.group(0) ??
        "";
    var str = renderData
        .trim()
        .replaceAll('\\"', '"')
        .replaceAll(r"\\", r"\")
        .replaceAll(']\\n', "");
    
    // 检查是否成功获取到数据
    if (str.isEmpty || str.length < 2) {
      throw Exception("抖音直播间页面加载失败，可能是访问频率过高或直播间不存在。请稍后再试。");
    }
    
    try {
      var renderDataJson = json.decode(str);
      return renderDataJson["state"];
    } catch (e) {
      // 如果是JSON解析错误，提供更友好的错误信息
      if (e is FormatException) {
        throw Exception("抖音直播间数据解析失败，可能页面结构已变化。错误详情：${e.message}");
      }
      rethrow;
    }
  }

  /// 通过webRid获取直播间Web信息
  /// - [webRid] 直播间RID
  Future<Map> _getRoomDataByApi(String webRid) async {
    String serverUrl = "https://live.douyin.com/webcast/room/web/enter/";
        // 提前获取 headers
    var requestHeader = await getRequestHeaders();

    // 使用动态 Referer（包含房间号，参考 DouyinLiveRecorder）
    requestHeader["Referer"] = "https://live.douyin.com/$webRid";
    var uri = Uri.parse(serverUrl)
        .replace(scheme: "https", port: 443, queryParameters: {
      "aid": '6383',
      "app_name": "douyin_web",
      "live_id": '1',
      "device_platform": "web",
      "language": "zh-CN",
      "browser_language": "zh-CN",
      "browser_name": "Edge",
      "browser_version": "125.0.0.0",
      "web_rid": webRid,
      "msToken": "",
    });
    var requestUrl = await getAbogusUrl(uri.toString(), kDefaultUserAgent);

    var result = await HttpClient.instance.getJson(
      requestUrl,
      header: requestHeader,
    );

    if (result is! Map) {
      throw Exception("抖音接口返回格式异常");
    }

    return result["data"];
  }

  /// 通过roomId获取直播间信息
  /// - [roomId] 直播间ID
  Future<Map> _getRoomDataByRoomId(String roomId) async {
    var result = await HttpClient.instance.getJson(
      'https://webcast.amemv.com/webcast/room/reflow/info/',
      queryParameters: {
        "type_id": 0,
        "live_id": 1,
        "room_id": roomId,
        "sec_user_id": "",
        "version_code": "99.99.99",
        "app_id": 6383,
      },
      header: await getRequestHeaders(),
    );
    
    if (result == null) {
      throw Exception("Failed to get room data by roomId: result is null");
    }
    
    return result;
  }

  @override
  Future<List<LivePlayQuality>> getPlayQualites(
      {required LiveRoomDetail detail}) async {
    List<LivePlayQuality> qualities = [];
    try {
      var liveCoreData = detail.data["live_core_sdk_data"];

      if (liveCoreData == null) {
        return qualities;
      }
      var pullData = liveCoreData["pull_data"];

      if (pullData == null) {
        return qualities;
      }

      var options = pullData["options"];

      var qulityList = options?["qualities"];

      var streamData = pullData["stream_data"]?.toString() ?? "";

      if (!streamData.startsWith('{')) {
        var flvList =
            (detail.data["flv_pull_url"] as Map).values.cast<String>().toList();
        var hlsList = (detail.data["hls_pull_url_map"] as Map)
            .values
            .cast<String>()
            .toList();
        for (var quality in qulityList) {
          int level = quality["level"];
          List<String> urls = [];
          var flvIndex = flvList.length - level;
          if (flvIndex >= 0 && flvIndex < flvList.length) {
            urls.add(flvList[flvIndex]);
          }
          var hlsIndex = hlsList.length - level;
          if (hlsIndex >= 0 && hlsIndex < hlsList.length) {
            urls.add(hlsList[hlsIndex]);
          }
          var qualityItem = LivePlayQuality(
            quality: quality["name"],
            sort: level,
            data: urls,
          );
          if (urls.isNotEmpty) {
            qualities.add(qualityItem);
          }
        }
      } else {
        Map<String, dynamic> qualityData;
        try {
          var decodedData = json.decode(streamData);
          qualityData = Map<String, dynamic>.from(decodedData["data"] as Map);
        } catch (e) {
          if (e is FormatException) {
            CoreLog.error("解析streamData失败: ${e.message}");
            return qualities;
          }
          rethrow;
        }

        for (var quality in qulityList) {
          List<String> urls = [];

          var flvUrl =
              qualityData[quality["sdk_key"]]?["main"]?["flv"]?.toString();

          if (flvUrl != null && flvUrl.isNotEmpty) {
            urls.add(flvUrl);
          }
          var hlsUrl =
              qualityData[quality["sdk_key"]]?["main"]?["hls"]?.toString();

          if (hlsUrl != null && hlsUrl.isNotEmpty) {
            urls.add(hlsUrl);
          }

          var qualityItem = LivePlayQuality(
            quality: quality["name"],
            sort: quality["level"],
            data: urls,
          );
          if (urls.isNotEmpty) {
            qualities.add(qualityItem);
          }
        }
      }
    } catch (e, stackTrace) {
      CoreLog.error(e);
      CoreLog.error(stackTrace);
    }
    // var qualityData = json.decode(
    //     detail.data["live_core_sdk_data"]["pull_data"]["stream_data"])["data"];

    qualities.sort((a, b) => b.sort.compareTo(a.sort));
    _logDebug("获取到的画质列表: ${qualities.map((q) => q.quality).toList()}");
    return qualities;
  }

  @override
  Future<LivePlayUrl> getPlayUrls(
      {required LiveRoomDetail detail,
      required LivePlayQuality quality}) async {
    // 返回列表的副本，防止外部 clear() 影响原始数据
    return LivePlayUrl(urls: List<String>.from(quality.data));
  }

  /// 通过HTML页面抓取抖音直播搜索结果
  /// 抖音搜索页面SSR渲染包含直播间数据
  Future<List<Map<String, dynamic>>> _searchByHtml(String keyword) async {
    var dyCookie = "";
    try {
      var headResp = await HttpClient.instance.head(
        "https://www.douyin.com/root/search/${Uri.encodeComponent(keyword)}?type=live",
        header: {"User-Agent": kDefaultUserAgent},
      );
      headResp.headers["set-cookie"]?.forEach((element) {
        var c = element.split(";")[0];
        if (c.contains("ttwid") || c.contains("__ac_nonce") || c.contains("msToken")) {
          dyCookie += "$c;";
        }
      });
    } catch (_) {}

    if (dyCookie.isEmpty) {
      var requestHeaders = await getRequestHeaders();
      dyCookie = requestHeaders["cookie"] ?? "";
    }

    var html = await HttpClient.instance.getText(
      "https://www.douyin.com/root/search/${Uri.encodeComponent(keyword)}?type=live",
      queryParameters: {},
      header: {
        "User-Agent": kDefaultUserAgent,
        "Referer": "https://www.douyin.com/",
        "Cookie": dyCookie,
      },
    );

    // 从HTML中提取RENDER_DATA (URL编码的JSON)
    var renderMatch = RegExp(r'<script id="RENDER_DATA" type="application/json">(.*?)</script>')
        .firstMatch(html);
    if (renderMatch != null) {
      var encoded = renderMatch.group(1) ?? "";
      var decoded = Uri.decodeComponent(encoded);
      try {
        var renderData = json.decode(decoded);
        return _extractRoomsFromRenderData(renderData);
      } catch (_) {}
    }

    // 备用: 从script中提取 __RENDER_DATA__ 格式
    var stateMatch = RegExp(r'self\.__pace_f\.push.*?\\"roomInfos\\".*?\]\\n')
        .firstMatch(html);
    if (stateMatch != null) {
      try {
        var str = stateMatch.group(0) ?? "";
        str = str.replaceAll('\\"', '"').replaceAll(r'\\', r'\');
        var rooms = _extractRoomInfoFromString(str);
        if (rooms.isNotEmpty) return rooms;
      } catch (_) {}
    }

    return [];
  }

  /// 从RENDER_DATA中递归提取直播间信息
  List<Map<String, dynamic>> _extractRoomsFromRenderData(dynamic data) {
    var rooms = <Map<String, dynamic>>[];
    if (data is Map) {
      // 检查是否包含直播间数据
      if (data.containsKey("owner") && data.containsKey("title") && data.containsKey("id_str")) {
        rooms.add(Map<String, dynamic>.from(data));
        return rooms;
      }
      // 检查搜索结果列表
      if (data.containsKey("rawdata") || data.containsKey("lives")) {
        var rawdata = data["rawdata"] ?? data["lives"]?["rawdata"];
        if (rawdata != null) {
          try {
            var parsed = rawdata is String ? json.decode(rawdata) : rawdata;
            if (parsed is Map && parsed.containsKey("owner")) {
              rooms.add(Map<String, dynamic>.from(parsed));
            }
          } catch (_) {}
        }
      }
      // 递归搜索
      for (var value in data.values) {
        rooms.addAll(_extractRoomsFromRenderData(value));
      }
    } else if (data is List) {
      for (var item in data) {
        rooms.addAll(_extractRoomsFromRenderData(item));
      }
    }
    return rooms;
  }

  /// 从字符串中提取直播间信息
  List<Map<String, dynamic>> _extractRoomInfoFromString(String str) {
    var rooms = <Map<String, dynamic>>[];
    // 匹配所有类似直播间数据的JSON块
    var matches = RegExp(r'\{"id_str":"(\d+)","status":(\d+).*?"owner":\{.*?"nickname":"(.*?)"').allMatches(str);
    for (var match in matches) {
      try {
        var idStr = match.group(1) ?? "";
        if (idStr.isNotEmpty) {
          rooms.add({"id_str": idStr, "partial": true});
        }
      } catch (_) {}
    }
    return rooms;
  }

  /// 通过 info_by_scene API 获取直播间详细信息（搜索场景）
  Future<Map<String, dynamic>?> _getRoomInfoByScene(String roomId) async {
    try {
      var requestHeaders = await getRequestHeaders();
      var uri = Uri.parse("https://live.douyin.com/webcast/room/info_by_scene/")
          .replace(scheme: "https", port: 443, queryParameters: {
        "aid": "6383",
        "app_name": "douyin_web",
        "live_id": "1",
        "device_platform": "web",
        "language": "zh-CN",
        "cookie_enabled": "true",
        "screen_width": "1536",
        "screen_height": "864",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Edge",
        "browser_version": "146.0.0.0",
        "room_id": roomId,
        "scene": "douyin_pc_search",
        "channel": "channel_pc_web",
        "region": "cn",
        "device_type": "web_device",
        "os_version": "web",
        "version_code": "170400",
        "webcast_sdk_version": "2450",
      });

      var requlestUrl = uri.toString();
      try {
        requlestUrl = await getAbogusUrl(uri.toString(), kDefaultUserAgent);
      } catch (_) {
        // 签名失败则使用原始URL
      }

      var result = await HttpClient.instance.getJson(
        requlestUrl,
        queryParameters: {},
        header: {
          "Authority": "live.douyin.com",
          "accept": "application/json, text/plain, */*",
          "accept-language": "zh-CN,zh;q=0.9,en;q=0.8",
          "cookie": requestHeaders["cookie"] ?? "",
          "referer": "https://www.douyin.com/",
          "user-agent": kDefaultUserAgent,
        },
      );

      if (result != null && result["data"] != null) {
        return result["data"] is Map ? Map<String, dynamic>.from(result["data"]) : null;
      }
    } catch (e) {
      CoreLog.d("info_by_scene 失败 [roomId: $roomId]: $e");
    }
    return null;
  }

  /// 从直播间数据中提取 LiveRoomItem
  LiveRoomItem? _extractRoomItem(Map<String, dynamic> roomData) {
    try {
      var owner = roomData["owner"];
      if (owner == null) return null;

      String roomId = owner["web_rid"]?.toString() ?? "";
      if (roomId.isEmpty) {
        roomId = owner["display_id"]?.toString() ?? "";
      }
      if (roomId.isEmpty) {
        roomId = roomData["id_str"]?.toString() ?? "";
      }
      if (roomId.isEmpty || roomId == "0") return null;

      String userName = owner["nickname"]?.toString() ?? "";
      String title = roomData["title"]?.toString() ?? userName;
      String cover = "";
      int online = 0;

      // 封面
      if (roomData["cover"]?["url_list"] != null) {
        var urlList = roomData["cover"]["url_list"];
        if (urlList is List && urlList.isNotEmpty) {
          cover = urlList[0].toString();
        }
      }

      // 在线人数 - 优先 user_count，再试 stats
      online = asT<int?>(roomData["user_count"]) ?? 0;
      if (online == 0 && roomData["stats"] != null) {
        online = asT<int?>(roomData["stats"]["total_user"]) ?? 0;
        if (online == 0) {
          var userCountStr = roomData["stats"]?["user_count_str"]?.toString();
          if (userCountStr != null) {
            online = int.tryParse(userCountStr) ?? 0;
          }
        }
      }
      if (online == 0 && roomData["room_view_stats"] != null) {
        online = asT<int?>(roomData["room_view_stats"]["display_value"]) ?? 0;
      }

      return LiveRoomItem(
        roomId: roomId,
        title: title.isEmpty ? userName : title,
        cover: cover,
        userName: userName,
        online: online,
      );
    } catch (e) {
      return null;
    }
  }

  /// 从直播间数据中提取 LiveAnchorItem
  LiveAnchorItem? _extractAnchorItem(Map<String, dynamic> roomData) {
    try {
      var owner = roomData["owner"];
      if (owner == null) return null;

      String roomId = owner["web_rid"]?.toString() ?? "";
      if (roomId.isEmpty) {
        roomId = owner["display_id"]?.toString() ?? "";
      }
      if (roomId.isEmpty) {
        roomId = roomData["id_str"]?.toString() ?? "";
      }
      if (roomId.isEmpty || roomId == "0") return null;

      String userName = owner["nickname"]?.toString() ?? "";
      String avatar = "";
      bool liveStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;

      if (owner["avatar_thumb"]?["url_list"] != null) {
        var urlList = owner["avatar_thumb"]["url_list"];
        if (urlList is List && urlList.isNotEmpty) {
          avatar = urlList[0].toString();
        }
      }

      return LiveAnchorItem(
        roomId: roomId,
        avatar: avatar,
        userName: userName,
        liveStatus: liveStatus,
      );
    } catch (e) {
      return null;
    }
  }

  @override
  Future<LiveSearchRoomResult> searchRooms(String keyword,
      {int page = 1}) async {
    // 只支持第一页 (HTML方式)
    if (page > 1) {
      return LiveSearchRoomResult(hasMore: false, items: []);
    }

    var items = <LiveRoomItem>[];

    // 策略1: 通过HTML页面提取搜索结果
    try {
      var htmlRooms = await _searchByHtml(keyword);
      for (var roomData in htmlRooms) {
        var item = _extractRoomItem(roomData);
        if (item != null) {
          items.add(item);
        }
      }

      if (items.isNotEmpty) {
        return LiveSearchRoomResult(hasMore: false, items: items);
      }
    } catch (e) {
      CoreLog.d("HTML搜索失败: $e");
    }

    // 策略2: 通过 web/enter API 逐个查询（将关键词当作webRid尝试）
    // 用户可能直接输入了房间号或主播ID
    if (keyword.isNotEmpty && RegExp(r'^[\w\d_]+$').hasMatch(keyword)) {
      try {
        var data = await _getRoomDataByApi(keyword);
        if (data["data"] != null && data["data"].isNotEmpty) {
          var roomData = data["data"][0];
          var roomStatus = (asT<int?>(roomData["status"]) ?? 0) == 2;
          if (roomStatus) {
            var item = _extractRoomItem(roomData);
            if (item != null) {
              items.add(item);
              return LiveSearchRoomResult(hasMore: false, items: items);
            }
          }
        }
      } catch (_) {}
    }

    if (items.isEmpty) {
      throw Exception("抖音搜索暂时不可用，请尝试直接输入房间号进入直播间");
    }

    return LiveSearchRoomResult(hasMore: false, items: items);
  }

  @override
  Future<LiveSearchAnchorResult> searchAnchors(String keyword,
      {int page = 1}) async {
    if (page > 1) {
      return LiveSearchAnchorResult(hasMore: false, items: []);
    }

    var items = <LiveAnchorItem>[];

    // 策略1: 通过HTML页面提取搜索结果
    try {
      var htmlRooms = await _searchByHtml(keyword);
      for (var roomData in htmlRooms) {
        var item = _extractAnchorItem(roomData);
        if (item != null) {
          items.add(item);
        }
      }

      if (items.isNotEmpty) {
        return LiveSearchAnchorResult(hasMore: false, items: items);
      }
    } catch (e) {
      CoreLog.d("HTML主播搜索失败: $e");
    }

    // 策略2: 关键词当作房间号/用户ID直接查询
    if (keyword.isNotEmpty && RegExp(r'^[\w\d_]+$').hasMatch(keyword)) {
      try {
        var data = await _getRoomDataByApi(keyword);
        if (data["data"] != null && data["data"].isNotEmpty) {
          var roomData = data["data"][0];
          var item = _extractAnchorItem(roomData);
          if (item != null) {
            items.add(item);
            return LiveSearchAnchorResult(hasMore: false, items: items);
          }
        }
      } catch (_) {}
    }

    if (items.isEmpty) {
      throw Exception("抖音搜索暂时不可用，请尝试直接输入房间号进入直播间");
    }

    return LiveSearchAnchorResult(hasMore: false, items: items);
  }

  @override
  Future<bool> getLiveStatus({required String roomId}) async {
    try {
      // 使用轻量级方法检查直播状态，避免获取完整房间详情
      return await _getLiveStatusLight(roomId);
    } catch (e) {
      // 如果轻量级方法失败，尝试完整方法作为后备
      try {
        var result = await getRoomDetail(roomId: roomId);
        return result.status;
      } catch (e2) {
        String errorStr = e2.toString();
        
        // 如果是404/444错误或直播间不存在，返回false（表示未直播）
        if (errorStr.contains("444") || 
            errorStr.contains("404") || 
            errorStr.contains("不存在") || 
            errorStr.contains("已关闭") ||
            errorStr.contains("已下播")) {
          return false;
        }
        
        // 如果是请求频繁错误，抛出异常让上层处理
        if (errorStr.contains("频繁") || errorStr.contains("limit")) {
          throw Exception("抖音请求过于频繁，请稍后再试");
        }
        
        // 其他错误，记录日志并返回false
        CoreLog.error("获取抖音直播状态失败 [roomId: $roomId]: $e2");
        return false;
      }
    }
  }

  /// 轻量级直播状态检查方法
  /// 只获取必要的状态信息，避免获取完整房间详情
  Future<bool> _getLiveStatusLight(String roomId) async {
    // 判断是webRid还是roomId
    if (roomId.length <= 16) {
      // webRid - 使用API快速检查
      return await _getLiveStatusByApi(roomId);
    } else {
      // roomId - 使用reflow接口检查
      return await _getLiveStatusByRoomId(roomId);
    }
  }

  /// 通过API检查直播状态（适用于webRid）
  Future<bool> _getLiveStatusByApi(String webRid) async {
    String serverUrl = "https://live.douyin.com/webcast/room/web/enter/";
    var requestHeader = await getRequestHeaders();
    requestHeader["Referer"] = "https://live.douyin.com/$webRid";
    
    var uri = Uri.parse(serverUrl)
        .replace(scheme: "https", port: 443, queryParameters: {
      "aid": '6383',
      "app_name": "douyin_web",
      "live_id": '1',
      "device_platform": "web",
      "language": "zh-CN",
      "browser_language": "zh-CN",
      "browser_name": "Edge",
      "browser_version": "125.0.0.0",
      "web_rid": webRid,
      "msToken": "",
    });
    
    var requestUrl = await getAbogusUrl(uri.toString(), kDefaultUserAgent);
    var result = await HttpClient.instance.getJson(
      requestUrl,
      header: requestHeader,
    );

    if (result is! Map || !result.containsKey("data")) {
      throw Exception("API返回格式错误");
    }

    var data = result["data"];
    if (data == null || data["data"] == null || data["data"].isEmpty) {
      // 数据为空时抛出异常，让上层fallback到完整方法
      throw Exception("API返回数据为空");
    }

    var roomData = data["data"][0];
    var status = roomData["status"];
    
    // 成功时重置失败计数
    resetCookieFailCount();
    
    return status == 2; // status=2 表示直播中
  }

  /// 通过roomId检查直播状态（适用于长roomId）
  Future<bool> _getLiveStatusByRoomId(String roomId) async {
    var result = await HttpClient.instance.getJson(
      'https://webcast.amemv.com/webcast/room/reflow/info/',
      queryParameters: {
        "type_id": 0,
        "live_id": 1,
        "room_id": roomId,
        "sec_user_id": "",
        "version_code": "99.99.99",
        "app_id": 6383,
      },
      header: await getRequestHeaders(),
    );
    
    if (result == null || result["data"] == null || result["data"]["room"] == null) {
      // 数据为空时抛出异常，让上层fallback到完整方法
      throw Exception("reflow接口返回数据为空");
    }

    var room = result["data"]["room"];
    var status = room["status"];
    
    // status=4 表示已下播，需要通过webRid再次检查
    if (status == 4) {
      var webRid = room["owner"]?["web_rid"]?.toString();
      if (webRid != null && webRid.isNotEmpty) {
        return await _getLiveStatusByApi(webRid);
      }
      return false;
    }
    
    return status == 2; // status=2 表示直播中
  }

  @override
  Future<List<LiveSuperChatMessage>> getSuperChatMessage(
      {required String roomId}) {
    return Future.value(<LiveSuperChatMessage>[]);
  }

  @override
  bool get supportLiveRank => true;

  @override
  Future<LiveRankResult> getLiveRanks(
      {required LiveRoomDetail detail}) async {
    try {
      var args = detail.danmakuData as DouyinDanmakuArgs?;
      if (args == null) {
        return LiveRankResult(title: "在线榜", items: []);
      }
      var requestHeader = await getRequestHeaders();
      requestHeader["Referer"] = "https://live.douyin.com/${args.webRid}";
      requestHeader["Accept"] = "application/json";

      var uri = Uri.parse("https://live.douyin.com/webcast/ranklist/audience/")
          .replace(queryParameters: {
        "aid": "6383",
        "app_name": "douyin_web",
        "live_id": "1",
        "device_platform": "web",
        "language": "zh-CN",
        "enter_from": "link_share",
        "cookie_enabled": "true",
        "screen_width": "1920",
        "screen_height": "1080",
        "browser_language": "zh-CN",
        "browser_platform": "Win32",
        "browser_name": "Chrome",
        "browser_version": "125.0.0.0",
        "os_name": "Windows",
        "os_version": "10",
        "webcast_sdk_version": "2450",
        "room_id": args.roomId,
        "anchor_id": args.anchorId,
        "sec_anchor_id": args.secAnchorId,
        "ignoreToast": "true",
        "rank_type": "30",
        "msToken": "",
      });

      // 优先使用 abogus 签名（PR#887 推荐）
      String requestUrl = uri.toString();
      try {
        requestUrl = await getAbogusUrl(uri.toString(), kDefaultUserAgent);
      } catch (_) {
        // 签名未就绪则用原始URL
      }

      var result = await HttpClient.instance.getJson(
        requestUrl,
        header: requestHeader,
      );
      var ranks = (result["data"]?["ranks"] as List?) ?? const [];
      List<LiveRankItem> items = [];
      for (var i = 0; i < ranks.length; i++) {
        var item = ranks[i];
        if (item is! Map) continue;
        var user = (item["user"] as Map?) ?? const {};
        var payGrade = (user["pay_grade"] as Map?) ?? const {};
        var fansClub = (user["fans_club"] as Map?) ?? const {};
        var fansData = (fansClub["data"] as Map?) ?? const {};

        var userLevel = asT<int?>(payGrade["level"]) ??
            int.tryParse(payGrade["level"]?.toString() ?? "");
        var fansLevel = asT<int?>(fansData["level"]) ??
            int.tryParse(fansData["level"]?.toString() ?? "");

        var scoreText = _resolveDouyinRankScore(item);
        var scoreDescription =
            item["score_description"]?.toString().trim() ?? "";
        var exactlyScore = item["exactly_score"]?.toString().trim() ?? "";
        String? scoreDetail;
        if (scoreDescription.isNotEmpty && scoreDescription != scoreText) {
          scoreDetail = scoreDescription;
        } else if (exactlyScore.isNotEmpty && exactlyScore != scoreText) {
          scoreDetail = exactlyScore;
        } else {
          var gapDescription =
              item["gap_description"]?.toString().trim() ?? "";
          scoreDetail = gapDescription.isEmpty ? null : gapDescription;
        }

        var userName = user["nickname"]?.toString().trim() ?? "";
        if (userName.isEmpty) continue;
        items.add(
          LiveRankItem(
            rank: asT<int?>(item["rank"]) ?? (i + 1),
            userName: userName,
            avatar: _firstImageUrl(user["avatar_thumb"]),
            score: scoreText,
            scoreDetail: scoreDetail,
            level: userLevel ?? 0,
            levelText: (userLevel == null || userLevel <= 0)
                ? null
                : "财富 $userLevel",
            levelIcon: _firstImageUrl(payGrade["new_im_icon_with_level"]),
            fansLevel: fansLevel ?? 0,
            medalName: fansData["club_name"]?.toString() ?? "",
            medalIcon: _pickDouyinBadgeIcon(fansData["badge"]?["icons"]),
          ),
        );
      }
      return LiveRankResult(title: "在线榜", items: items);
    } catch (e) {
      CoreLog.error(e);
      return LiveRankResult(title: "在线榜", items: []);
    }
  }

  String _firstImageUrl(dynamic data) {
    if (data is! Map) return "";
    var urls = data["url_list"];
    if (urls is List && urls.isNotEmpty) {
      return urls.first.toString();
    }
    return "";
  }

  String? _pickDouyinBadgeIcon(dynamic icons) {
    if (icons is! Map) return null;
    for (var key in const ["4", "3", "2", "1", "0"]) {
      var url = _firstImageUrl(icons[key]);
      if (url.isNotEmpty) return url;
    }
    for (var value in icons.values) {
      var url = _firstImageUrl(value);
      if (url.isNotEmpty) return url;
    }
    return null;
  }

  String _resolveDouyinRankScore(Map item) {
    var exactlyScore = item["exactly_score"]?.toString().trim() ?? "";
    if (exactlyScore.isNotEmpty) return exactlyScore;
    var scoreDescription = item["score_description"]?.toString().trim() ?? "";
    if (scoreDescription.isNotEmpty) return scoreDescription;
    var score = item["score"]?.toString().trim() ?? "";
    if (score.isNotEmpty) return score;
    var delta = item["delta"]?.toString().trim() ?? "";
    if (delta.isNotEmpty) return delta;
    return "0";
  }

  //生成指定长度的16进制随机字符串
  String generateRandomString(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(16));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item.toRadixString(16));
    }
    return stringBuffer.toString();
  }

  // 生成随机的数字
  int generateRandomNumber(int length) {
    var random = Random.secure();
    var values = List<int>.generate(length, (i) => random.nextInt(10));
    StringBuffer stringBuffer = StringBuffer();
    for (var item in values) {
      stringBuffer.write(item);
    }
    return int.tryParse(stringBuffer.toString()) ??
        Random().nextInt(1000000000);
  }
}
