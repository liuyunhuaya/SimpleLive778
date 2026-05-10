import 'dart:io';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_menu.dart';
import 'package:simple_live_app/widgets/settings/settings_number.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class PlaySettingsPage extends GetView<AppSettingsController> {
  const PlaySettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("直播间设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 0),
            child: Text(
              "播放器",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsSwitch(
                    title: "硬件解码",
                    value: controller.hardwareDecode.value,
                    subtitle: "播放失败可尝试关闭此选项",
                    onChanged: (e) {
                      controller.setHardwareDecode(e);
                    },
                  ),
                ),
                if (Platform.isAndroid) AppStyle.divider,
                Obx(
                  () => Visibility(
                    visible: Platform.isAndroid,
                    child: SettingsSwitch(
                      title: "兼容模式",
                      subtitle: "若播放卡顿可尝试打开此选项",
                      value: controller.playerCompatMode.value,
                      onChanged: (e) {
                        controller.setPlayerCompatMode(e);
                      },
                    ),
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "缓冲区大小",
                    subtitle: "影响内存占用和网络抖动容忍度，建议16-64秒",
                    value: controller.playerBufferSize.value,
                    min: 8,
                    max: 128,
                    step: 8,
                    unit: "秒",
                    onChanged: (e) {
                      controller.setPlayerBufferSize(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "进入后台自动暂停",
                    value: controller.playerAutoPause.value,
                    onChanged: (e) {
                      controller.setPlayerAutoPause(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "画面尺寸",
                    value: controller.scaleMode.value,
                    valueMap: const {
                      0: "适应",
                      1: "拉伸",
                      2: "铺满",
                      3: "16:9",
                      4: "4:3",
                    },
                    onChanged: (e) {
                      controller.setScaleMode(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "使用HTTPS链接",
                    subtitle: "将http链接替换为https",
                    value: controller.playerForceHttps.value,
                    onChanged: (e) {
                      controller.setPlayerForceHttps(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "直播间",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsSwitch(
                    title: "进入直播间自动全屏",
                    value: controller.autoFullScreen.value,
                    onChanged: (e) {
                      controller.setAutoFullScreen(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => Visibility(
                    visible: Platform.isAndroid,
                    child: SettingsSwitch(
                      title: "进入小窗隐藏弹幕",
                      value: controller.pipHideDanmu.value,
                      onChanged: (e) {
                        controller.setPIPHideDanmu(e);
                      },
                    ),
                  ),
                ),
                if (Platform.isAndroid) AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "启用人数自动刷新",
                    subtitle: "关闭后可减少资源消耗，(应该可以)避免手机发烫",
                    value: controller.roomOnlineRefreshEnable.value,
                    onChanged: (e) {
                      controller.setRoomOnlineRefreshEnable(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "人数刷新间隔",
                    subtitle: "直播间在线人数自动刷新的间隔时间",
                    value: controller.roomOnlineRefreshInterval.value,
                    min: 3,
                    max: 60,
                    step: 1,
                    unit: "秒",
                    enabled: controller.roomOnlineRefreshEnable.value,
                    onChanged: (e) {
                      controller.setRoomOnlineRefreshInterval(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "人数精确显示",
                    subtitle: "开启后显示完整数字（如12,345），关闭后显示格式化数字（如1.2万）",
                    value: controller.roomOnlineExactDisplay.value,
                    onChanged: (e) {
                      controller.setRoomOnlineExactDisplay(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "播放器中显示SC",
                    value: controller.playershowSuperChat.value,
                    onChanged: (e) {
                      controller.setPlayerShowSuperChat(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "搜索",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsSwitch(
                    title: "虎牙搜索主播按开播排序",
                    subtitle: "开启后会加载全部搜索结果再排序，可能需要等待较长时间",
                    value: controller.huyaSearchAnchorSortByLive.value,
                    onChanged: (e) {
                      controller.setHuyaSearchAnchorSortByLive(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "清晰度",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => SettingsMenu<int>(
                    title: "默认清晰度",
                    value: controller.qualityLevel.value,
                    valueMap: const {
                      0: "最低",
                      1: "中等",
                      2: "最高",
                    },
                    onChanged: (e) {
                      controller.setQualityLevel(e);
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsMenu<int>(
                    title: "数据网络清晰度",
                    value: controller.qualityLevelCellular.value,
                    valueMap: const {
                      0: "最低",
                      1: "中等",
                      2: "最高",
                    },
                    onChanged: (e) {
                      controller.setQualityLevelCellular(e);
                    },
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: AppStyle.edgeInsetsA12.copyWith(top: 24),
            child: Text(
              "聊天区",
              style: Get.textTheme.titleSmall,
            ),
          ),
          SettingsCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Obx(
                  () => SettingsNumber(
                    title: "文字大小",
                    value: controller.chatTextSize.value.toInt(),
                    min: 8,
                    max: 36,
                    onChanged: (e) {
                      controller.setChatTextSize(e.toDouble());
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsNumber(
                    title: "上下间隔",
                    value: controller.chatTextGap.value.toInt(),
                    min: 0,
                    max: 12,
                    onChanged: (e) {
                      controller.setChatTextGap(e.toDouble());
                    },
                  ),
                ),
                AppStyle.divider,
                Obx(
                  () => SettingsSwitch(
                    title: "气泡样式",
                    value: controller.chatBubbleStyle.value,
                    onChanged: (e) {
                      controller.setChatBubbleStyle(e);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
