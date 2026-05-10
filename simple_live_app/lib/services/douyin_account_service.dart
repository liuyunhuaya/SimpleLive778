import 'dart:convert';
import 'package:get/get.dart';
import 'package:simple_live_app/app/constant.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_app/services/local_storage_service.dart';
import 'package:simple_live_core/simple_live_core.dart';

class DouyinAccountService extends GetxService {
  static DouyinAccountService get instance =>
      Get.find<DouyinAccountService>();

  var cookie = "";
  var hasCookie = false.obs;
  
  /// Cookie池列表
  var cookiePool = <String>[].obs;

  @override
  void onInit() {
    cookie = LocalStorageService.instance
        .getValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = cookie.isNotEmpty;
    
    // 加载Cookie池
    _loadCookiePool();
    
    setSite();
    super.onInit();
  }
  
  /// 加载Cookie池
  void _loadCookiePool() {
    try {
      var poolJson = LocalStorageService.instance
          .getValue(LocalStorageService.kDouyinCookiePool, "");
      if (poolJson.isNotEmpty) {
        var list = jsonDecode(poolJson) as List;
        cookiePool.value = list.cast<String>();
      }
    } catch (e) {
      cookiePool.value = [];
    }
    
    // 如果Cookie池为空，使用默认的ttwid
    if (cookiePool.isEmpty) {
      cookiePool.value = List.from(DouyinSite.kCookiePool);
      _saveCookiePool();
    }
  }
  
  /// 保存Cookie池
  void _saveCookiePool() {
    LocalStorageService.instance.setValue(
      LocalStorageService.kDouyinCookiePool, 
      jsonEncode(cookiePool.toList())
    );
  }

  void setSite() {
    var site = (Sites.allSites[Constant.kDouyin]!.liveSite as DouyinSite);
    site.cookie = cookie;
    // 同步Cookie池到DouyinSite
    DouyinSite.kCookiePool = cookiePool.toList();
  }

  void setCookie(String cookie) {
    this.cookie = cookie;
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, cookie);
    hasCookie.value = cookie.isNotEmpty;
    setSite();
  }

  void clearCookie() {
    cookie = "";
    LocalStorageService.instance
        .setValue(LocalStorageService.kDouyinCookie, "");
    hasCookie.value = false;
    setSite();
  }
  
  /// 从完整Cookie中提取ttwid
  static String? extractTtwid(String input) {
    if (input.isEmpty) return null;
    
    // 如果输入包含ttwid=，提取ttwid值
    var ttwidMatch = RegExp(r'ttwid=([^;]+)').firstMatch(input);
    if (ttwidMatch != null) {
      return "ttwid=${ttwidMatch.group(1)}";
    }
    
    // 如果输入本身就是ttwid值（不包含=号和;号）
    if (!input.contains('=') && !input.contains(';')) {
      return "ttwid=$input";
    }
    
    // 如果已经是ttwid=xxx格式
    if (input.startsWith('ttwid=') && !input.contains(';')) {
      return input;
    }
    
    return null;
  }
  
  /// 添加ttwid到Cookie池
  bool addToCookiePool(String input) {
    var ttwid = extractTtwid(input);
    if (ttwid == null || ttwid.isEmpty) return false;
    
    // 检查是否已存在
    if (cookiePool.contains(ttwid)) return false;
    
    cookiePool.add(ttwid);
    _saveCookiePool();
    setSite();
    return true;
  }
  
  /// 从Cookie池删除ttwid
  void removeFromCookiePool(int index) {
    if (index < 0 || index >= cookiePool.length) return;
    cookiePool.removeAt(index);
    _saveCookiePool();
    setSite();
  }
  
  /// 清空Cookie池并恢复默认
  void resetCookiePool() {
    cookiePool.value = List.from(DouyinSite.kDefaultCookiePool);
    _saveCookiePool();
    setSite();
  }
}
