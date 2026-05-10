import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:ns_danmaku/ns_danmaku.dart';
import 'package:share_plus/share_plus.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/event_bus.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/follow_user.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/player/player_controller.dart';
import 'package:simple_live_app/modules/settings/danmu_settings_page.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_core/simple_live_core.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:simple_live_app/widgets/follow_history_overlay.dart';

class LiveRoomController extends PlayerController with WidgetsBindingObserver {
  final Site pSite;
  final String pRoomId;
  late LiveDanmaku liveDanmaku;
  LiveRoomController({
    required this.pSite,
    required this.pRoomId,
  }) {
    rxSite = pSite.obs;
    rxRoomId = pRoomId.obs;
    liveDanmaku = site.liveSite.getDanmaku();
    // 抖音应该默认是竖屏的
    if (site.id == "douyin") {
      isVertical.value = true;
    }
  }

  late Rx<Site> rxSite;
  Site get site => rxSite.value;
  late Rx<String> rxRoomId;
  String get roomId => rxRoomId.value;

  Rx<LiveRoomDetail?> detail = Rx<LiveRoomDetail?>(null);
  var online = 0.obs;
  var followed = false.obs;
  var liveStatus = false.obs;
  RxList<LiveSuperChatMessage> superChats = RxList<LiveSuperChatMessage>();

  /// 滚动控制
  final ScrollController scrollController = ScrollController();

  /// 聊天信息
  RxList<LiveMessage> messages = RxList<LiveMessage>();

  /// 清晰度数据
  RxList<LivePlayQuality> qualites = RxList<LivePlayQuality>();

  /// 当前清晰度
  var currentQuality = -1;
  var currentQualityInfo = "".obs;

  /// 线路数据
  RxList<String> playUrls = RxList<String>();

  Map<String, String>? playHeaders;

  /// 当前线路
  var currentLineIndex = -1;
  var currentLineInfo = "".obs;

  /// 退出倒计时
  var countdown = 60.obs;

  Timer? autoExitTimer;

  /// 设置的自动关闭时间（分钟）
  var autoExitMinutes = 60.obs;

  ///是否延迟自动关闭
  var delayAutoExit = false.obs;

  /// 是否启用自动关闭
  var autoExitEnable = false.obs;

  /// 是否禁用自动滚动聊天栏
  /// - 当用户向上滚动聊天栏时，不再自动滚动
  var disableAutoScroll = false.obs;

  /// 是否处于后台
  var isBackground = false;

  /// 直播间加载失败
  var loadError = false.obs;
  String? error;

  /// 直播间加载中（仅在播放器区域显示）
  var isPlayerLoading = false.obs;

  // 开播时长状态变量
  var liveDuration = "00:00:00".obs;
  Timer? _liveDurationTimer;

  // 人数刷新定时器
  Timer? _onlineRefreshTimer;
  
  // 上一次获取到的人数（用于防抖动）
  int _lastOnlineCount = 0;
  
  // 可疑的人数值（可能是异常数据）
  int? _suspiciousOnlineCount;

  @override
  void onInit() {
    WidgetsBinding.instance.addObserver(this);
    if (FollowService.instance.followList.isEmpty) {
      FollowService.instance.loadData();
    }
    initAutoExit();
    showDanmakuState.value = AppSettingsController.instance.danmuEnable.value;
    followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
    loadData();

    scrollController.addListener(scrollListener);

    super.onInit();
  }

  void scrollListener() {
    if (scrollController.position.userScrollDirection ==
        ScrollDirection.forward) {
      disableAutoScroll.value = true;
    }
  }

  /// 初始化自动关闭倒计时
  void initAutoExit() {
    if (AppSettingsController.instance.autoExitEnable.value) {
      autoExitEnable.value = true;
      autoExitMinutes.value =
          AppSettingsController.instance.autoExitDuration.value;
      setAutoExit();
    } else {
      autoExitMinutes.value =
          AppSettingsController.instance.roomAutoExitDuration.value;
    }
  }

