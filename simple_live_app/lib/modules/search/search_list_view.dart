import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:remixicon/remixicon.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/modules/mine/account/account_controller.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_app/widgets/keep_alive_wrapper.dart';
import 'package:simple_live_app/widgets/live_room_card.dart';
import 'package:simple_live_app/widgets/net_image.dart';
import 'package:simple_live_app/widgets/page_grid_view.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SearchListView extends StatelessWidget {
  final String tag;
  const SearchListView(this.tag, {Key? key}) : super(key: key);
  SearchListController get controller =>
      Get.find<SearchListController>(tag: tag);
  @override
  Widget build(BuildContext context) {
    var roomRowCount = MediaQuery.of(context).size.width ~/ 200;
    if (roomRowCount < 2) roomRowCount = 2;

    var userRowCount = MediaQuery.of(context).size.width ~/ 500;
    if (userRowCount < 1) userRowCount = 1;
    return KeepAliveWrapper(
      child: Obx(() {
        // 仅在快手 Tab、且未登录时，在搜索列表顶部显示一条引导登录的卡片，
        // 同时仍保留下方的搜索结果（接口已支持匿名访问，仅是登录后体验更好）。
        final isKuaishou = controller.site.id == Constant.kKuaishou;
        final needLoginTip =
            isKuaishou && !KuaishouAccountService.instance.logined.value;

        Widget body = controller.searchMode.value == 0
            ? PageGridView(
                pageController: controller,
                padding: AppStyle.edgeInsetsA12,
                firstRefresh: false,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                crossAxisCount: roomRowCount,
                showPageLoadding: true,
                itemBuilder: (_, i) {
                  var item = controller.list[i] as LiveRoomItem;
                  return LiveRoomCard(controller.site, item);
                },
              )
            : PageGridView(
                crossAxisSpacing: 12,
                crossAxisCount: userRowCount,
                pageController: controller,
                firstRefresh: true,
                showPageLoadding: true,
                padding: AppStyle.edgeInsetsA12,
                mainAxisSpacing: 8,
                itemBuilder: (_, i) {
                  var item = controller.list[i] as LiveAnchorItem;
                  return _buildAnchorCard(context, item);
                },
              );

        if (!needLoginTip) {
          return body;
        }
        return Column(
          children: [
            _buildKuaishouLoginTip(context),
            Expanded(child: body),
          ],
        );
      }),
    );
  }

  /// 快手未登录提示卡片：未登录时部分主播会被搜索接口降权或截断，
  /// 提供 "Cookie 登录" 一键入口，点击后直接弹出 Cookie 教程对话框，
  /// 用户粘贴 Cookie 后即时生效，搜索列表会自动按登录态重新拉取。
  Widget _buildKuaishouLoginTip(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.orange.withAlpha(20),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withAlpha(60), width: 0.6),
      ),
      child: Row(
        children: [
          Icon(Remix.information_line,
              size: 20, color: Colors.orange.shade700),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "快手搜索建议先登录",
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange.shade800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  "未登录可能拿不到完整结果，登录后可获取更全的主播列表与最高清晰度。",
                  style: TextStyle(
                    fontSize: 12,
                    color: theme.textTheme.bodySmall?.color,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showKuaishouCookieLogin,
            icon: const Icon(Remix.key_2_line, size: 14),
            label: const Text("Cookie 登录", style: TextStyle(fontSize: 12)),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
              elevation: 0,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              minimumSize: const Size(0, 32),
            ),
          ),
        ],
      ),
    );
  }

  /// 弹出快手 Cookie 登录教程对话框（复用账号管理页的入口逻辑，避免重复维护）
  void _showKuaishouCookieLogin() {
    // AccountController 可能未注册（用户未进入账号管理页），用 lazyPut 临时拿一个实例
    if (!Get.isRegistered<AccountController>()) {
      Get.put(AccountController(), permanent: false);
    }
    Get.find<AccountController>().showKuaishouCookieTutorial();
  }

  Widget _buildAnchorCard(BuildContext context, LiveAnchorItem item) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
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
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          AppNavigator.toLiveRoomDetail(
              site: controller.site, roomId: item.roomId);
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // 头像
              Stack(
                children: [
                  Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: item.liveStatus
                            ? Colors.green.withAlpha(100)
                            : Colors.grey.withAlpha(40),
                        width: 2,
                      ),
                    ),
                    child: NetImage(
                      item.avatar,
                      width: 46,
                      height: 46,
                      borderRadius: 23,
                    ),
                  ),
                  if (item.liveStatus)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Theme.of(context).cardColor,
                            width: 2,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              // 信息
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.userName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ClipOval(
                          child: Image.asset(
                            controller.site.logo,
                            width: 16,
                            height: 16,
                            fit: BoxFit.cover,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          controller.site.name,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // 直播状态标签
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: item.liveStatus
                      ? Colors.green.withAlpha(25)
                      : Colors.grey.withAlpha(20),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: item.liveStatus
                        ? Colors.green.withAlpha(60)
                        : Colors.grey.withAlpha(40),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: item.liveStatus ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      item.liveStatus ? "直播中" : "未开播",
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: item.liveStatus ? Colors.green : Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
