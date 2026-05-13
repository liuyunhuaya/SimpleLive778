import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 让 [SingleChildScrollView] 在桌面端（Windows / Linux / macOS）能用
/// **鼠标拖拽 + 鼠标滚轮（含 Shift+滚轮纵向→横向）** 滚动的横向滚动包装。
///
/// 背景：
/// - Flutter 默认在桌面端只允许触屏拖拽，鼠标只能滚轮，导致直播间"关注 Tab"
///   平台分类条等横向按钮在 Windows 上只能看到一部分、无法滑动。
/// - 通过自定义 [ScrollBehavior]，把 [PointerDeviceKind.mouse] / `trackpad` /
///   `stylus` 都纳入"可拖拽"集合，并默认显示横向 [Scrollbar]，让用户既能
///   按住鼠标左键拖动，又能用滚轮滚动，同时保留触屏端原生体验。
class DesktopHorizontalScroll extends StatelessWidget {
  final Widget child;

  /// 是否显示横向滚动条（桌面端建议开启，触屏端通常自动隐藏）
  final bool showScrollbar;

  /// 自定义内边距
  final EdgeInsetsGeometry? padding;

  final ScrollController? controller;

  const DesktopHorizontalScroll({
    Key? key,
    required this.child,
    this.showScrollbar = true,
    this.padding,
    this.controller,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final ctrl = controller ?? ScrollController();
    Widget scrollView = SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      controller: ctrl,
      // BouncingScrollPhysics 在桌面端拖拽体验最自然
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      child: child,
    );

    if (showScrollbar) {
      scrollView = Scrollbar(
        controller: ctrl,
        thumbVisibility: false, // 仅滚动时显示，避免遮挡按钮
        thickness: 4,
        radius: const Radius.circular(2),
        child: scrollView,
      );
    }

    return ScrollConfiguration(
      behavior: const _DesktopDragScrollBehavior(),
      child: scrollView,
    );
  }
}

/// 允许鼠标 / 触控板 / 触屏 / 触控笔同时支持拖拽滚动的 ScrollBehavior。
/// 这是 Windows 端能用鼠标拖动横向条的关键。
class _DesktopDragScrollBehavior extends MaterialScrollBehavior {
  const _DesktopDragScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.stylus,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      };
}