  void setAutoExit() {
    if (!autoExitEnable.value) {
      autoExitTimer?.cancel();
      return;
    }
    autoExitTimer?.cancel();
    countdown.value = autoExitMinutes.value * 60;
    autoExitTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      countdown.value -= 1;
      if (countdown.value <= 0) {
        timer = Timer(const Duration(seconds: 10), () async {
          await WakelockPlus.disable();
          exit(0);
        });
        autoExitTimer?.cancel();
        var delay = await Utils.showAlertDialog("定时关闭已到时,是否延迟关闭?",
            title: "延迟关闭", confirm: "延迟", cancel: "关闭", selectable: true);
        if (delay) {
          timer.cancel();
          delayAutoExit.value = true;
          showAutoExitSheet();
          setAutoExit();
        } else {
          delayAutoExit.value = false;
          await WakelockPlus.disable();
          exit(0);
        }
      }
    });
  }
  // 弹窗逻辑

  void refreshRoom() {
    //messages.clear();
    superChats.clear();
    liveDanmaku.stop();

    loadData();
  }

  /// 聊天栏始终滚动到底部
  void chatScrollToBottom() {
    if (scrollController.hasClients) {
      // 如果手动上拉过，就不自动滚动到底部
      if (disableAutoScroll.value) {
        return;
      }
      scrollController.jumpTo(scrollController.position.maxScrollExtent);
    }
  }

  /// 初始化弹幕接收事件
  void initDanmau() {
    liveDanmaku.onMessage = onWSMessage;
    liveDanmaku.onClose = onWSClose;
    liveDanmaku.onReady = onWSReady;
  }

  /// 接收到WebSocket信息
  void onWSMessage(LiveMessage msg) {
    if (msg.type == LiveMessageType.chat) {
      if (messages.length > 200 && !disableAutoScroll.value) {
        messages.removeAt(0);
      }

      // 关键词屏蔽检查
      for (var keyword in AppSettingsController.instance.shieldList) {
        Pattern? pattern;
        if (Utils.isRegexFormat(keyword)) {
          String removedSlash = Utils.removeRegexFormat(keyword);
          try {
            pattern = RegExp(removedSlash);
          } catch (e) {
            // should avoid this during add keyword
            Log.d("关键词：$keyword 正则格式错误");
          }
        } else {
          pattern = keyword;
        }
        if (pattern != null && msg.message.contains(pattern)) {
          Log.d("关键词：$keyword\n已屏蔽消息内容：${msg.message}");
          return;
        }
      }

      messages.add(msg);

      WidgetsBinding.instance.addPostFrameCallback(
        (_) => chatScrollToBottom(),
      );
      if (!liveStatus.value || isBackground) {
        return;
      }

      addDanmaku([
        DanmakuItem(
          msg.message,
          color: Color.fromARGB(
            255,
            msg.color.r,
            msg.color.g,
            msg.color.b,
          ),
        ),
      ]);
    } else if (msg.type == LiveMessageType.online) {
      // 抖音平台：忽略WebSocket的人数更新（热度值），只使用定时刷新的真实人数
      if (site.id == "douyin") {
        return;
      }
      // 使用防抖动更新人数
      updateOnlineCount(msg.data);
    } else if (msg.type == LiveMessageType.superChat) {
      superChats.add(msg.data);
    }
  }

  /// 添加一条系统消息
  void addSysMsg(String msg) {
    messages.add(
      LiveMessage(
        type: LiveMessageType.chat,
        userName: "LiveSysMessage",
        message: msg,
        color: LiveMessageColor.white,
      ),
    );
  }

  /// 接收到WebSocket关闭信息
  void onWSClose(String msg) {
    addSysMsg(msg);
  }

  /// WebSocket准备就绪
  void onWSReady() {
    addSysMsg("弹幕服务器连接正常");
  }

  /// 加载直播间信息
  void loadData() async {
    try {
      isPlayerLoading.value = true;
      loadError.value = false;
      error = null;
      update();
      addSysMsg("正在读取直播间信息");
      
      // 抖音直播特殊处理：失败时自动切换ttwid重试
      if (site.id == Constant.kDouyin) {
        detail.value = await _loadDouyinRoomWithRetry();
      } else {
        detail.value = await site.liveSite.getRoomDetail(roomId: roomId);
      }

      if (site.id == Constant.kDouyin) {
        // 1.6.0之前收藏的WebRid
        // 1.6.0收藏的RoomID
        // 1.6.0之后改回WebRid
        if (detail.value!.roomId != roomId) {
          var oldId = roomId;
          rxRoomId.value = detail.value!.roomId;
          if (followed.value) {
            // 更新关注列表
            DBService.instance.deleteFollow("${site.id}_$oldId");
            DBService.instance.addFollow(
              FollowUser(
                id: "${site.id}_$roomId",
                roomId: roomId,
                siteId: site.id,
                userName: detail.value!.userName,
                face: detail.value!.userAvatar,
                addTime: DateTime.now(),
              ),
            );
          } else {
            followed.value =
                DBService.instance.getFollowExist("${site.id}_$roomId");
          }
        }
      }

      getSuperChatMessage();

      addHistory();
      // 确认房间关注状态
      followed.value = DBService.instance.getFollowExist("${site.id}_$roomId");
      online.value = detail.value!.online;
      _lastOnlineCount = detail.value!.online; // 初始化上一次人数值
      liveStatus.value = detail.value!.status || detail.value!.isRecord;
      if (liveStatus.value) {
        getPlayQualites();
      }
      if (detail.value!.isRecord) {
        addSysMsg("当前主播未开播，正在轮播录像");
      }
      addSysMsg("开始连接弹幕服务器");
      initDanmau();
      liveDanmaku.start(detail.value?.danmakuData);
      startLiveDurationTimer(); // 启动开播时长定时器
      startOnlineRefreshTimer(); // 启动人数刷新定时器
    } catch (e) {
      Log.logPrint(e);
      loadError.value = true;
      error = e.toString();
    } finally {
      isPlayerLoading.value = false;
    }
  }
  
  /// 抖音直播间加载（带自动重试和ttwid切换）
  Future<LiveRoomDetail> _loadDouyinRoomWithRetry() async {
    int maxRetries = DouyinSite.kCookiePool.length;
    
    for (int i = 0; i < maxRetries; i++) {
      try {
        var result = await site.liveSite.getRoomDetail(roomId: roomId);
        // 成功时重置cookie失败计数
        DouyinSite.resetCookieFailCount();
        if (i > 0) {
          SmartDialog.showToast("使用ttwid #${DouyinSite.getCurrentCookieIndex() + 1} 成功");
        }
        return result;
      } catch (e) {
        String errorStr = e.toString();
        
        // 判断是否是可重试的错误
        bool isRetryableError = errorStr.contains("444") || 
            errorStr.contains("403") || 
            errorStr.contains("频繁") || 
            errorStr.contains("格式");
        
        if (isRetryableError && i < maxRetries - 1) {
          // 标记当前cookie失败，切换到下一个
          DouyinSite.markCookieAsFailed();
          int nextIndex = (DouyinSite.getCurrentCookieIndex() + 1) % maxRetries;
          SmartDialog.showToast("ttwid #${DouyinSite.getCurrentCookieIndex() + 1} 失败，正在尝试 #${nextIndex + 1}...");
          addSysMsg("切换ttwid重试 (${i + 1}/$maxRetries)");
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          // 不可重试的错误或已用尽重试次数
          break;
        }
      }
    }
    
    // 所有ttwid都失败了
    int cooldownSeconds = _calculateCooldownTime();
    String errorMsg = "抖音直播间加载失败，可能是访问频率过高或直播间不存在。";
    if (cooldownSeconds > 0) {
      errorMsg += "\n建议等待约${cooldownSeconds}秒后再试";
    }
    throw Exception(errorMsg);
  }
  
  /// 计算建议的冷却时间
  int _calculateCooldownTime() {
    int maxCooldown = 0;
    for (var cookie in DouyinSite.kCookiePool) {
      int failCount = DouyinSite.getCookieFailCount(cookie);
      int cooldown = failCount * 30 + 10;
      if (cooldown > maxCooldown) {
        maxCooldown = cooldown;
      }
    }
    return maxCooldown;
  }

  /// 初始化播放器
  void getPlayQualites() async {
    qualites.clear();
    currentQuality = -1;

    try {
      var playQualites =
          await site.liveSite.getPlayQualites(detail: detail.value!);

      if (playQualites.isEmpty) {
        // 设置错误状态，在播放器区域显示
        loadError.value = true;
        error = "无法读取播放清晰度";
        return;
      }
      qualites.value = playQualites;
      var qualityLevel = await getQualityLevel();
      if (qualityLevel == 2) {
        //最高
        currentQuality = 0;
      } else if (qualityLevel == 0) {
        //最低
        currentQuality = playQualites.length - 1;
      } else {
        //中间值
        int middle = (playQualites.length / 2).floor();
        currentQuality = middle;
      }

      getPlayUrl();
    } catch (e) {
      Log.logPrint(e);
      // 设置错误状态
      loadError.value = true;
      error = "无法读取播放清晰度：$e";
    }
  }

  Future<int> getQualityLevel() async {
    var qualityLevel = AppSettingsController.instance.qualityLevel.value;
    try {
      var connectivityResult = await (Connectivity().checkConnectivity());
      if (connectivityResult.first == ConnectivityResult.mobile) {
        qualityLevel =
            AppSettingsController.instance.qualityLevelCellular.value;
      }
    } catch (e) {
      Log.logPrint(e);
    }
    return qualityLevel;
  }

  void getPlayUrl() async {
    playUrls.clear();
    currentQualityInfo.value = qualites[currentQuality].quality;
    currentLineInfo.value = "";
    currentLineIndex = -1;
    var playUrl = await site.liveSite
        .getPlayUrls(detail: detail.value!, quality: qualites[currentQuality]);
    if (playUrl.urls.isEmpty) {
      // 设置错误状态，在播放器区域显示
      loadError.value = true;
      error = "无法读取播放地址";
      return;
    }
    playUrls.value = playUrl.urls;
    playHeaders = playUrl.headers;
    currentLineIndex = 0;
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    //重置错误次数
    mediaErrorRetryCount = 0;
    setPlayer();
  }

  void changePlayLine(int index) {
    currentLineIndex = index;
    //重置错误次数
    mediaErrorRetryCount = 0;
    setPlayer();
  }

  void setPlayer() async {
    currentLineInfo.value = "线路${currentLineIndex + 1}";
    errorMsg.value = "";

    var playurl = playUrls[currentLineIndex];
    if (AppSettingsController.instance.playerForceHttps.value) {
      playurl = playurl.replaceAll("http://", "https://");
    }

    // 初始化播放器并设置 ao 参数
    await initializePlayer();

    await player.open(
      Media(
        playurl,
        httpHeaders: playHeaders,
      ),
    );
    Log.d("播放链接\r\n：$playurl");
  }

  @override
  void mediaEnd() async {
    super.mediaEnd();
    if (mediaErrorRetryCount < 2) {
      Log.d("播放结束，尝试第${mediaErrorRetryCount + 1}次刷新");
      if (mediaErrorRetryCount == 1) {
        //延迟一秒再刷新
        await Future.delayed(const Duration(seconds: 1));
      }
      mediaErrorRetryCount += 1;
      //刷新一次
      setPlayer();
      return;
    }

    Log.d("播放结束");
    // 遍历线路，如果全部链接都断开就是直播结束了
    if (playUrls.length - 1 == currentLineIndex) {
      // 所有线路都失败了，尝试重新获取播放链接（可能是链接过期）
      Log.d("所有线路都失败，尝试重新获取播放链接");
      await Future.delayed(const Duration(seconds: 2));
      getPlayUrl();
    } else {
      changePlayLine(currentLineIndex + 1);

      //setPlayer();
    }
  }

  int mediaErrorRetryCount = 0;
  @override
  void mediaError(String error) async {
    super.mediaEnd();
    if (mediaErrorRetryCount < 2) {
      Log.d("播放失败，尝试第${mediaErrorRetryCount + 1}次刷新");
      if (mediaErrorRetryCount == 1) {
        //延迟一秒再刷新
        await Future.delayed(const Duration(seconds: 1));
      }
      mediaErrorRetryCount += 1;
      //刷新一次
      setPlayer();
      return;
    }

    if (playUrls.length - 1 == currentLineIndex) {
      // 所有线路都失败了，尝试重新获取播放链接（可能是链接过期）
      Log.d("所有线路播放失败，尝试重新获取播放链接");
      await Future.delayed(const Duration(seconds: 2));
      getPlayUrl();
    } else {
      //currentLineIndex += 1;
      //setPlayer();
      changePlayLine(currentLineIndex + 1);
    }
  }

  /// 读取SC
  void getSuperChatMessage() async {
    try {
      var sc =
          await site.liveSite.getSuperChatMessage(roomId: detail.value!.roomId);
      superChats.addAll(sc);
    } catch (e) {
      Log.logPrint(e);
      addSysMsg("SC读取失败");
    }
  }

  /// 移除掉已到期的SC
  void removeSuperChats() async {
    var now = DateTime.now().millisecondsSinceEpoch;
    superChats.value = superChats
        .where((x) => x.endTime.millisecondsSinceEpoch > now)
        .toList();
  }

  /// 添加历史记录
  void addHistory() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    var history = DBService.instance.getHistory(id);
    if (history != null) {
      history.updateTime = DateTime.now();
    }
    history ??= History(
      id: id,
      roomId: roomId,
      siteId: site.id,
      userName: detail.value?.userName ?? "",
      face: detail.value?.userAvatar ?? "",
      updateTime: DateTime.now(),
    );

    DBService.instance.addOrUpdateHistory(history);
  }

  /// 关注用户
  void followUser() {
    if (detail.value == null) {
      return;
    }
    var id = "${site.id}_$roomId";
    DBService.instance.addFollow(
      FollowUser(
        id: id,
        roomId: roomId,
        siteId: site.id,
        userName: detail.value?.userName ?? "",
        face: detail.value?.userAvatar ?? "",
        addTime: DateTime.now(),
      ),
    );
    followed.value = true;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  /// 取消关注用户
  void removeFollowUser() async {
    if (detail.value == null) {
      return;
    }
    if (!await Utils.showAlertDialog("确定要取消关注该用户吗？", title: "取消关注")) {
      return;
    }

    var id = "${site.id}_$roomId";
    DBService.instance.deleteFollow(id);
    followed.value = false;
    EventBus.instance.emit(Constant.kUpdateFollow, id);
  }

  void share() {
    if (detail.value == null) {
      return;
    }
    Share.share(detail.value!.url);
  }

  void copyUrl() {
    if (detail.value == null) {
      return;
    }
    Utils.copyToClipboard(detail.value!.url);
    SmartDialog.showToast("已复制直播间链接");
  }

  /// 复制新生成的直播流
  void copyPlayUrl() async {
    // 未开播不复制
    if (!liveStatus.value) {
      return;
    }
    var playUrl = await site.liveSite
        .getPlayUrls(detail: detail.value!, quality: qualites[currentQuality]);
    if (playUrl.urls.isEmpty) {
      SmartDialog.showToast("无法读取播放地址");
      return;
    }
    Utils.copyToClipboard(playUrl.urls.first);
    SmartDialog.showToast("已复制播放直链");
  }

  /// 底部打开播放器设置
  void showDanmuSettingsSheet() {
    Utils.showBottomSheet(
      title: "弹幕设置",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          DanmuSettingsView(
            danmakuController: danmakuController,
            onTapDanmuShield: () {
              Get.back();
              showDanmuShield();
            },
          ),
        ],
      ),
    );
  }

  void setPlayerMute() {
    var nowVolume = AppSettingsController.instance.playerVolume.value;
    var lastVolume = AppSettingsController.instance.playerLastVolume.value;
    if (nowVolume == 0) {
      lastVolume = (lastVolume == 0) ? 50 : lastVolume;
      player.setVolume(lastVolume);
      AppSettingsController.instance.setPlayerVolume(lastVolume);
    }
    else {
      AppSettingsController.instance.setPlayerLastVolume(nowVolume);
      player.setVolume(0);
      AppSettingsController.instance.setPlayerVolume(0);
    }
  }

  void showVolumeSlider(BuildContext targetContext) {
    // 防止窗口因按钮未完全显现而反复弹出
    if (SmartDialog.checkExist(tag: "volume_slider")) return;
    SmartDialog.showAttach(
      tag: "volume_slider",
      keepSingle: true, // 仅允许一个窗口存在
      usePenetrate: true, // 允许穿透遮罩以响应后方按钮单击事件
      targetContext: targetContext,
      alignment: Alignment.topCenter,
      displayTime: const Duration(seconds: 3),
      maskColor: const Color(0x00000000),
      builder: (context) {
        return Container(
          decoration: BoxDecoration(
            borderRadius: AppStyle.radius12,
            color: Theme.of(context).cardColor,
          ),
          padding: AppStyle.edgeInsetsA4,
          child: Obx(
            () => SizedBox(
              width: 200,
              child: Slider(
                min: 0,
                max: 100,
                divisions: 20,
                value: AppSettingsController.instance.playerVolume.value,
                label: '${AppSettingsController.instance.playerVolume.value.round()}',
                onChanged: (newValue) {
                  player.setVolume(newValue);
                  AppSettingsController.instance.setPlayerVolume(newValue);
                },
              ),
            ),
          ),
        );
      },
    );
  }

  void showQualitySheet() {
    Utils.showBottomSheet(
      title: "切换清晰度",
      child: ListView.builder(
        itemCount: qualites.length,
        itemBuilder: (_, i) {
          var item = qualites[i];
          return RadioListTile(
            value: i,
            groupValue: currentQuality,
            title: Text(item.quality),
            onChanged: (e) {
              Get.back();
              currentQuality = i;
              getPlayUrl();
            },
          );
        },
      ),
    );
  }

  void showPlayUrlsSheet() {
    Utils.showBottomSheet(
      title: "切换线路",
      child: ListView.builder(
        itemCount: playUrls.length,
        itemBuilder: (_, i) {
          return RadioListTile(
            value: i,
            groupValue: currentLineIndex,
            title: Text("线路${i + 1}"),
            secondary: Text(
              playUrls[i].contains(".flv") ? "FLV" : "HLS",
            ),
            onChanged: (e) {
              Get.back();
              //currentLineIndex = i;
              //setPlayer();
              changePlayLine(i);
            },
          );
        },
      ),
    );
  }

  void showPlayerSettingsSheet() {
    Utils.showBottomSheet(
      title: "画面尺寸",
      child: Obx(
        () => ListView(
          padding: AppStyle.edgeInsetsV12,
          children: [
            RadioListTile(
              value: 0,
              title: const Text("适应"),
              visualDensity: VisualDensity.compact,
              groupValue: AppSettingsController.instance.scaleMode.value,
              onChanged: (e) {
                AppSettingsController.instance.setScaleMode(e ?? 0);
                updateScaleMode();
              },
            ),
            RadioListTile(
              value: 1,
              title: const Text("拉伸"),
              visualDensity: VisualDensity.compact,
              groupValue: AppSettingsController.instance.scaleMode.value,
              onChanged: (e) {
                AppSettingsController.instance.setScaleMode(e ?? 1);
                updateScaleMode();
              },
            ),
            RadioListTile(
              value: 2,
              title: const Text("铺满"),
              visualDensity: VisualDensity.compact,
              groupValue: AppSettingsController.instance.scaleMode.value,
              onChanged: (e) {
                AppSettingsController.instance.setScaleMode(e ?? 2);
                updateScaleMode();
              },
            ),
            RadioListTile(
              value: 3,
              title: const Text("16:9"),
              visualDensity: VisualDensity.compact,
              groupValue: AppSettingsController.instance.scaleMode.value,
              onChanged: (e) {
                AppSettingsController.instance.setScaleMode(e ?? 3);
                updateScaleMode();
              },
            ),
            RadioListTile(
              value: 4,
              title: const Text("4:3"),
              visualDensity: VisualDensity.compact,
              groupValue: AppSettingsController.instance.scaleMode.value,
              onChanged: (e) {
                AppSettingsController.instance.setScaleMode(e ?? 4);
                updateScaleMode();
              },
            ),
          ],
        ),
      ),
    );
  }

  void showDanmuShield() {
    TextEditingController keywordController = TextEditingController();

    void addKeyword() {
      if (keywordController.text.isEmpty) {
        SmartDialog.showToast("请输入关键词");
        return;
      }

      AppSettingsController.instance
          .addShieldList(keywordController.text.trim());
      keywordController.text = "";
    }

    Utils.showBottomSheet(
      title: "关键词屏蔽",
      child: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          TextField(
            controller: keywordController,
            decoration: InputDecoration(
              contentPadding: AppStyle.edgeInsetsH12,
              border: const OutlineInputBorder(),
              hintText: "请输入关键词",
              suffixIcon: TextButton.icon(
                onPressed: addKeyword,
                icon: const Icon(Icons.add),
                label: const Text("添加"),
              ),
            ),
            onSubmitted: (e) {
              addKeyword();
            },
          ),
          AppStyle.vGap12,
          Obx(
            () => Text(
              "已添加${AppSettingsController.instance.shieldList.length}个关键词（点击移除）",
              style: Get.textTheme.titleSmall,
            ),
          ),
          AppStyle.vGap12,
          Obx(
            () => Wrap(
              runSpacing: 12,
              spacing: 12,
              children: AppSettingsController.instance.shieldList
                  .map(
                    (item) => InkWell(
                      borderRadius: AppStyle.radius24,
                      onTap: () {
                        AppSettingsController.instance.removeShieldList(item);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey),
                          borderRadius: AppStyle.radius24,
                        ),
                        padding: AppStyle.edgeInsetsH12.copyWith(
                          top: 4,
                          bottom: 4,
                        ),
                        child: Text(
                          item,
                          style: Get.textTheme.bodyMedium,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  void showFollowUserSheet() {
    showModalBottomSheet(
      context: Get.context!,
      constraints: const BoxConstraints(maxWidth: 600),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(12),
          topRight: Radius.circular(12),
        ),
      ),
      builder: (_) => FollowHistoryOverlay(
        controller: this,
        isBottomSheet: true,
        onDismiss: () => Get.back(),
      ),
    );
  }

  void showAutoExitSheet() {
    if (AppSettingsController.instance.autoExitEnable.value &&
        !delayAutoExit.value) {
      SmartDialog.showToast("已设置了全局定时关闭");
      return;
    }
    Utils.showBottomSheet(
      title: "定时关闭",
      child: ListView(
        children: [
          Obx(
            () => SwitchListTile(
              title: Text(
                "启用定时关闭",
                style: Get.textTheme.titleMedium,
              ),
              value: autoExitEnable.value,
              onChanged: (e) {
                autoExitEnable.value = e;

                setAutoExit();
                //controller.setAutoExitEnable(e);
              },
            ),
          ),
          Obx(
            () => ListTile(
              enabled: autoExitEnable.value,
              title: Text(
                "自动关闭时间：${autoExitMinutes.value ~/ 60}小时${autoExitMinutes.value % 60}分钟",
                style: Get.textTheme.titleMedium,
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                var value = await showTimePicker(
                  context: Get.context!,
                  initialTime: TimeOfDay(
                    hour: autoExitMinutes.value ~/ 60,
                    minute: autoExitMinutes.value % 60,
                  ),
                  initialEntryMode: TimePickerEntryMode.inputOnly,
                  builder: (_, child) {
                    return MediaQuery(
                      data: Get.mediaQuery.copyWith(
                        alwaysUse24HourFormat: true,
                      ),
                      child: child!,
                    );
                  },
                );
                if (value == null || (value.hour == 0 && value.minute == 0)) {
                  return;
                }
                var duration =
                    Duration(hours: value.hour, minutes: value.minute);
                autoExitMinutes.value = duration.inMinutes;
                AppSettingsController.instance
                    .setRoomAutoExitDuration(autoExitMinutes.value);
                //setAutoExitDuration(duration.inMinutes);
                setAutoExit();
              },
            ),
          ),
        ],
      ),
    );
  }

  void openNaviteAPP() async {
    var naviteUrl = "";
    var webUrl = "";
    if (site.id == Constant.kBiliBili) {
      naviteUrl = "bilibili://live/${detail.value?.roomId}";
      webUrl = "https://live.bilibili.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyin) {
      var args = detail.value?.danmakuData as DouyinDanmakuArgs;
      naviteUrl = "snssdk1128://webcast_room?room_id=${args.roomId}";
      webUrl = "https://live.douyin.com/${args.webRid}";
    } else if (site.id == Constant.kHuya) {
      var args = detail.value?.danmakuData as HuyaDanmakuArgs;
      naviteUrl =
          "yykiwi://homepage/index.html?banneraction=https%3A%2F%2Fdiy-front.cdn.huya.com%2Fzt%2Ffrontpage%2Fcc%2Fupdate.html%3Fhyaction%3Dlive%26channelid%3D${args.subSid}%26subid%3D${args.subSid}%26liveuid%3D${args.subSid}%26screentype%3D1%26sourcetype%3D0%26fromapp%3Dhuya_wap%252Fclick%252Fopen_app_guide%26&fromapp=huya_wap/click/open_app_guide";
      webUrl = "https://www.huya.com/${detail.value?.roomId}";
    } else if (site.id == Constant.kDouyu) {
      naviteUrl =
          "douyulink://?type=90001&schemeUrl=douyuapp%3A%2F%2Froom%3FliveType%3D0%26rid%3D${detail.value?.roomId}";
      webUrl = "https://www.douyu.com/${detail.value?.roomId}";
    }
    try {
      await launchUrlString(naviteUrl, mode: LaunchMode.externalApplication);
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("无法打开APP，将使用浏览器打开");
      await launchUrlString(webUrl, mode: LaunchMode.externalApplication);
    }
  }

  void resetRoom(Site site, String roomId) async {
    if (this.site == site && this.roomId == roomId) {
      return;
    }

    rxSite.value = site;
    rxRoomId.value = roomId;

    // 清除全部消息
    liveDanmaku.stop();
    messages.clear();
    superChats.clear();
    danmakuController?.clear();

    // 重新设置LiveDanmaku
    liveDanmaku = site.liveSite.getDanmaku();

    // 停止播放
    await player.stop();

    // 刷新信息
    loadData();
  }

  void copyErrorDetail() {
    Utils.copyToClipboard('''直播平台：${rxSite.value.name}
房间号：${rxRoomId.value}
错误信息：
$error''');
    SmartDialog.showToast("已复制错误信息");
  }

  /// 后台时音量降低前的原始音量
  double? _volumeBeforeBackground;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      Log.d("进入后台/失去焦点: $state");
      isBackground = true;

      // 1. 关闭弹幕渲染（后台 UI 不可见，节省资源）
      danmakuController?.clear();

      // 2. 暂停定时器（防止后台持续唤醒 CPU）
      _liveDurationTimer?.cancel();
      _liveDurationTimer = null;
      _onlineRefreshTimer?.cancel();
      _onlineRefreshTimer = null;

      // 3. 关闭屏幕常亮
      WakelockPlus.disable();

      // 4. iOS：拍照/微信等场景仍允许后台播放，仅降低音量并保持音频
      //    其它平台（Android/桌面）按设置项决定是否暂停
      if (Platform.isIOS) {
        if (!isManualPaused.value) {
          try {
            final cur = AppSettingsController.instance.playerVolume.value;
            _volumeBeforeBackground = cur;
            // 后台音量降到原音量的 30%，最低 5
            final reduced = (cur * 0.3).clamp(5.0, 100.0);
            player.setVolume(reduced);
          } catch (e) {
            Log.logPrint(e);
          }
        }
      } else {
        if (AppSettingsController.instance.playerAutoPause.value &&
            !isManualPaused.value) {
          try {
            player.pause();
          } catch (e) {
            Log.logPrint(e);
          }
        }
      }
    } else if (state == AppLifecycleState.resumed) {
      Log.d("返回前台");
      isBackground = false;

      // iOS：恢复后台前的音量
      if (Platform.isIOS && _volumeBeforeBackground != null) {
        try {
          player.setVolume(_volumeBeforeBackground!);
        } catch (e) {
          Log.logPrint(e);
        }
        _volumeBeforeBackground = null;
      }

      // 非 iOS：若是自动暂停模式且未被用户手动暂停，则恢复播放
      if (!Platform.isIOS &&
          AppSettingsController.instance.playerAutoPause.value &&
          !isManualPaused.value) {
        try {
          player.play();
        } catch (e) {
          Log.logPrint(e);
        }
      }

      // 恢复定时器和屏幕常亮
      if (liveStatus.value) {
        WakelockPlus.enable();
        startLiveDurationTimer();
        startOnlineRefreshTimer();
      }
    }
  }

  // 用于启动开播时长计算和更新的函数
  void startLiveDurationTimer() {
    // 如果不是直播状态或者 showTime 为空，则不启动定时器
    if (!(detail.value?.status ?? false) || detail.value?.showTime == null) {
      liveDuration.value = "00:00:00"; // 未开播时显示 00:00:00
      _liveDurationTimer?.cancel();
      return;
    }

    try {
      int startTimeStamp = int.parse(detail.value!.showTime!);
      // 取消之前的定时器
      _liveDurationTimer?.cancel();
      // 创建新的定时器，每秒更新一次
      _liveDurationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        int currentTimeStamp = DateTime.now().millisecondsSinceEpoch ~/ 1000;
        int durationInSeconds = currentTimeStamp - startTimeStamp;

        int hours = durationInSeconds ~/ 3600;
        int minutes = (durationInSeconds % 3600) ~/ 60;
        int seconds = durationInSeconds % 60;

        String formattedDuration =
            '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
        liveDuration.value = formattedDuration;
      });
    } catch (e) {
      liveDuration.value = "--:--:--"; // 错误时显示 --:--:--
    }
  }

  // 更新人数（带防抖动逻辑）
  void updateOnlineCount(int newOnline) {
    // 如果是首次获取或当前人数为0，直接更新
    if (_lastOnlineCount == 0 || online.value == 0) {
      online.value = newOnline;
      _lastOnlineCount = newOnline;
      _suspiciousOnlineCount = null;
      return;
    }
    
    // 抖音平台：直接更新人数（因为已经在API层面保证了使用真实人数）
    if (site.id == "douyin") {
      online.value = newOnline;
      _lastOnlineCount = newOnline;
      _suspiciousOnlineCount = null;
      return;
    }
    
    // 其他平台：计算新人数与当前人数的倍率差异
    double ratio = newOnline > online.value 
        ? newOnline / online.value.toDouble()
        : online.value / newOnline.toDouble();
    
    // 如果人数差异过大（超过5倍），可能是异常数据
    if (ratio > 5.0) {
      // 如果这个值与上次可疑值相同，说明可能是真实值，更新它
      if (_suspiciousOnlineCount != null && _suspiciousOnlineCount == newOnline) {
        online.value = newOnline;
        _lastOnlineCount = newOnline;
        _suspiciousOnlineCount = null;
        Log.d("确认人数更新: $newOnline");
      } else {
        // 标记为可疑值，等待下次确认
        _suspiciousOnlineCount = newOnline;
        Log.d("检测到可疑人数值: $newOnline，等待下次确认");
      }
    } else {
      // 人数变化合理，直接更新
      online.value = newOnline;
      _lastOnlineCount = newOnline;
      _suspiciousOnlineCount = null;
    }
  }

  // 启动人数刷新定时器
  void startOnlineRefreshTimer() {
    // 取消之前的定时器
    _onlineRefreshTimer?.cancel();

    // 严格遵循用户设置：关闭后任何平台都不再自动刷新
    if (!AppSettingsController.instance.roomOnlineRefreshEnable.value) {
      Log.d("人数自动刷新已禁用，仅可点击人数手动刷新");
      return;
    }

    // 获取用户设置的刷新间隔
    int intervalSeconds = AppSettingsController.instance.roomOnlineRefreshInterval.value;
    Log.d("启动人数自动刷新，间隔 $intervalSeconds 秒");

    // 创建定时器，按设置的间隔刷新人数
    _onlineRefreshTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (timer) {
        refreshOnlineCount();
      },
    );
  }

  /// 是否正在获取实时人数
  var isFetchingOnline = false.obs;

  /// 是否处于手动暂停状态（仅区分用户主动暂停，不影响后台 / 退出等场景）
  var isManualPaused = false.obs;

  /// 榜单数据（贡献榜 / 亲密榜）
  Rx<LiveRankResult?> liveRankResult = Rx<LiveRankResult?>(null);

  /// 是否正在加载榜单
  var isLoadingRank = false.obs;

  /// 拉取榜单数据，每次点击会强制刷新
  Future<void> fetchLiveRanks() async {
    if (detail.value == null || isLoadingRank.value) return;
    if (!site.liveSite.supportLiveRank) {
      SmartDialog.showToast("当前平台暂不支持榜单");
      return;
    }
    try {
      isLoadingRank.value = true;
      var result = await site.liveSite.getLiveRanks(detail: detail.value!);
      liveRankResult.value = result;
    } catch (e) {
      Log.logPrint(e);
      SmartDialog.showToast("榜单加载失败");
    } finally {
      isLoadingRank.value = false;
    }
  }

  /// 切换播放 / 暂停。
  /// - 暂停：直接 `player.pause()`，保持当前画面，弹幕仍可接收。
  /// - 恢复：直播是实时流，调用 `setPlayer()` 重新加载最新流，避免落后。
  void togglePlayPause() async {
    if (loadError.value || isPlayerLoading.value) {
      return;
    }
    if (!liveStatus.value) {
      SmartDialog.showToast("当前未在直播");
      return;
    }
    if (isManualPaused.value) {
      // 当前为暂停状态 → 恢复并重新拉流到最新
      isManualPaused.value = false;
      if (qualites.isEmpty || currentQuality < 0 || playUrls.isEmpty || currentLineIndex < 0) {
        // 数据缺失，重新走完整流程
        loadData();
      } else {
        mediaErrorRetryCount = 0;
        setPlayer();
      }
    } else {
      // 当前为播放状态 → 暂停
      isManualPaused.value = true;
      try {
        await player.pause();
      } catch (e) {
        Log.logPrint(e);
      }
    }
  }

  /// 手动点击获取实时人数
  void fetchRealtimeOnline() async {
    if (isFetchingOnline.value) return;
    try {
      isFetchingOnline.value = true;
      var roomDetail = await site.liveSite.getRoomDetail(roomId: roomId);
      online.value = roomDetail.online;
      _lastOnlineCount = roomDetail.online;
      _suspiciousOnlineCount = null;
      SmartDialog.showToast("当前人数: ${roomDetail.online}");
    } catch (e) {
      SmartDialog.showToast("获取人数失败");
      Log.d("手动获取人数失败: $e");
    } finally {
      isFetchingOnline.value = false;
    }
  }

  // 刷新直播间在线人数
  void refreshOnlineCount() async {
    try {
      // 获取最新的直播间信息
      var roomDetail = await site.liveSite.getRoomDetail(roomId: roomId);
      
      // 使用防抖动逻辑更新人数
      updateOnlineCount(roomDetail.online);
    } catch (e) {
      // 刷新失败不影响观看，静默处理
      Log.d("刷新人数失败: $e");
    }
  }

  @override
  void onClose() {
    WidgetsBinding.instance.removeObserver(this);
    scrollController.removeListener(scrollListener);
    autoExitTimer?.cancel();

    liveDanmaku.stop();
    danmakuController = null;
    _liveDurationTimer?.cancel(); // 页面关闭时取消定时器
    _onlineRefreshTimer?.cancel(); // 页面关闭时取消人数刷新定时器
    super.onClose();
  }
}
