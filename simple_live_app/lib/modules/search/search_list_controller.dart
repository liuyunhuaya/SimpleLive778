import 'package:get/get.dart';
import 'package:simple_live_app/app/controller/app_settings_controller.dart';
import 'package:simple_live_app/app/controller/base_controller.dart';
import 'package:simple_live_app/app/sites.dart';
import 'package:simple_live_core/simple_live_core.dart';

class SearchListController extends BasePageController {
  String keyword = "";

  /// 搜索模式，0=直播间，1=主播
  var searchMode = 0.obs;
  final Site site;
  SearchListController(
    this.site,
  );

  @override
  Future refreshData() async {
    if (keyword.isEmpty) {
      return;
    }
    return await super.refreshData();
  }

  @override
  Future<List> getData(int page, int pageSize) async {
    if (keyword.isEmpty) {
      return [];
    }
    if (searchMode.value == 1) {
      // 搜索主播
      // 虎牙站点支持按开播状态排序
      if (site.liveSite is HuyaSite && 
          AppSettingsController.instance.huyaSearchAnchorSortByLive.value) {
        var huyaSite = site.liveSite as HuyaSite;
        var result = await huyaSite.searchAnchors(keyword, page: page, sortByLiveStatus: true);
        return result.items;
      }
      var result = await site.liveSite.searchAnchors(keyword, page: page);
      return result.items;
    }
    var result = await site.liveSite.searchRooms(keyword, page: page);

    return result.items;
  }

  void clear() {
    pageEmpty.value = false;
    list.clear();
  }
}
