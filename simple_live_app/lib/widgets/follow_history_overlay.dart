import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/models/db/history.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/services/db_service.dart';
import 'package:simple_live_app/services/follow_service.dart';
import 'package:simple_live_app/widgets/desktop_horizontal_scroll.dart';
import 'package:simple_live_app/widgets/follow_user_item.dart';
import 'package:simple_live_app/widgets/net_image.dart';

class FollowHistoryOverlay extends StatefulWidget {
  final LiveRoomController controller;
  final VoidCallback onDismiss;
  final bool isBottomSheet;

  const FollowHistoryOverlay({
    required this.controller,
    required this.onDismiss,
    this.isBottomSheet = false,
    Key? key,
  }) : super(key: key);

  @override
  State<FollowHistoryOverlay> createState() => _FollowHistoryOverlayState();
}

class _FollowHistoryOverlayState extends State<FollowHistoryOverlay>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late int _initialIndex;
  List<History> _historyList = [];

  /// 直播状态缓存: id -> 0=查询中, 1=未开播, 2=直播中
  final Map<String, int> _liveStatusMap = {};
  bool _isCheckingStatus = false;

  /// 关注列表的滚动控制器（用于让右下角刷新按钮区域的滚轮事件穿透至列表）
  final ScrollController _followScrollController = ScrollController();

  /// 历史列表的滚动控制器
  final ScrollController _historyScrollController = ScrollController();

  /// 顶部平台筛选条是否展开（关注Tab / 记录Tab 共用同一开关，
  /// 切换Tab时保持当前展开/收起状态，符合直觉）
  bool _showPlatformFilter = false;

  /// 当前选中的平台筛选（null = 全部）
  String? _filterSiteId;

  @override
  void initState() {
    super.initState();
    _initialIndex = AppSettingsController.instance.overlayTabOrder.value;
    _tabController = TabController(
      length: 2,
      vsync: this,
      initialIndex: _initialIndex,
    );
    _tabController.addListener(_onTabChanged);
    _loadHistory();
  }

  void _onTabChanged() {
    if (!_tabController.indexIsChanging) {
      setState(() {});
      AppSettingsController.instance.setOverlayTabOrder(_tabController.index);
      // 切换到记录标签时自动检查直播状态
      if (_tabController.index == 1) {
        _checkAllLiveStatus();
      }
    }
  }

  void _loadHistory() {
    _historyList = DBService.instance.getHistores();
    _liveStatusMap.clear();
    setState(() {});
    // 如果当前在记录标签页，自动检查
    if (_tabController.index == 1) {
      _checkAllLiveStatus();
    }
  }

  /// 批量异步查询所有观看记录的直播状态
  Future<void> _checkAllLiveStatus() async {
    if (_isCheckingStatus || _historyList.isEmpty) return;
    _isCheckingStatus = true;

    // 先将所有未查询的标记为查询中
    for (var item in _historyList) {
      if (!_liveStatusMap.containsKey(item.id)) {
        _liveStatusMap[item.id] = 0;
      }
    }
    // 优先从关注列表同步头像，避免历史记录中头像过期
    _syncFaceFromFollowList();
    if (mounted) setState(() {});

    // 逐个查询，避免并发过多导致发烫
    for (var item in _historyList) {
      if (!mounted) break;
      var site = Sites.allSites[item.siteId];
      if (site == null) {
        _liveStatusMap[item.id] = 1;
        continue;
      }
      try {
        var isLiving =
            await site.liveSite.getLiveStatus(roomId: item.roomId);
        _liveStatusMap[item.id] = isLiving ? 2 : 1;
        // 正在直播时拉一次详情更新头像与昵称
        if (isLiving) {
          try {
            var detail = await site.liveSite.getRoomDetail(roomId: item.roomId);
            bool changed = false;
            if (detail.userAvatar.isNotEmpty && detail.userAvatar != item.face) {
              item.face = detail.userAvatar;
              changed = true;
            }
            if (detail.userName.isNotEmpty && detail.userName != item.userName) {
              item.userName = detail.userName;
              changed = true;
            }
            if (changed) {
              await DBService.instance.addOrUpdateHistory(item);
            }
          } catch (e) {
            // 详情获取失败不影响主流程
          }
        }
      } catch (e) {
        Log.d("检查观看记录直播状态失败 [${item.userName}]: $e");
        _liveStatusMap[item.id] = 1;
      }
      if (mounted) setState(() {});
    }
    _isCheckingStatus = false;
  }

  /// 从已加载的关注列表中同步头像，避免观看记录头像过期
  void _syncFaceFromFollowList() {
    final followMap = {
      for (var f in FollowService.instance.followList) f.id: f,
    };
    bool changed = false;
    for (var item in _historyList) {
      final follow = followMap[item.id];
      if (follow == null) continue;
      if (follow.face.isNotEmpty && follow.face != item.face) {
        item.face = follow.face;
        DBService.instance.addOrUpdateHistory(item);
        changed = true;
      }
      if (follow.userName.isNotEmpty && follow.userName != item.userName) {
        item.userName = follow.userName;
        DBService.instance.addOrUpdateHistory(item);
        changed = true;
      }
    }
    if (changed && mounted) {
      // _historyList 项已就地修改，无需重排
    }
  }

  Future<void> _refreshHistoryStatus() async {
    _liveStatusMap.clear();
    _loadHistory();
    await _checkAllLiveStatus();
  }

  Future<void> _clearAllHistory() async {
    var result = await Utils.showAlertDialog(
      "确定要清空所有观看记录吗？",
      title: "清空记录",
    );
    if (!result) return;
    await DBService.instance.historyBox.clear();
    _liveStatusMap.clear();
    _loadHistory();
    SmartDialog.showToast("已清空观看记录");
  }

  Future<void> _deleteHistoryItem(History item) async {
    HapticFeedback.mediumImpact();
    await DBService.instance.historyBox.delete(item.id);
    _liveStatusMap.remove(item.id);
    _loadHistory();
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    _followScrollController.dispose();
    _historyScrollController.dispose();
    super.dispose();
  }

  /// 通用滚动事件转发：让右下角浮层按钮区域的滚轮事件穿透到下方列表
  void _forwardScroll(ScrollController controller, PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (!controller.hasClients) return;
    final position = controller.position;
    final newOffset = (controller.offset + event.scrollDelta.dy).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    controller.jumpTo(newOffset);
  }

  // ── 统一的直播状态配色 ──
  static const Color _liveColor = Color(0xFF2ECC71);       // 翡翠绿
  static const Color _liveBgColor = Color(0x192ECC71);     // 10%透明度
  static const Color _offlineColor = Color(0xFF95A5A6);    // 银灰
  static const Color _offlineBgColor = Color(0x1995A5A6);  // 10%透明度

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        // Tab bar header
        Container(
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: Colors.grey.withAlpha(30),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: [
              if (!widget.isBottomSheet)
                IconButton(
                  onPressed: widget.onDismiss,
                  icon: const Icon(Icons.arrow_back, size: 20),
                ),
              Expanded(
                child: TabBar(
                  controller: _tabController,
                  labelColor: theme.colorScheme.primary,
                  unselectedLabelColor: Colors.grey,
                  indicatorColor: theme.colorScheme.primary,
                  indicatorSize: TabBarIndicatorSize.label,
                  indicatorWeight: 2.5,
                  labelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  unselectedLabelStyle: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.normal,
                  ),
                  dividerHeight: 0,
                  tabs: const [
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Remix.heart_3_line, size: 15),
                          SizedBox(width: 5),
                          Text("关注"),
                        ],
                      ),
                    ),
                    Tab(
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Remix.history_line, size: 15),
                          SizedBox(width: 5),
                          Text("记录"),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 平台筛选切换按钮（点击隐藏/显示底部平台筛选条）
              IconButton(
                onPressed: () {
                  setState(() {
                    _showPlatformFilter = !_showPlatformFilter;
                    if (!_showPlatformFilter) {
                      _filterSiteId = null;
                    }
                  });
                },
                tooltip: _showPlatformFilter ? "隐藏平台筛选" : "平台筛选",
                icon: Icon(
                  _showPlatformFilter ? Remix.filter_fill : Remix.filter_line,
                  size: 19,
                  color: _showPlatformFilter ? theme.colorScheme.primary : null,
                ),
              ),
              // Right side action button area
              if (_tabController.index == 1 && _historyList.isNotEmpty)
                IconButton(
                  onPressed: _clearAllHistory,
                  tooltip: "清空记录",
                  icon: const Icon(Remix.delete_bin_line, size: 19, color: Colors.red),
                )
              else if (widget.isBottomSheet)
                IconButton(
                  onPressed: widget.onDismiss,
                  icon: const Icon(Remix.close_line, size: 20),
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        ),
        // Tab views
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildFollowList(),
              _buildHistoryList(),
            ],
          ),
        ),
      ],
    );
  }

  /// 当前关注列表（已按平台过滤）
  List<dynamic> get _filteredLiveFollows {
    final base = FollowService.instance.liveList;
    // 显式访问 length 触发 GetX 响应式收集
    final _ = base.length;
    if (_filterSiteId == null) return base.toList();
    return base.where((u) => u.siteId == _filterSiteId).toList();
  }

  /// 当前观看记录（已按平台过滤）
  List<History> get _filteredHistory {
    if (_filterSiteId == null) return _historyList;
    return _historyList.where((h) => h.siteId == _filterSiteId).toList();
  }

  /// 当前关注列表中实际存在的平台ID（按 Sites.allSites 顺序）
  List<String> _activePlatformIdsForFollow() {
    final follow = FollowService.instance.followList;
    final _ = follow.length;
    final ids = follow.map((u) => u.siteId).toSet();
    return Sites.allSites.keys.where((k) => ids.contains(k)).toList();
  }

  /// 观看记录中实际存在的平台ID
  List<String> _activePlatformIdsForHistory() {
    final ids = _historyList.map((h) => h.siteId).toSet();
    return Sites.allSites.keys.where((k) => ids.contains(k)).toList();
  }

  Widget _buildPlatformFilterBar(List<String> platformIds) {
    if (platformIds.length <= 1 || !_showPlatformFilter) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.withAlpha(20),
            width: 0.5,
          ),
        ),
      ),
      // 使用 DesktopHorizontalScroll，桌面端可用鼠标拖拽 + 滚轮滑动
      child: DesktopHorizontalScroll(
        child: Row(
          children: [
            _buildPlatformChip(null, "全部"),
            ...platformIds.map((id) {
              final site = Sites.allSites[id]!;
              return _buildPlatformChip(id, site.name, logo: site.logo);
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildPlatformChip(String? siteId, String label, {String? logo}) {
    final theme = Theme.of(context);
    final selected = _filterSiteId == siteId;
    return GestureDetector(
      onTap: () {
        setState(() {
          _filterSiteId = siteId;
        });
      },
      child: Container(
        margin: const EdgeInsets.only(right: 6),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withAlpha(30)
              : theme.cardColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? theme.colorScheme.primary
                : Colors.grey.withAlpha(60),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (logo != null) ...[
              ClipOval(
                child: Image.asset(
                  logo,
                  width: 14,
                  height: 14,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: selected ? theme.colorScheme.primary : null,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowList() {
    return Obx(
      () {
        final platformIds = _activePlatformIdsForFollow();
        final list = _filteredLiveFollows;
        return Column(
          children: [
            _buildPlatformFilterBar(platformIds),
            Expanded(
              child: Stack(
                children: [
                  RefreshIndicator(
                    onRefresh: FollowService.instance.loadData,
                    child: list.isEmpty
                        ? ListView(
                            controller: _followScrollController,
                            physics: const AlwaysScrollableScrollPhysics(),
                            children: [
                              SizedBox(
                                height: 240,
                                child: _buildEmptyState(
                                  _filterSiteId == null
                                      ? "暂无正在直播的关注"
                                      : "该平台暂无正在直播的关注",
                                  Remix.heart_3_line,
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            controller: _followScrollController,
                            padding: const EdgeInsets.only(top: 4, bottom: 8),
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              var item = list[i];
                              return Obx(
                                () => FollowUserItem(
                                  item: item,
                                  playing: widget.controller.rxSite.value.id ==
                                          item.siteId &&
                                      widget.controller.rxRoomId.value ==
                                          item.roomId,
                                  onTap: () {
                                    widget.onDismiss();
                                    widget.controller.resetRoom(
                                      Sites.allSites[item.siteId]!,
                                      item.roomId,
                                    );
                                  },
                                  onLongPress:
                                      (Platform.isAndroid || Platform.isIOS)
                                          ? () => _showFollowOptions(item)
                                          : null,
                                  onSecondaryTap: (Platform.isWindows ||
                                          Platform.isMacOS ||
                                          Platform.isLinux)
                                      ? () => _showFollowOptions(item)
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                  if (Platform.isLinux ||
                      Platform.isWindows ||
                      Platform.isMacOS)
                    Positioned(
                      right: 12,
                      bottom: 12,
                      child: Listener(
                        onPointerSignal: (event) =>
                            _forwardScroll(_followScrollController, event),
                        child: Obx(
                          () => _buildRefreshButton(
                            refreshing: FollowService.instance.updating.value,
                            onPressed: FollowService.instance.loadData,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildHistoryList() {
    if (_historyList.isEmpty) {
      // 整个记录为空时直接显示空状态（同时也保留下拉刷新能力）
      return RefreshIndicator(
        onRefresh: _refreshHistoryStatus,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: 240,
              child: _buildEmptyState("暂无观看记录", Remix.history_line),
            ),
          ],
        ),
      );
    }
    final platformIds = _activePlatformIdsForHistory();
    final list = _filteredHistory;
    return Column(
      children: [
        _buildPlatformFilterBar(platformIds),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refreshHistoryStatus,
            child: list.isEmpty
                ? ListView(
                    controller: _historyScrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 240,
                        child: _buildEmptyState(
                          "该平台暂无观看记录",
                          Remix.history_line,
                        ),
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _historyScrollController,
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    itemCount: list.length,
                    itemBuilder: (_, i) {
                      var item = list[i];
                      var site = Sites.allSites[item.siteId];
                      if (site == null) return const SizedBox.shrink();
                      bool isPlaying =
                          widget.controller.rxSite.value.id == item.siteId &&
                              widget.controller.rxRoomId.value == item.roomId;
                      int liveStatus = _liveStatusMap[item.id] ?? -1;
                      return _buildHistoryItem(item, site, isPlaying, liveStatus);
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildHistoryItem(
      History item, dynamic site, bool isPlaying, int liveStatus) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () {
        widget.onDismiss();
        widget.controller.resetRoom(
          Sites.allSites[item.siteId]!,
          item.roomId,
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isPlaying
              ? theme.colorScheme.primaryContainer.withAlpha(60)
              : theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: isPlaying
              ? Border.all(
                  color: theme.colorScheme.primary.withAlpha(80),
                  width: 1.5,
                )
              : Border.all(
                  color: Colors.grey.withAlpha(30),
                  width: 0.5,
                ),
          boxShadow: [
            BoxShadow(
              blurRadius: 6,
              color: Colors.black.withAlpha(Get.isDarkMode ? 20 : 12),
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding:
              const EdgeInsets.only(left: 12, top: 10, bottom: 10, right: 4),
          child: Row(
            children: [
              // Avatar + live dot
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.grey.withAlpha(40),
                        width: 1.5,
                      ),
                    ),
                    child: NetImage(
                      item.face,
                      width: 44,
                      height: 44,
                      borderRadius: 22,
                    ),
                  ),
                  // 直播中绿色圆点
                  if (liveStatus == 2)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: _liveColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.cardColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isPlaying ? theme.colorScheme.primary : null,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            site.logo,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          site.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        // 直播状态标签
                        _buildLiveStatusTag(liveStatus),
                        const SizedBox(width: 6),
                        Icon(
                          Remix.time_line,
                          size: 11,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 2),
                        Flexible(
                          child: Text(
                            _formatTime(item.updateTime),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.grey.shade500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Right side
              if (isPlaying)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.play_arrow_rounded,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        "观看中",
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                )
              else
                // Delete button
                SizedBox(
                  width: 36,
                  height: 36,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    onPressed: () => _deleteHistoryItem(item),
                    tooltip: "删除记录",
                    icon: Icon(
                      Remix.close_circle_line,
                      size: 20,
                      color: Colors.grey.shade400,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// 构建直播状态标签（统一风格）
  Widget _buildLiveStatusTag(int liveStatus) {
    if (liveStatus == 0) {
      // 查询中 - 小loading
      return Container(
        margin: const EdgeInsets.only(left: 8),
        width: 12,
        height: 12,
        child: const CircularProgressIndicator(
          strokeWidth: 1.5,
          color: Colors.grey,
        ),
      );
    }
    if (liveStatus == -1) {
      return const SizedBox.shrink(); // 尚未开始查询
    }
    final bool isLive = liveStatus == 2;
    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: isLive ? _liveBgColor : _offlineBgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        isLive ? "直播中" : "未开播",
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          color: isLive ? _liveColor : _offlineColor,
        ),
      ),
    );
  }

  void _showFollowOptions(item) {
    Get.dialog(
      Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 320),
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  item.userName,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(
                  item.pinned ? Remix.unpin_line : Remix.pushpin_line,
                  color: item.pinned ? Colors.orange : null,
                ),
                title: Text(item.pinned ? "取消置顶" : "置顶"),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Get.back();
                  if (item.pinned) {
                    item.pinned = false;
                    item.pinnedTime = null;
                  } else {
                    item.pinned = true;
                    item.pinnedTime = DateTime.now();
                  }
                  await DBService.instance.addFollow(item);
                  FollowService.instance.filterData();
                },
              ),
              ListTile(
                leading: const Icon(Remix.dislike_line, color: Colors.red),
                title: const Text(
                  "取消关注",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  HapticFeedback.mediumImpact();
                  Get.back();
                  await DBService.instance.followBox.delete(item.id);
                  FollowService.instance.filterData();
                  if (widget.controller.rxSite.value.id == item.siteId &&
                      widget.controller.rxRoomId.value == item.roomId) {
                    widget.controller.followed.value = false;
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(String text, IconData icon) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 48,
            color: Colors.grey.withAlpha(80),
          ),
          const SizedBox(height: 12),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRefreshButton({
    required bool refreshing,
    required VoidCallback onPressed,
  }) {
    return FloatingActionButton.small(
      onPressed: refreshing ? null : onPressed,
      child: refreshing
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Remix.refresh_line, size: 20),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) return "刚刚";
    if (diff.inMinutes < 60) return "${diff.inMinutes}分钟前";
    if (diff.inHours < 24) return "${diff.inHours}小时前";
    if (diff.inDays < 7) return "${diff.inDays}天前";
    return "${time.month}/${time.day}";
  }
}
