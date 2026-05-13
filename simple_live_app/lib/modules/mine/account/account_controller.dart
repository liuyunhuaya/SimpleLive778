import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:simple_live_app/app/utils.dart';
import 'package:simple_live_app/routes/route_path.dart';
import 'package:simple_live_app/services/bilibili_account_service.dart';
import 'package:simple_live_app/services/douyin_account_service.dart';
import 'package:simple_live_app/services/kuaishou_account_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class AccountController extends GetxController {
  void bilibiliTap() async {
    if (BiliBiliAccountService.instance.logined.value) {
      var result = await Utils.showAlertDialog("确定要退出哔哩哔哩账号吗？", title: "退出登录");
      if (result) {
        BiliBiliAccountService.instance.logout();
      }
    } else {
      bilibiliLogin();
    }
  }

  void bilibiliLogin() {
    Utils.showBottomSheet(
      title: "登录哔哩哔哩",
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Visibility(
            visible: Platform.isAndroid || Platform.isIOS,
            child: ListTile(
              leading: const Icon(Icons.account_circle_outlined),
              title: const Text("Web登录"),
              subtitle: const Text("填写用户名密码登录"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Get.back();
                Get.toNamed(RoutePath.kBiliBiliWebLogin);
              },
            ),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code),
            title: const Text("扫码登录"),
            subtitle: const Text("使用哔哩哔哩APP扫描二维码登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              Get.toNamed(RoutePath.kBiliBiliQRLogin);
            },
          ),
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text("Cookie登录"),
            subtitle: const Text("手动输入Cookie登录"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Get.back();
              doBiliBiliCookieLogin();
            },
          ),
        ],
      ),
    );
  }

  void doBiliBiliCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入Cookie",
      hintText: "请输入Cookie",
    );
    if (cookie == null || cookie.isEmpty) {
      return;
    }
    BiliBiliAccountService.instance.setCookie(cookie);
    await BiliBiliAccountService.instance.loadUserInfo();
  }

  void douyinTap() {
    showDouyinCookiePoolDialog();
  }

  void kuaishouTap() async {
    if (KuaishouAccountService.instance.logined.value) {
      showKuaishouAccountInfoDialog();
    } else {
      kuaishouLogin();
    }
  }

  /// 已登录情况下点击「快手」入口，弹出账号详情管理：
  /// 显示当前用户、关键 Cookie 字段摘要、完整 Cookie（可选中复制），
  /// 并提供 复制 / 重新登录 / 退出登录 操作。
  void showKuaishouAccountInfoDialog() {
    final service = KuaishouAccountService.instance;
    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            ClipOval(
              child: service.avatar.value.isNotEmpty
                  ? Image.network(
                      service.avatar.value,
                      width: 32,
                      height: 32,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Image.asset(
                        'assets/images/kuaishou.png',
                        width: 32,
                        height: 32,
                      ),
                    )
                  : Image.asset(
                      'assets/images/kuaishou.png',
                      width: 32,
                      height: 32,
                    ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Obx(() => Text(
                    service.name.value,
                    style: const TextStyle(fontSize: 16),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  )),
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildKuaishouCookieSummary(service.cookie),
              const SizedBox(height: 10),
              const Text(
                "完整 Cookie（长按可选中）：",
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 200),
                child: Container(
                  width: double.maxFinite,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Get.isDarkMode
                        ? Colors.white.withOpacity(0.06)
                        : Colors.black.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Scrollbar(
                    child: SingleChildScrollView(
                      child: SelectableText(
                        service.cookie.isEmpty ? "(空)" : service.cookie,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: "monospace",
                          height: 1.4,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                "共 ${service.cookie.length} 字符",
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              Get.back();
              var ok = await Utils.showAlertDialog(
                "确定要退出快手账号吗？",
                title: "退出登录",
              );
              if (ok) {
                KuaishouAccountService.instance.logout();
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text("退出登录"),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              kuaishouLogin();
            },
            child: const Text("重新登录"),
          ),
          TextButton(
            onPressed: () {
              if (service.cookie.isEmpty) {
                SmartDialog.showToast("Cookie 为空");
                return;
              }
              Clipboard.setData(ClipboardData(text: service.cookie));
              SmartDialog.showToast("已复制完整 Cookie");
            },
            child: const Text("复制Cookie"),
          ),
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("关闭"),
          ),
        ],
      ),
    );
  }

  /// 拆解快手 Cookie 字符串，展示关键登录字段的存在情况，
  /// 让用户一眼看出当前 Cookie 是否携带了完整登录态。
  Widget _buildKuaishouCookieSummary(String cookie) {
    // 关键字段 -> 显示名
    const keys = <String, String>{
      "kuaishou.live.web_st": "web_st",
      "kuaishou.live.web.at": "web.at",
      "kuaishou.live.web_ph": "web_ph",
      "passToken": "passToken",
      "userId": "userId",
      "did": "did",
      "kpn": "kpn",
    };
    final pairs = <String, String>{};
    for (final seg in cookie.split(";")) {
      final p = seg.trim();
      if (p.isEmpty) continue;
      final eq = p.indexOf("=");
      if (eq <= 0) continue;
      pairs[p.substring(0, eq).trim()] = p.substring(eq + 1).trim();
    }
    final chips = <Widget>[];
    keys.forEach((key, label) {
      final has = pairs[key]?.isNotEmpty == true;
      chips.add(Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: has
              ? Colors.green.withOpacity(0.12)
              : Colors.grey.withOpacity(0.18),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          "${has ? "✓" : "·"} $label",
          style: TextStyle(
            fontSize: 11,
            color: has ? Colors.green.shade700 : Colors.grey,
          ),
        ),
      ));
    });
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          "关键字段：",
          style: TextStyle(fontSize: 13, color: Colors.grey),
        ),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: chips),
      ],
    );
  }

  /// 快手登录入口
  ///
  /// 仅保留 Cookie 登录方式（已移除二维码登录），点击后直接弹出 Cookie 登录教程，
  /// 用户阅读步骤后可直接粘贴 Cookie 完成登录。
  void kuaishouLogin() {
    showKuaishouCookieTutorial();
  }

  /// 快手 Cookie 登录·教程与输入
  void showKuaishouCookieTutorial() {
    Get.dialog(
      AlertDialog(
        title: const Text("快手 Cookie 登录"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "获取步骤：",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                "1. 在电脑浏览器登录 live.kuaishou.com\n"
                "2. 按 F12 打开开发者工具，切换到「网络」或「应用程序」\n"
                "3. 网络：刷新页面，点任意 live.kuaishou.com 请求，在请求头里复制完整 Cookie\n"
                "   或 应用程序：左侧「Cookie」→「https://live.kuaishou.com」全选字段导出\n"
                "4. 至少需包含：kuaishou.live.web_st、userId；建议同时包含 did、clientid、\n"
                "   kwfv1、kwssectoken、kwscode、kuaishou.live.bfb1s、kuaishou.live.web_ph 等\n"
                "5. 可直接粘贴一整段（重复 did/userId 会自动合并）",
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 12),
              Text(
                "提示",
                style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.orange),
              ),
              SizedBox(height: 6),
              Text(
                "• 不登录也能正常播放高画质，只在需要登录态的功能（如关注同步）才需要 Cookie\n"
                "• Cookie 失效后 APP 会提示，请重新粘贴",
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              Get.back();
              doKuaishouCookieLogin();
            },
            child: const Text("我已知晓·继续"),
          ),
        ],
      ),
    );
  }

  Future<void> doKuaishouCookieLogin() async {
    var cookie = await Utils.showEditTextDialog(
      "",
      title: "请输入快手 Cookie",
      hintText: "粘贴完整 Cookie 字符串",
    );
    if (cookie == null || cookie.trim().isEmpty) return;
    cookie = cookie.trim();
    SmartDialog.showLoading(msg: "校验 Cookie...");
    try {
      final result = await KuaishouQRLogin.verifyByCookiesFull(cookie);
      SmartDialog.dismiss();
      if (result == null || result.info.userId.isEmpty) {
        SmartDialog.showToast("Cookie 无效或已失效，请重新获取");
        return;
      }
      final info = result.info;
      KuaishouAccountService.instance.setLogin(
        cookie: result.effectiveCookie,
        userName: info.name.isEmpty ? "已登录" : info.name,
        userAvatar: info.avatar,
      );
      SmartDialog.showToast("快手登录成功");
    } catch (e) {
      SmartDialog.dismiss();
      SmartDialog.showToast("登录失败：$e");
    }
  }
  
  /// 显示获取Cookie教程弹窗
  void showCookieTutorial() {
    Get.dialog(
      AlertDialog(
        title: const Text("获取抖音ttwid教程"),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Text(
                "方法一：电脑浏览器获取",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                "1. 电脑打开浏览器，访问 live.douyin.com\n"
                "2. 按 F12 打开开发者工具\n"
                "3. 切换到「应用程序」或「Application」标签\n"
                "4. 在左侧找到「Cookie」→「live.douyin.com」\n"
                "5. 找到名为「ttwid」的项，复制其值",
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 16),
              Text(
                "方法二：手机抓包获取",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              SizedBox(height: 8),
              Text(
                "使用抓包工具（如HttpCanary、Charles等）\n"
                "抓取抖音直播请求中的Cookie，\n"
                "找到ttwid字段即可。",
                style: TextStyle(fontSize: 13),
              ),
              SizedBox(height: 16),
              Text(
                "提示",
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.orange),
              ),
              SizedBox(height: 8),
              Text(
                "• ttwid有效期较长，一般不需要频繁更换\n"
                "• 可以添加多个ttwid，失败时自动切换\n"
                "• 支持粘贴完整Cookie，会自动提取ttwid",
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("知道了"),
          ),
        ],
      ),
    );
  }
  
  /// 显示抖音Cookie池管理弹窗
  void showDouyinCookiePoolDialog() {
    Get.dialog(
      AlertDialog(
        title: Row(
          children: [
            const Text("抖音Cookie池"),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.help_outline, size: 20),
              onPressed: showCookieTutorial,
              tooltip: "获取Cookie教程",
            ),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                "进入直播间失败时会自动轮换ttwid尝试",
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              Obx(() => ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 300),
                child: DouyinAccountService.instance.cookiePool.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text("Cookie池为空，请添加ttwid"),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: DouyinAccountService.instance.cookiePool.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          var ttwid = DouyinAccountService.instance.cookiePool[index];
                          var shortId = _getShortTtwid(ttwid);
                          var createTime = _getTtwidCreateTime(ttwid);
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                            child: Row(
                              children: [
                                // 左侧信息
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        "ttwid #${index + 1}",
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        shortId,
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (createTime != null) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          "创建于 $createTime",
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                                // 右侧操作按钮
                                IconButton(
                                  icon: const Icon(Icons.copy, size: 20),
                                  onPressed: () => _copyTtwid(ttwid),
                                  tooltip: "复制",
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                ),
                                const SizedBox(width: 8),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 20, color: Colors.red),
                                  onPressed: () => _deleteTtwid(index),
                                  tooltip: "删除",
                                  padding: const EdgeInsets.all(8),
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              )),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              DouyinAccountService.instance.resetCookiePool();
              SmartDialog.showToast("已恢复默认ttwid");
            },
            child: const Text("恢复默认"),
          ),
          TextButton(
            onPressed: () => _showAddTtwidDialog(),
            child: const Text("添加ttwid"),
          ),
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("关闭"),
          ),
        ],
      ),
    );
  }
  
  /// 获取ttwid的短显示形式
  String _getShortTtwid(String ttwid) {
    var value = ttwid;
    if (value.startsWith('ttwid=')) {
      value = value.substring(6);
    }
    if (value.length > 30) {
      return "${value.substring(0, 15)}...${value.substring(value.length - 10)}";
    }
    return value;
  }
  
  /// 从ttwid中提取创建时间
  /// ttwid格式: 1|xxx|timestamp|hash (URL编码后 %7C 是 |)
  String? _getTtwidCreateTime(String ttwid) {
    try {
      var value = ttwid;
      if (value.startsWith('ttwid=')) {
        value = value.substring(6);
      }
      // URL解码
      value = Uri.decodeComponent(value);
      // 按 | 分割
      var parts = value.split('|');
      if (parts.length >= 3) {
        var timestamp = int.tryParse(parts[2]);
        if (timestamp != null) {
          var date = DateTime.fromMillisecondsSinceEpoch(timestamp * 1000);
          // 格式化日期
          return "${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}";
        }
      }
    } catch (e) {
      // 解析失败，返回null
    }
    return null;
  }
  
  /// 复制ttwid
  void _copyTtwid(String ttwid) {
    var value = ttwid;
    if (value.startsWith('ttwid=')) {
      value = value.substring(6);
    }
    Clipboard.setData(ClipboardData(text: value));
    SmartDialog.showToast("已复制到剪贴板");
  }
  
  /// 删除ttwid
  void _deleteTtwid(int index) async {
    if (DouyinAccountService.instance.cookiePool.length <= 1) {
      SmartDialog.showToast("至少保留一个ttwid");
      return;
    }
    var result = await Utils.showAlertDialog("确定要删除这个ttwid吗？", title: "删除确认");
    if (result) {
      DouyinAccountService.instance.removeFromCookiePool(index);
      SmartDialog.showToast("已删除");
    }
  }
  
  /// 显示添加ttwid弹窗
  void _showAddTtwidDialog() {
    var controller = TextEditingController();
    Get.dialog(
      AlertDialog(
        title: const Text("添加ttwid"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "支持以下格式：\n"
              "• 完整Cookie（会自动提取ttwid）\n"
              "• ttwid=xxx 格式\n"
              "• 纯ttwid值",
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: "粘贴ttwid或完整Cookie",
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Get.back(),
            child: const Text("取消"),
          ),
          TextButton(
            onPressed: () {
              var input = controller.text.trim();
              if (input.isEmpty) {
                SmartDialog.showToast("请输入内容");
                return;
              }
              var success = DouyinAccountService.instance.addToCookiePool(input);
              if (success) {
                Get.back();
                SmartDialog.showToast("添加成功");
              } else {
                var ttwid = DouyinAccountService.extractTtwid(input);
                if (ttwid == null) {
                  SmartDialog.showToast("无法识别ttwid，请检查格式");
                } else {
                  SmartDialog.showToast("该ttwid已存在");
                }
              }
            },
            child: const Text("添加"),
          ),
        ],
      ),
    );
  }
}
