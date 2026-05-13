import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

/// 快手账号服务：负责持久化与同步登录态到 KuaishouSite。
class KuaishouAccountService extends GetxService {
  static KuaishouAccountService get instance =>
      Get.find<KuaishouAccountService>();

  var logined = false.obs;
  var name = "未登录".obs;
  var avatar = "".obs;
  var cookie = "";

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kKuaishouCookie, "");
    name.value = LocalStorageService.instance
        .getValue(LocalStorageService.kKuaishouUserName, "未登录");
    avatar.value = LocalStorageService.instance
        .getValue(LocalStorageService.kKuaishouAvatar, "");
    logined.value = cookie.isNotEmpty;
    setSite();
    if (logined.value) {
      // 异步校验 cookie 是否仍然有效
      verifyCookie();
    }
    super.onInit();
  }

  /// 把 cookie 同步到 KuaishouSite，让所有接口请求能携带登录态
  void setSite() {
    final site = (Sites.allSites[Constant.kKuaishou]!.liveSite as KuaishouSite);
    site.userCookie = cookie;
  }

  /// 设置登录信息（来自二维码登录流程）
  void setLogin({
    required String cookie,
    required String userName,
    required String userAvatar,
  }) {
    this.cookie = cookie;
    name.value = userName.isEmpty ? "未登录" : userName;
    avatar.value = userAvatar;
    logined.value = cookie.isNotEmpty;
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouCookie, cookie);
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouUserName, name.value);
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouAvatar, avatar.value);
    setSite();
  }

  /// 退出登录
  void logout() {
    cookie = "";
    name.value = "未登录";
    avatar.value = "";
    logined.value = false;
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouCookie, "");
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouUserName, "");
    LocalStorageService.instance
        .setValue(LocalStorageService.kKuaishouAvatar, "");
    setSite();
  }

  /// 校验当前 cookie 是否仍然有效
  Future<void> verifyCookie() async {
    if (cookie.isEmpty) return;
    try {
      final result = await KuaishouQRLogin.verifyByCookiesFull(cookie);
      if (result == null) {
        return;
      }
      final info = result.info;
      if (info.userId.isEmpty) {
        SmartDialog.showToast("快手登录已失效，请重新登录");
        logout();
        return;
      }
      if (result.effectiveCookie.isNotEmpty &&
          result.effectiveCookie != cookie) {
        setLogin(
          cookie: result.effectiveCookie,
          userName: info.name.isEmpty ? name.value : info.name,
          userAvatar: info.avatar.isEmpty ? avatar.value : info.avatar,
        );
        return;
      }
      name.value = info.name.isEmpty ? name.value : info.name;
      avatar.value = info.avatar.isEmpty ? avatar.value : info.avatar;
      LocalStorageService.instance
          .setValue(LocalStorageService.kKuaishouUserName, name.value);
      LocalStorageService.instance
          .setValue(LocalStorageService.kKuaishouAvatar, avatar.value);
    } catch (_) {
      // 网络问题等，不做处理
    }
  }
}
