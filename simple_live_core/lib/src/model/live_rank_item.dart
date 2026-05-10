/// 直播间榜单项目（贡献榜 / 亲密榜）
class LiveRankItem {
  /// 排名
  final int rank;

  /// 用户名
  final String userName;

  /// 头像
  final String avatar;

  /// 显示数值（如：1.2 万、888）
  final String score;

  /// 数值附加描述（如：距离上一名差 xx）
  final String? scoreDetail;

  /// 用户财富 / 粉丝等级（0 表示无）
  final int level;

  /// 等级文字描述（如：财富 25）
  final String? levelText;

  /// 等级图标URL（部分平台返回）
  final String? levelIcon;

  /// 粉丝牌等级（部分平台支持，0 表示无）
  final int fansLevel;

  /// 粉丝牌名称（部分平台支持）
  final String medalName;

  /// 粉丝牌图标URL（部分平台返回）
  final String? medalIcon;

  LiveRankItem({
    required this.rank,
    required this.userName,
    this.avatar = "",
    this.score = "",
    this.scoreDetail,
    this.level = 0,
    this.levelText,
    this.levelIcon,
    this.fansLevel = 0,
    this.medalName = "",
    this.medalIcon,
  });
}

/// 榜单结果
class LiveRankResult {
  /// 榜单标题（如：贡献榜、亲密榜）
  final String title;

  /// 榜单条目
  final List<LiveRankItem> items;

  LiveRankResult({
    required this.title,
    required this.items,
  });
}
