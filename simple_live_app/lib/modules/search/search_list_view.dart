import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/search/search_list_controller.dart';
import 'package:simple_live_app/routes/app_navigation.dart';
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
      child: Obx(
        () => controller.searchMode.value == 0
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
              ),
      ),
    );
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
                        Image.asset(
                          controller.site.logo,
                          width: 16,
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
