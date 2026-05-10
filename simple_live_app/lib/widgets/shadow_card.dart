import 'package:flutter/material.dart';
import 'package:get/get.dart';

class ShadowCard extends StatelessWidget {
  final Widget child;
  final double radius;
  final Function()? onTap;
  final Function()? onLongPress;
  const ShadowCard({
    required this.child,
    this.radius = 12.0,
    this.onTap,
    this.onLongPress,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: Get.isDarkMode
            ? [
                BoxShadow(
                  blurRadius: 8,
                  color: Colors.black.withAlpha(40),
                  offset: const Offset(0, 2),
                )
              ]
            : [
                BoxShadow(
                  blurRadius: 12,
                  color: Colors.black.withAlpha(30),
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  blurRadius: 4,
                  color: Colors.black.withAlpha(10),
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      child: Material(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(radius),
          onTap: onTap,
          onLongPress: onLongPress,
          child: child,
        ),
      ),
    );
  }
}
