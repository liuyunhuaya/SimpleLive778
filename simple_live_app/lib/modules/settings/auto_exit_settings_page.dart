import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/widgets/settings/settings_action.dart';
import 'package:simple_live_app/widgets/settings/settings_card.dart';
import 'package:simple_live_app/widgets/settings/settings_switch.dart';

class AutoExitSettingsPage extends GetView<AppSettingsController> {
  const AutoExitSettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("定时关闭设置"),
      ),
      body: ListView(
        padding: AppStyle.edgeInsetsA12,
        children: [
          SettingsCard(
            child: Column(
              children: [
                Obx(
                  () => SettingsSwitch(
                    value: controller.autoExitEnable.value,
                    title: "启用定时关闭",
                    onChanged: (e) {
                      controller.setAutoExitEnable(e);
                    },
                  ),
                ),
                Obx(
                  () => Visibility(
                    visible: controller.autoExitEnable.value,
                    child: AppStyle.divider,
                  ),
                ),
                // 模式选择
                Obx(
                  () => Visibility(
                    visible: controller.autoExitEnable.value,
                    child: Padding(
                      padding: AppStyle.edgeInsetsH12.copyWith(top: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildModeChip(
                              context,
                              0,
                              "倒计时关闭",
                              "进入直播间后倒计时",
                            ),
                          ),
                          AppStyle.hGap12,
                          Expanded(
                            child: _buildModeChip(
                              context,
                              1,
                              "定时关闭",
                              "到达指定时间点关闭",
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Obx(
                  () => Visibility(
                    visible: controller.autoExitEnable.value &&
                        controller.autoExitMode.value == 0,
                    child: AppStyle.divider,
                  ),
                ),
                Obx(
                  () => Visibility(
                    visible: controller.autoExitEnable.value &&
                        controller.autoExitMode.value == 0,
                    child: SettingsAction(
                      title: "自动关闭时间",
                      value:
                          "${controller.autoExitDuration.value ~/ 60}小时${controller.autoExitDuration.value % 60}分钟",
                      subtitle: "从进入直播间开始倒计时",
                      onTap: () {
                        setTimer(context);
                      },
                    ),
                  ),
                ),
                Obx(
                  () => Visibility(
                    visible: controller.autoExitEnable.value &&
                        controller.autoExitMode.value == 1,
                    child: AppStyle.divider,
                  ),
                ),
                Obx(
                  () => Visibility(
                    visible: controller.autoExitEnable.value &&
                        controller.autoExitMode.value == 1,
                    child: SettingsAction(
                      title: "目标时间",
                      value: _formatTargetTime(
                          controller.autoExitTargetMinutes.value),
                      subtitle: "到达该时间点自动关闭应用",
                      onTap: () {
                        setTargetTime(context);
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeChip(
      BuildContext context, int value, String title, String subtitle) {
    return Obx(() {
      final selected = controller.autoExitMode.value == value;
      return Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => controller.setAutoExitMode(value),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
            decoration: BoxDecoration(
              color: selected
                  ? Theme.of(context).colorScheme.primary.withAlpha(30)
                  : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey.withAlpha(60),
              ),
            ),
            child: Column(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }

  String _formatTargetTime(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return "$h:$m";
  }

  void setTimer(BuildContext context) async {
    var value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: controller.autoExitDuration.value ~/ 60,
        minute: controller.autoExitDuration.value % 60,
      ),
      initialEntryMode: TimePickerEntryMode.inputOnly,
      builder: (_, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        );
      },
    );
    if (value == null || (value.hour == 0 && value.minute == 0)) {
      return;
    }
    var duration = Duration(hours: value.hour, minutes: value.minute);
    controller.setAutoExitDuration(duration.inMinutes);
  }

  void setTargetTime(BuildContext context) async {
    var value = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: controller.autoExitTargetMinutes.value ~/ 60,
        minute: controller.autoExitTargetMinutes.value % 60,
      ),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (_, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        );
      },
    );
    if (value == null) return;
    controller.setAutoExitTargetMinutes(value.hour * 60 + value.minute);
  }
}
