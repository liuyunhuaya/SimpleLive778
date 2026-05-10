import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/modules/live_room/live_room_controller.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 直播间榜单内嵌视图（贡献榜 / 亲密榜 / 高能榜）
/// - 进入即拉取一次
/// - 支持下拉刷新（与 buildFollowList 一致的交互）
/// - 不支持榜单的平台显示提示信息
class LiveRankView extends StatefulWidget {
  final LiveRoomController controller;
  const LiveRankView({required this.controller, Key? key}) : super(key: key);

  @override
  State<LiveRankView> createState() => _LiveRankViewState();
}

class _LiveRankViewState extends State<LiveRankView>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 进入榜单 tab 即首次拉取（仅在数据为空时，避免 tab 切换重复请求）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = widget.controller;
      if (c.site.liveSite.supportLiveRank &&
          c.liveRankResult.value == null &&
          !c.isLoadingRank.value) {
        c.fetchLiveRanks();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    return Obx(() {
      final supportRank = widget.controller.site.liveSite.supportLiveRank;
      if (!supportRank) {
        return _buildEmpty(text: "当前平台暂不支持榜单");
      }
      final isLoading = widget.controller.isLoadingRank.value;
      final result = widget.controller.liveRankResult.value;
      final items = result?.items ?? const <LiveRankItem>[];

      Widget body;
      if (items.isEmpty) {
        body = ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(
              height: MediaQuery.of(context).size.height * 0.4,
              child: isLoading && result == null
                  ? const Center(child: CircularProgressIndicator())
                  : _buildEmpty(),
            ),
          ],
        );
      } else {
        body = ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: items.length,
          separatorBuilder: (_, __) => Divider(
            height: 1,
            color: theme.dividerColor.withAlpha(60),
            indent: 64,
            endIndent: 16,
          ),
          itemBuilder: (_, i) => _buildRankItem(items[i]),
        );
      }

      return Column(
        children: [
          // 标题栏：榜单名 + 刷新按钮
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 4),
            child: Row(
              children: [
                const Icon(Remix.medal_2_fill, color: Colors.orange, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    result?.title ?? "榜单",
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: "刷新榜单",
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  onPressed:
                      isLoading ? null : () => widget.controller.fetchLiveRanks(),
                  icon: isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Remix.refresh_line),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => widget.controller.fetchLiveRanks(),
              child: body,
            ),
          ),
        ],
      );
    });
  }

  Widget _buildEmpty({String text = "暂无榜单数据"}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Remix.bar_chart_box_line,
                size: 48, color: Colors.grey.withAlpha(120)),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRankItem(LiveRankItem item) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 32,
            child: Center(child: _buildRankBadge(item.rank)),
          ),
          const SizedBox(width: 8),
          NetImage(
            item.avatar,
            width: 38,
            height: 38,
            borderRadius: 19,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.userName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                _buildBadgeRow(item),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (item.score.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.score,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if ((item.scoreDetail ?? "").isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      item.scoreDetail!,
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
    );
  }

  Widget _buildBadgeRow(LiveRankItem item) {
    final badges = <Widget>[];
    if (item.medalName.isNotEmpty) badges.add(_buildFansMedal(item));
    if ((item.levelText ?? "").isNotEmpty || item.level > 0) {
      badges.add(_buildLevelBadge(item));
    }
    if (badges.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Wrap(
        spacing: 4,
        runSpacing: 2,
        children: badges,
      ),
    );
  }

  Widget _buildFansMedal(LiveRankItem item) {
    final hasIcon = (item.medalIcon ?? "").isNotEmpty;
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: hasIcon ? 0 : 6,
        vertical: 1,
      ),
      decoration: hasIcon
          ? null
          : BoxDecoration(
              color: Colors.purple.withAlpha(40),
              borderRadius: BorderRadius.circular(4),
            ),
      child: hasIcon
          ? NetImage(
              item.medalIcon!,
              height: 14,
              width: 36,
              borderRadius: 2,
              fit: BoxFit.contain,
            )
          : Text(
              item.fansLevel > 0
                  ? "${item.medalName} ${item.fansLevel}"
                  : item.medalName,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.purple,
                fontWeight: FontWeight.w600,
              ),
            ),
    );
  }

  Widget _buildLevelBadge(LiveRankItem item) {
    final hasIcon = (item.levelIcon ?? "").isNotEmpty;
    final text = (item.levelText ?? "").isNotEmpty
        ? item.levelText!
        : "Lv.${item.level}";
    if (hasIcon) {
      return NetImage(
        item.levelIcon!,
        height: 14,
        width: 36,
        borderRadius: 2,
        fit: BoxFit.contain,
      );
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: Colors.amber.withAlpha(40),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          color: Colors.amber.shade800,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildRankBadge(int rank) {
    Color color;
    if (rank == 1) {
      color = const Color(0xFFFFB300);
    } else if (rank == 2) {
      color = const Color(0xFF9E9E9E);
    } else if (rank == 3) {
      color = const Color(0xFFCE7F3A);
    } else {
      return Text(
        "$rank",
        style: TextStyle(
          fontSize: 14,
          color: Colors.grey.shade500,
          fontWeight: FontWeight.w600,
        ),
      );
    }
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withAlpha(180)],
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: color.withAlpha(80),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        "$rank",
        style: const TextStyle(
          fontSize: 12,
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
