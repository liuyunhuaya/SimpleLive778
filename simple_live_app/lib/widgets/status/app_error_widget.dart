import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:simple_live_app/app/app_style.dart';
import 'package:lottie/lottie.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';

class AppErrorWidget extends StatelessWidget {
  final Function()? onRefresh;
  final String errorMsg;
  final String? fullErrorMsg;
  const AppErrorWidget({
    this.errorMsg = "", 
    this.fullErrorMsg,
    this.onRefresh, 
    Key? key
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        onTap: () {
          onRefresh?.call();
        },
        child: Padding(
          padding: AppStyle.edgeInsetsA12,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LottieBuilder.asset(
                'assets/lotties/error.json',
                width: 260,
                repeat: false,
              ),
              Text(
                errorMsg,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              AppStyle.vGap12,
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh),
                    label: const Text("点击刷新"),
                  ),
                  if (fullErrorMsg != null && fullErrorMsg!.isNotEmpty) ...[
                    AppStyle.hGap12,
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: fullErrorMsg!));
                        SmartDialog.showToast("错误信息已复制到剪贴板");
                      },
                      icon: const Icon(Icons.copy),
                      label: const Text("复制错误信息"),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
