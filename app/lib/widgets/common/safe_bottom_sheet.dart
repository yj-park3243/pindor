import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// main_tab_screen.dart의 NavigationBar height와 일치
const double kAppBottomNavHeight = 64.0;

/// 모달 바텀시트 — 항상 루트 Navigator로 띄워 바텀 네비 위로 올라온다.
///
/// 바텀 네비 위로 시트가 올라오는 디자인을 일관되게 적용한다.
/// 바텀 네비 영역까지 시트 컨텐츠를 회피시키고 싶을 때만 [insetForBottomNav]를 true로.
Future<T?> showAppBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  bool isScrollControlled = false,
  bool isDismissible = true,
  bool enableDrag = true,
  bool useRootNavigator = true,
  ShapeBorder? shape,
  bool insetForBottomNav = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: backgroundColor,
    barrierColor: barrierColor,
    isScrollControlled: isScrollControlled,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    shape: shape,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: insetForBottomNav
            ? kAppBottomNavHeight + MediaQuery.of(ctx).padding.bottom
            : 0,
      ),
      child: builder(ctx),
    ),
  );
}

/// 카드 형태의 모달 시트 — 바텀 네비 위에 floating 카드로 표시한다.
///
/// confirm/alert 다이얼로그형 시트에 적합하다.
/// - 사방 둥근 모서리(20px)
/// - 좌우 마진(기본 16px)
/// - 음영(elevation 12)
/// - 바텀 네비 + safe area 위에 띄움
///
/// 호출부의 builder는 박스 색/borderRadius를 지정할 필요 없이 컨텐츠(Padding+Column 등)만 반환하면 된다.
Future<T?> showAppCardSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  Color? barrierColor,
  bool isDismissible = true,
  bool enableDrag = false,
  bool useRootNavigator = true,
  EdgeInsets margin = const EdgeInsets.fromLTRB(16, 0, 16, 12),
  double borderRadius = 20,
  double elevation = 12,
  bool insetForBottomNav = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: barrierColor,
    isScrollControlled: true,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
    useRootNavigator: useRootNavigator,
    builder: (ctx) {
      final bottomInset = insetForBottomNav
          ? kAppBottomNavHeight + MediaQuery.of(ctx).padding.bottom
          : MediaQuery.of(ctx).padding.bottom;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          margin.left,
          margin.top,
          margin.right,
          margin.bottom + bottomInset,
        ),
        child: Material(
          color: backgroundColor ?? const Color(0xFF1E1E1E),
          borderRadius: BorderRadius.circular(borderRadius),
          elevation: elevation,
          shadowColor: Colors.black.withValues(alpha: 0.6),
          clipBehavior: Clip.antiAlias,
          child: builder(ctx),
        ),
      );
    },
  );
}

/// CupertinoActionSheet/Cupertino 모달 팝업용 헬퍼.
/// 메인 탭 안에서 띄울 때 바텀 네비를 피하도록 보정한다.
Future<T?> showAppCupertinoModalPopup<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? barrierColor,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  bool insetForBottomNav = false,
}) {
  return showCupertinoModalPopup<T>(
    context: context,
    barrierColor: barrierColor ?? kCupertinoModalBarrierColor,
    barrierDismissible: barrierDismissible,
    useRootNavigator: useRootNavigator,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: insetForBottomNav
            ? kAppBottomNavHeight + MediaQuery.of(ctx).padding.bottom
            : 0,
      ),
      child: builder(ctx),
    ),
  );
}
