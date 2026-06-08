// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'listening_history.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ListeningRecordAdapter extends TypeAdapter<ListeningRecord> {
  @override
  final int typeId = 2;

  @override
  ListeningRecord read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return ListeningRecord(
      albumId: fields[0] as String,
      trackTitle: fields[1] as String,
      playedAt: fields[2] as DateTime,
      durationSeconds: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, ListeningRecord obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.albumId)
      ..writeByte(1)
      ..write(obj.trackTitle)
      ..writeByte(2)
      ..write(obj.playedAt)
      ..writeByte(3)
      ..write(obj.durationSeconds);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ListeningRecordAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
