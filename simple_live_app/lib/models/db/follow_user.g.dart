// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follow_user.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class FollowUserAdapter extends TypeAdapter<FollowUser> {
  @override
  final int typeId = 1;

  @override
  FollowUser read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    // 兼容旧版本数据（可能只有 7 个字段）
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
    );
  }

  @override
  void write(BinaryWriter writer, FollowUser obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.roomId)
      ..writeByte(2)
      ..write(obj.siteId)
      ..writeByte(3)
      ..write(obj.userName)
      ..writeByte(4)
      ..write(obj.face)
      ..writeByte(5)
      ..write(obj.addTime)
      ..writeByte(6)
      ..write(obj.tag)
      ..writeByte(7)
      ..write(obj.pinned)
      ..writeByte(8)
      ..write(obj.pinnedTime);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FollowUserAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
