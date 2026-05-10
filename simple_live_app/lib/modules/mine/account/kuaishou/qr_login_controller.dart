import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/log.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

enum KuaishouLoginStatus {
  loading,
  unscanned,
  scanned,
  expired,
  failed,
}

class KuaishouQRLoginController extends GetxController {
  final KuaishouQRLogin _login = KuaishouQRLogin();

  /// 二维码图片字节（base64 解码）
  var qrImage = Rx<Uint8List?>(null);

  /// 二维码原始 URL（备用，扫码图片为空时直接生成）
  var qrUrl = "".obs;

  Rx<KuaishouLoginStatus> status = KuaishouLoginStatus.loading.obs;

  Timer? _timer;
  bool _accepted = false;
  int _expireTime = 0;

  @override
  void onInit() {
    loadQRCode();
    super.onInit();
  }

  Future<void> loadQRCode() async {
    try {
      status.value = KuaishouLoginStatus.loading;
      qrImage.value = null;
      _accepted = false;
      final result = await _login.start();
      qrUrl.value = result.qrUrl;
      _expireTime = result.expireTime;
      if (result.imageData.isNotEmpty) {
        try {
          qrImage.value = base64Decode(result.imageData);
        } catch (e) {
          Log.logPrint("快手二维码图片解码失败: $e");
        }
      }
      status.value = KuaishouLoginStatus.unscanned;
      _startPoll();
    } catch (e) {
      Log.logPrint("快手二维码加载失败: $e");
      status.value = KuaishouLoginStatus.failed;
    }
  }

  void _startPoll() {
    _timer?.cancel();
    // 轮询间隔缩短到 1.5s，贴近浏览器行为，减少手机确认后响应滞后
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      try {
        await _pollOnce();
      } catch (e) {
        Log.logPrint("快手登录轮询异常: $e");
      }
    });
  }

  /// 客户端主动判断二维码是否真正过期（服务端给的绝对时间）
  bool _qrExpiredByTime() {
    if (_expireTime <= 0) return false;
    return DateTime.now().millisecondsSinceEpoch >= _expireTime;
  }

  Future<void> _pollOnce() async {
    if (_accepted) return;
    // 1) 扫描状态
    if (status.value == KuaishouLoginStatus.unscanned) {
      final scan = await _login.pollScanResult();
      if (scan.state == KuaishouQRScanState.scanned) {
        status.value = KuaishouLoginStatus.scanned;
      } else if (scan.state == KuaishouQRScanState.expired ||
          _qrExpiredByTime()) {
        _timer?.cancel();
        status.value = KuaishouLoginStatus.expired;
        return;
      }
    }
    if (status.value != KuaishouLoginStatus.scanned) return;

    // 2) 用户点击确认
    final accept = await _login.pollAcceptResult();
    if (accept.state == KuaishouQRScanState.accepted &&
        (accept.qrToken ?? "").isNotEmpty) {
      _accepted = true;
      _timer?.cancel();
      await _finishLogin(accept.qrToken!);
      return;
    }
    // 已扫码后的过期判定更严格：服务端明确过期 + 本地已超时才结束
    if (accept.state == KuaishouQRScanState.expired && _qrExpiredByTime()) {
      _timer?.cancel();
      status.value = KuaishouLoginStatus.expired;
    }
  }

  Future<void> _finishLogin(String qrToken) async {
    try {
      SmartDialog.showLoading(msg: "登录中...");
      final ok = await _login.callback(qrToken);
      if (!ok) {
        throw "服务端拒绝登录";
      }
      // 不强依赖 webLogin 接口的成功状态，但仍然请求一次以累计完整 cookies
      await _login.webLogin();
      final info = await _login.fetchUserInfo();
      KuaishouAccountService.instance.setLogin(
        cookie: _login.cookies,
        userName: info?.name ?? "已登录",
        userAvatar: info?.avatar ?? "",
      );
      SmartDialog.dismiss();
      SmartDialog.showToast("快手登录成功");
      Get.back();
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast("快手登录失败：$e");
      status.value = KuaishouLoginStatus.failed;
    }
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
