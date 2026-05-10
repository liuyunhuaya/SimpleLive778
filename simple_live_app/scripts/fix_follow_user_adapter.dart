import 'dart:io';

/// 修复follow_user.g.dart的兼容性问题
/// 此脚本会在build_runner生成文件后自动修补兼容性代码
void main() {
  final file = File('lib/models/db/follow_user.g.dart');
  
  // 检查文件是否存在
  if (!file.existsSync()) {
    print('Warning: follow_user.g.dart not found, might be excluded from build_runner');
    // 不报错退出，因为可能已经有正确的版本
    exit(0);
  }
  
  print('Reading follow_user.g.dart...');
  var content = file.readAsStringSync();
  
  // 检查是否已经包含兼容性代码
  if (content.contains('fields.containsKey(')) {
    print('File already contains compatibility code, skipping patch');
    exit(0);
  }
  
  // 查找并替换read方法中的返回语句
  // 使用更精确的匹配模式
  final originalPattern = RegExp(
    r'return FollowUser\(\s*' +
    r'id: fields\[0\] as String,\s*' +
    r'roomId: fields\[1\] as String,\s*' +
    r'siteId: fields\[2\] as String,\s*' +
    r'userName: fields\[3\] as String,\s*' +
    r'face: fields\[4\] as String,\s*' +
    r'addTime: fields\[5\] as DateTime,\s*' +
    r'tag: fields\[6\] as String,\s*' +
    r'pinned: fields\[7\] as bool,\s*' +
    r'pinnedTime: fields\[8\] as DateTime\?,?\s*' +
    r'\);',
    multiLine: true,
    dotAll: true
  );
  
  final compatibleCode = '''    // 兼容旧版本数据（可能只有 6、7 或 9 个字段）
    return FollowUser(
      id: fields[0] as String,
      roomId: fields[1] as String,
      siteId: fields[2] as String,
      userName: fields[3] as String,
      face: fields[4] as String,
      addTime: fields[5] as DateTime,
      tag: fields.containsKey(6) ? (fields[6] as String? ?? "全部") : "全部",
      pinned: fields.containsKey(7) ? (fields[7] as bool? ?? false) : false,
      pinnedTime: fields.containsKey(8) ? fields[8] as DateTime? : null,
    );''';
  
  // 尝试第一种精确匹配
  if (originalPattern.hasMatch(content)) {
    print('Found exact match, applying patch...');
    content = content.replaceAllMapped(originalPattern, (match) => compatibleCode);
  } else {
    // 如果精确匹配失败，尝试更宽松的匹配
    print('Exact match failed, trying broader pattern...');
    final broaderPattern = RegExp(
      r'return FollowUser\([^;]+\);',
      multiLine: true,
      dotAll: true
    );
    
    if (broaderPattern.hasMatch(content)) {
      print('Found broader match, applying patch...');
      content = content.replaceAllMapped(broaderPattern, (match) {
        // 只替换read方法中的return语句
        if (match.group(0)!.contains('fields[0]')) {
          return compatibleCode;
        }
        return match.group(0)!;
      });
    } else {
      print('ERROR: Could not find FollowUser constructor to patch!');
      print('Please check the generated file format');
      exit(1);
    }
  }
  
  // 写回文件
  file.writeAsStringSync(content);
  print('Successfully patched follow_user.g.dart for backward compatibility');
  
  // 验证修补是否成功
  final patchedContent = file.readAsStringSync();
  if (!patchedContent.contains('fields.containsKey(')) {
    print('ERROR: Patch verification failed!');
    exit(1);
  }
  
  print('Patch verified successfully');
}
