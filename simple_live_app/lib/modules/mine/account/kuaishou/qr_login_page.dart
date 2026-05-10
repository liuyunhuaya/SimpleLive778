import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:simple_live_app/modules/mine/account/kuaishou/qr_login_controller.dart';

class KuaishouQRLoginPage extends GetView<KuaishouQRLoginController> {
  const KuaishouQRLoginPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("快手账号登录")),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Center(
            child: Obx(
              () {
                final state = controller.status.value;
                if (state == KuaishouLoginStatus.loading) {
                  return const CircularProgressIndicator();
                }
                if (state == KuaishouLoginStatus.failed) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("二维码加载失败"),
                      TextButton(
                        onPressed: controller.loadQRCode,
                        child: const Text("重试"),
                      ),
                    ],
                  );
                }
                if (state == KuaishouLoginStatus.expired) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text("二维码已失效"),
                      TextButton(
                        onPressed: controller.loadQRCode,
                        child: const Text("刷新二维码"),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    ClipRRect(
                      borderRadius: AppStyle.radius12,
                      child: Container(
                        color: Colors.white,
                        padding: AppStyle.edgeInsetsA12,
                        child: SizedBox(
                          width: 200,
                          height: 200,
                          child: controller.qrImage.value != null
                              ? Image.memory(
                                  controller.qrImage.value!,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                )
                              : QrImageView(
                                  data: controller.qrUrl.value,
                                  version: QrVersions.auto,
                                  backgroundColor: Colors.white,
                                  size: 200,
                                ),
                        ),
                      ),
                    ),
                    AppStyle.vGap8,
                    Visibility(
                      visible: state == KuaishouLoginStatus.scanned,
                      child: const Text("已扫描，请在手机上确认登录"),
                    ),
                  ],
                );
              },
            ),
          ),
          const Padding(
            padding: AppStyle.edgeInsetsA24,
            child: Text(
              "请使用快手 / 快手极速版 APP 扫描二维码登录",
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
